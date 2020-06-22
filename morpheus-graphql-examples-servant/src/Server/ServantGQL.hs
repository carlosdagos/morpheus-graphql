{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Server.ServantGQL
  ( GQLEndpoint,
    serveGQLEndpoint,
  )
where

import Control.Monad.Trans (MonadIO, liftIO)
import qualified Data.ByteString.Lazy as L
  ( readFile,
  )
import Data.ByteString.Lazy.Char8
  ( ByteString,
  )
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Morpheus.Types (GQLRequest, GQLResponse)
import Data.Typeable (Typeable)
import GHC.TypeLits
import Network.HTTP.Media ((//), (/:))
import Servant
  ( (:<|>) (..),
    (:>),
    Accept (..),
    Get,
    JSON,
    MimeRender (..),
    Post,
    ReqBody,
    Server,
  )

data HTML deriving (Typeable)

instance Accept HTML where
  contentTypes _ = "text" // "html" /: ("charset", "utf-8") :| ["text" // "html"]

instance MimeRender HTML ByteString where
  mimeRender _ = id

type GQLAPI = ReqBody '[JSON] GQLRequest :> Post '[JSON] GQLResponse

type GQLEndpoint (name :: Symbol) = name :> (GQLAPI :<|> Get '[HTML] ByteString)

serveGQLEndpoint :: (GQLRequest -> IO GQLResponse) -> Server (GQLEndpoint name)
serveGQLEndpoint app = (liftIO . app) :<|> gqlPlayground

gqlPlayground :: (Monad m, MonadIO m) => m ByteString
gqlPlayground = liftIO $ L.readFile "morpheus-graphql-examples-servant/assets/index.html"