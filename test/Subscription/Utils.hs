{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Subscription.Utils
  ( SimulationState (..),
    simulate,
    expectedResponse,
    SubM,
    testResponse,
    inputsAreConsumed,
    storeIsEmpty,
    storedSingle,
    stored,
    storeSubscriptions,
    simulatePublish,
    apolloStart,
    apolloStop,
    apolloRes,
    apolloInit,
    testSimulation,
  )
where

import Control.Monad ((>>=))
import Control.Monad.State.Lazy
  ( StateT,
    runStateT,
    state,
  )
import Data.ByteString.Lazy.Char8
  ( ByteString,
  )
import Data.List
  ( sort,
  )
import Data.Maybe
  ( isJust,
  )
import Data.Morpheus
  ( App,
  )
import Data.Morpheus.Types
  ( Event,
  )
import Data.Morpheus.Types.Internal.Subscription
  ( ClientConnectionStore,
    Input (..),
    Scope (..),
    SessionID,
    WS,
    connect,
    connectionSessionIds,
    empty,
    publish,
    runStreamWS,
    streamApp,
    toList,
  )
import Data.Semigroup
  ( (<>),
  )
import Test.Tasty
  ( TestTree,
  )
import Test.Tasty.HUnit
  ( assertEqual,
    assertFailure,
    testCase,
  )
import Prelude
  ( ($),
    (.),
    (<$>),
    Eq (..),
    IO,
    Maybe (..),
    Show (..),
    length,
    lookup,
    null,
    otherwise,
    pure,
    snd,
  )

data SimulationState e = SimulationState
  { inputs :: [ByteString],
    outputs :: [ByteString],
    store :: ClientConnectionStore e (SubM e)
  }

type Store e = ClientConnectionStore e (SubM e)

type SubM e = StateT (SimulationState e) IO

addOutput :: ByteString -> SimulationState e -> ((), SimulationState e)
addOutput x (SimulationState i xs st) = ((), SimulationState i (xs <> [x]) st)

updateStore :: (Store e -> Store e) -> SimulationState e -> ((), SimulationState e)
updateStore up (SimulationState i o st) = ((), SimulationState i o (up st))

readInput :: SimulationState e -> (ByteString, SimulationState e)
readInput (SimulationState (i : ins) o s) = (i, SimulationState ins o s)
readInput (SimulationState [] o s) = ("<Error>", SimulationState [] o s)

wsApp ::
  App e (SubM e) ->
  Input WS ->
  SubM e ()
wsApp app =
  runStreamWS
    ScopeWS
      { update = state . updateStore,
        listener = state readInput,
        callback = state . addOutput
      }
    . streamApp app

simulatePublish ::
  Eq ch =>
  Event ch con ->
  SimulationState (Event ch con) ->
  IO (SimulationState (Event ch con))
simulatePublish event s = snd <$> runStateT (publish event (store s)) s

simulate ::
  App e (SubM e) ->
  Input WS ->
  SimulationState e ->
  IO (SimulationState e)
simulate _ _ s@SimulationState {inputs = []} = pure s
simulate api input s = runStateT (wsApp api input) s >>= simulate api input . snd

testSimulation ::
  (Input WS -> SimulationState e -> TestTree) ->
  [ByteString] ->
  App e (SubM e) ->
  IO TestTree
testSimulation test simInputs api = do
  input <- connect
  s <- simulate api input (SimulationState simInputs [] empty)
  pure $ test input s

expectedResponse :: [ByteString] -> [ByteString] -> IO ()
expectedResponse expected value
  | expected == value = pure ()
  | otherwise =
    assertFailure $ "expected: \n " <> show expected <> " \n but got: \n " <> show value

testResponse :: [ByteString] -> [ByteString] -> TestTree
testResponse expected =
  testCase
    "expected response"
    . expectedResponse
      expected

inputsAreConsumed :: [ByteString] -> TestTree
inputsAreConsumed =
  testCase "inputs are consumed"
    . assertEqual
      "input stream should be consumed"
      []

storeIsEmpty :: Store e -> TestTree
storeIsEmpty cStore
  | null (toList cStore) =
    testCase "connectionStore: is empty" $ pure ()
  | otherwise =
    testCase "connectionStore: is empty"
      $ assertFailure
      $ " must be empty but "
        <> show
          cStore

storedSingle :: Store e -> TestTree
storedSingle cStore
  | length (toList cStore) == 1 =
    testCase "stored single connection" $ pure ()
  | otherwise =
    testCase "stored single connection"
      $ assertFailure
      $ "connectionStore must store single connection"
        <> show
          cStore

stored :: Input WS -> Store e -> TestTree
stored (Init uuid) cStore
  | isJust (lookup uuid (toList cStore)) =
    testCase "stored connection" $ pure ()
  | otherwise =
    testCase "stored connection"
      $ assertFailure
      $ " must store connection \"" <> show uuid <> "\" but stored: "
        <> show
          cStore

storeSubscriptions ::
  Input WS ->
  [SessionID] ->
  Store e ->
  TestTree
storeSubscriptions
  (Init uuid)
  sids
  cStore =
    checkSession (lookup uuid (toList cStore))
    where
      checkSession (Just conn)
        | sort sids == sort (connectionSessionIds conn) =
          testCase "stored subscriptions" $ pure ()
        | otherwise =
          testCase "stored subscriptions"
            $ assertFailure
            $ " must store subscriptions with id \"" <> show sids <> "\" but stored: "
              <> show
                (connectionSessionIds conn)
      checkSession _ =
        testCase "stored connection"
          $ assertFailure
          $ " must store connection \"" <> show uuid <> "\" but: "
            <> show
              cStore

apolloStart :: ByteString -> ByteString -> ByteString
apolloStart query sid = "{\"id\":\"" <> sid <> "\",\"type\":\"start\",\"payload\":{\"variables\":{},\"operationName\":\"MySubscription\",\"query\":\"" <> query <> "\"}}"

apolloStop :: ByteString -> ByteString
apolloStop x = "{\"id\":\"" <> x <> "\",\"type\":\"stop\"}"

apolloRes :: ByteString -> ByteString -> ByteString
apolloRes sid value = "{\"id\":\"" <> sid <> "\",\"type\":\"data\",\"payload\":{\"data\":" <> value <> "}}"

apolloInit :: ByteString
apolloInit = "{ \"type\":\"connection_init\" }"
