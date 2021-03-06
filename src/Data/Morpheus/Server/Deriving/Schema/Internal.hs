{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Data.Morpheus.Server.Deriving.Schema.Internal
  ( KindedProxy (..),
    KindedType (..),
    builder,
    inputType,
    outputType,
    setProxyType,
    unpackMs,
    UpdateDef (..),
    withObject,
    TyContentM,
    asObjectType,
    fromSchema,
    updateByContent,
  )
where

-- MORPHEUS

import Control.Applicative (Applicative (..))
import Control.Monad.Fail (fail)
import Data.Foldable (concatMap, traverse_)
import Data.Functor (($>), (<$>), Functor (..))
import Data.List (partition)
import qualified Data.Map as M
import Data.Maybe (Maybe (..), fromMaybe)
import Data.Morpheus.Error (globalErrorMessage)
import Data.Morpheus.Internal.Utils
  ( Failure (..),
    empty,
    singleton,
  )
import Data.Morpheus.Server.Deriving.Utils
  ( ConsRep (..),
    FieldRep (..),
    ResRep (..),
    fieldTypeName,
    isEmptyConstraint,
    isUnionRef,
  )
import Data.Morpheus.Server.Types.GQLType
  ( GQLType (..),
    TypeData (..),
  )
import Data.Morpheus.Server.Types.SchemaT
  ( SchemaT,
    insertType,
    updateSchema,
  )
import Data.Morpheus.Types.Internal.AST
  ( CONST,
    DataEnumValue (..),
    DataFingerprint (..),
    DataUnion,
    Description,
    Directives,
    ELEM,
    FieldContent (..),
    FieldDefinition (..),
    FieldName,
    FieldName (..),
    FieldsDefinition,
    IN,
    LEAF,
    OBJECT,
    OUT,
    Schema (..),
    TRUE,
    Token,
    TypeCategory,
    TypeContent (..),
    TypeDefinition (..),
    TypeName (..),
    UnionMember (..),
    VALID,
    mkEnumContent,
    mkField,
    mkInputValue,
    mkType,
    mkUnionMember,
    msg,
    unsafeFromFields,
  )
import Data.Morpheus.Types.Internal.Resolving
  ( Eventless,
    Result (..),
  )
import Data.Proxy (Proxy (..))
import Data.Semigroup ((<>))
import Data.Traversable (traverse)
import Language.Haskell.TH (Exp, Q)
import Prelude
  ( ($),
    (.),
    Bool (..),
    Show (..),
    map,
    null,
    otherwise,
    sequence,
  )

-- | context , like Proxy with multiple parameters
-- * 'kind': object, scalar, enum ...
-- * 'a': actual gql type
data KindedProxy k a
  = KindedProxy

data KindedType (cat :: TypeCategory) a where
  InputType :: KindedType IN a
  OutputType :: KindedType OUT a

-- converts:
--   f a -> KindedType IN a
-- or
--  f k a -> KindedType IN a
inputType :: f a -> KindedType IN a
inputType _ = InputType

outputType :: f a -> KindedType OUT a
outputType _ = OutputType

deriving instance Show (KindedType cat a)

setProxyType :: f b -> kinded k a -> KindedProxy k b
setProxyType _ _ = KindedProxy

fromSchema :: Eventless (Schema VALID) -> Q Exp
fromSchema Success {} = [|()|]
fromSchema Failure {errors} = fail (show errors)

withObject :: (GQLType a) => KindedType c a -> TypeContent TRUE any s -> SchemaT (FieldsDefinition c s)
withObject InputType DataInputObject {inputObjectFields} = pure inputObjectFields
withObject OutputType DataObject {objectFields} = pure objectFields
withObject x _ = failureOnlyObject x

asObjectType ::
  GQLType a =>
  (f2 a -> SchemaT (FieldsDefinition OUT CONST)) ->
  f2 a ->
  SchemaT (TypeDefinition OBJECT CONST)
asObjectType f proxy = (`mkObjectType` gqlTypeName (__type proxy)) <$> f proxy

mkObjectType :: FieldsDefinition OUT CONST -> TypeName -> TypeDefinition OBJECT CONST
mkObjectType fields typeName = mkType typeName (DataObject [] fields)

failureOnlyObject :: forall c a b. (GQLType a) => KindedType c a -> SchemaT b
failureOnlyObject _ =
  failure
    $ globalErrorMessage
    $ msg (gqlTypeName $ __type (Proxy @a)) <> " should have only one nonempty constructor"

type TyContentM kind = (SchemaT (Maybe (FieldContent TRUE kind CONST)))

type TyContent kind = Maybe (FieldContent TRUE kind CONST)

unpackM :: FieldRep (TyContentM k) -> SchemaT (FieldRep (TyContent k))
unpackM FieldRep {..} =
  FieldRep fieldSelector fieldTypeRef fieldIsObject
    <$> fieldValue

unpackCons :: ConsRep (TyContentM k) -> SchemaT (ConsRep (TyContent k))
unpackCons ConsRep {..} = ConsRep consName <$> traverse unpackM consFields

unpackMs :: [ConsRep (TyContentM k)] -> SchemaT [ConsRep (TyContent k)]
unpackMs = traverse unpackCons

builder ::
  forall kind (a :: *).
  GQLType a =>
  KindedType kind a ->
  [ConsRep (TyContent kind)] ->
  SchemaT (TypeContent TRUE kind CONST)
builder scope [ConsRep {consFields}] = buildObj <$> sequence (implements (Proxy @a))
  where
    buildObj interfaces = wrapFields interfaces scope (mkFieldsDefinition consFields)
builder scope cons = genericUnion scope cons
  where
    proxy = Proxy @a
    typeData = __type proxy
    genericUnion InputType = buildInputUnion typeData
    genericUnion OutputType = buildUnionType typeData DataUnion (DataObject [])

class UpdateDef value where
  updateDef :: GQLType a => f a -> value -> value

instance UpdateDef (TypeContent TRUE c CONST) where
  updateDef proxy DataObject {objectFields = fields, ..} =
    DataObject {objectFields = fmap (updateDef proxy) fields, ..}
  updateDef proxy DataInputObject {inputObjectFields = fields} =
    DataInputObject {inputObjectFields = fmap (updateDef proxy) fields, ..}
  updateDef proxy DataInterface {interfaceFields = fields} =
    DataInterface {interfaceFields = fmap (updateDef proxy) fields, ..}
  updateDef proxy (DataEnum enums) = DataEnum $ fmap (updateDef proxy) enums
  updateDef _ x = x

instance GetFieldContent cat => UpdateDef (FieldDefinition cat CONST) where
  updateDef proxy FieldDefinition {fieldName, fieldType, fieldContent} =
    FieldDefinition
      { fieldName,
        fieldDescription = lookupDescription (readName fieldName) proxy,
        fieldDirectives = lookupDirectives (readName fieldName) proxy,
        fieldContent = getFieldContent fieldName fieldContent proxy,
        ..
      }

instance UpdateDef (DataEnumValue CONST) where
  updateDef proxy DataEnumValue {enumName} =
    DataEnumValue
      { enumName,
        enumDescription = lookupDescription (readTypeName enumName) proxy,
        enumDirectives = lookupDirectives (readTypeName enumName) proxy
      }

lookupDescription :: GQLType a => Token -> f a -> Maybe Description
lookupDescription name = (name `M.lookup`) . getDescriptions

lookupDirectives :: GQLType a => Token -> f a -> Directives CONST
lookupDirectives name = fromMaybe [] . (name `M.lookup`) . getDirectives

class GetFieldContent c where
  getFieldContent :: GQLType a => FieldName -> Maybe (FieldContent TRUE c CONST) -> f a -> Maybe (FieldContent TRUE c CONST)

instance GetFieldContent IN where
  getFieldContent name val proxy =
    case name `M.lookup` getFieldContents proxy of
      Just (Just x, _) -> Just (DefaultInputValue x)
      _ -> val

instance GetFieldContent OUT where
  getFieldContent name args proxy =
    case name `M.lookup` getFieldContents proxy of
      Just (_, Just x) -> Just (FieldArgs x)
      _ -> args

updateByContent ::
  GQLType a =>
  (f kind a -> SchemaT (TypeContent TRUE cat CONST)) ->
  f kind a ->
  SchemaT ()
updateByContent f proxy =
  updateSchema
    (gqlTypeName $ __type proxy)
    (gqlFingerprint $ __type proxy)
    deriveD
    proxy
  where
    deriveD _ = buildType proxy <$> f proxy

analyseRep :: TypeName -> [ConsRep (Maybe (FieldContent TRUE kind CONST))] -> ResRep (Maybe (FieldContent TRUE kind CONST))
analyseRep baseName cons =
  ResRep
    { enumCons = fmap consName enumRep,
      unionRef = fieldTypeName <$> concatMap consFields unionRefRep,
      unionRecordRep
    }
  where
    (enumRep, left1) = partition isEmptyConstraint cons
    (unionRefRep, unionRecordRep) = partition (isUnionRef baseName) left1

buildInputUnion ::
  TypeData ->
  [ConsRep (Maybe (FieldContent TRUE IN CONST))] ->
  SchemaT (TypeContent TRUE IN CONST)
buildInputUnion TypeData {gqlTypeName, gqlFingerprint} =
  mkInputUnionType gqlFingerprint . analyseRep gqlTypeName

buildUnionType ::
  (ELEM LEAF kind ~ TRUE) =>
  TypeData ->
  (DataUnion CONST -> TypeContent TRUE kind CONST) ->
  (FieldsDefinition kind CONST -> TypeContent TRUE kind CONST) ->
  [ConsRep (Maybe (FieldContent TRUE kind CONST))] ->
  SchemaT (TypeContent TRUE kind CONST)
buildUnionType typeData wrapUnion wrapObject =
  mkUnionType typeData wrapUnion wrapObject . analyseRep (gqlTypeName typeData)

mkInputUnionType :: DataFingerprint -> ResRep (Maybe (FieldContent TRUE IN CONST)) -> SchemaT (TypeContent TRUE IN CONST)
mkInputUnionType _ ResRep {unionRef = [], unionRecordRep = [], enumCons} = pure $ mkEnumContent enumCons
mkInputUnionType baseFingerprint ResRep {unionRef, unionRecordRep, enumCons} = DataInputUnion <$> typeMembers
  where
    typeMembers :: SchemaT [UnionMember IN CONST]
    typeMembers = withMembers <$> buildUnions wrapInputObject baseFingerprint unionRecordRep
      where
        withMembers unionMembers = fmap mkUnionMember (unionRef <> unionMembers) <> fmap (`UnionMember` False) enumCons
    wrapInputObject :: (FieldsDefinition IN CONST -> TypeContent TRUE IN CONST)
    wrapInputObject = DataInputObject

mkUnionType ::
  (ELEM LEAF kind ~ TRUE) =>
  TypeData ->
  (DataUnion CONST -> TypeContent TRUE kind CONST) ->
  (FieldsDefinition kind CONST -> TypeContent TRUE kind CONST) ->
  ResRep (Maybe (FieldContent TRUE kind CONST)) ->
  SchemaT (TypeContent TRUE kind CONST)
mkUnionType _ _ _ ResRep {unionRef = [], unionRecordRep = [], enumCons} = pure $ mkEnumContent enumCons
mkUnionType typeData@TypeData {gqlFingerprint} wrapUnion wrapObject ResRep {unionRef, unionRecordRep, enumCons} = wrapUnion . map mkUnionMember <$> typeMembers
  where
    typeMembers = do
      enums <- buildUnionEnum wrapObject typeData enumCons
      unions <- buildUnions wrapObject gqlFingerprint unionRecordRep
      pure (unionRef <> enums <> unions)

wrapFields :: [TypeName] -> KindedType kind a -> FieldsDefinition kind CONST -> TypeContent TRUE kind CONST
wrapFields _ InputType = DataInputObject
wrapFields interfaces OutputType = DataObject interfaces

mkFieldsDefinition :: [FieldRep (Maybe (FieldContent TRUE kind CONST))] -> FieldsDefinition kind CONST
mkFieldsDefinition = unsafeFromFields . fmap fieldByRep

fieldByRep :: FieldRep (Maybe (FieldContent TRUE kind CONST)) -> FieldDefinition kind CONST
fieldByRep FieldRep {fieldSelector, fieldTypeRef, fieldValue} =
  mkField fieldValue fieldSelector fieldTypeRef

buildUnions ::
  (FieldsDefinition kind CONST -> TypeContent TRUE kind CONST) ->
  DataFingerprint ->
  [ConsRep (Maybe (FieldContent TRUE kind CONST))] ->
  SchemaT [TypeName]
buildUnions wrapObject baseFingerprint cons =
  traverse_ buildURecType cons $> fmap consName cons
  where
    buildURecType = insertType . buildUnionRecord wrapObject baseFingerprint

buildUnionEnum ::
  (FieldsDefinition cat CONST -> TypeContent TRUE cat CONST) ->
  TypeData ->
  [TypeName] ->
  SchemaT [TypeName]
buildUnionEnum wrapObject TypeData {gqlTypeName, gqlFingerprint} enums = updates $> members
  where
    members
      | null enums = []
      | otherwise = [enumTypeWrapperName]
    enumTypeName = gqlTypeName <> "Enum"
    enumTypeWrapperName = enumTypeName <> "Object"
    -------------------------
    updates :: SchemaT ()
    updates
      | null enums = pure ()
      | otherwise =
        buildEnumObject wrapObject enumTypeWrapperName gqlFingerprint enumTypeName
          *> buildEnum enumTypeName gqlFingerprint enums

buildType :: GQLType a => f a -> TypeContent TRUE cat CONST -> TypeDefinition cat CONST
buildType proxy typeContent =
  TypeDefinition
    { typeName = gqlTypeName typeData,
      typeFingerprint = gqlFingerprint typeData,
      typeDescription = description proxy,
      typeDirectives = [],
      typeContent
    }
  where
    typeData = __type proxy

buildUnionRecord ::
  (FieldsDefinition kind CONST -> TypeContent TRUE kind CONST) ->
  DataFingerprint ->
  ConsRep (Maybe (FieldContent TRUE kind CONST)) ->
  TypeDefinition kind CONST
buildUnionRecord wrapObject typeFingerprint ConsRep {consName, consFields} =
  mkSubType consName typeFingerprint (wrapObject $ mkFieldsDefinition consFields)

buildEnum :: TypeName -> DataFingerprint -> [TypeName] -> SchemaT ()
buildEnum typeName typeFingerprint tags =
  insertType
    ( mkSubType typeName typeFingerprint (mkEnumContent tags) ::
        TypeDefinition LEAF CONST
    )

buildEnumObject ::
  (FieldsDefinition cat CONST -> TypeContent TRUE cat CONST) ->
  TypeName ->
  DataFingerprint ->
  TypeName ->
  SchemaT ()
buildEnumObject wrapObject typeName typeFingerprint enumTypeName =
  insertType $
    mkSubType
      typeName
      typeFingerprint
      ( wrapObject
          $ singleton
          $ mkInputValue "enum" [] enumTypeName
      )

mkSubType :: TypeName -> DataFingerprint -> TypeContent TRUE k CONST -> TypeDefinition k CONST
mkSubType typeName typeFingerprint typeContent =
  TypeDefinition
    { typeName,
      typeFingerprint,
      typeDescription = Nothing,
      typeDirectives = empty,
      typeContent
    }
