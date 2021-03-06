{-# LANGUAGE DeriveLift #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Data.Morpheus.Types.Internal.AST
  ( -- BASE
    Ref (..),
    Position (..),
    Message,
    anonymousRef,
    FieldName (..),
    Description,
    Stage,
    CONST,
    VALID,
    RAW,
    -- VALUE
    Value (..),
    ScalarValue (..),
    Object,
    GQLValue (..),
    replaceValue,
    decodeScientific,
    convertToJSONName,
    convertToHaskellName,
    RawValue,
    ValidValue,
    RawObject,
    ValidObject,
    ResolvedObject,
    ResolvedValue,
    splitDuplicates,
    removeDuplicates,
    -- Selection
    Argument (..),
    Arguments,
    SelectionSet,
    SelectionContent (..),
    Selection (..),
    Fragments,
    Fragment (..),
    -- OPERATION
    Operation (..),
    Variable (..),
    VariableDefinitions,
    DefaultValue,
    getOperationName,
    -- DSL
    ScalarDefinition (..),
    DataEnum,
    FieldsDefinition,
    ArgumentDefinition,
    DataUnion,
    ArgumentsDefinition (..),
    FieldDefinition (..),
    InputFieldsDefinition,
    TypeContent (..),
    TypeDefinition (..),
    Schema (..),
    DataTypeWrapper (..),
    TypeKind (..),
    DataFingerprint (..),
    TypeWrapper (..),
    TypeRef (..),
    DataEnumValue (..),
    OperationType (..),
    QUERY,
    MUTATION,
    SUBSCRIPTION,
    Directive (..),
    ConsD (..),
    TypeCategory,
    DataInputUnion,
    VariableContent (..),
    TypeLib,
    initTypeLib,
    kindOf,
    toNullable,
    isObject,
    toHSWrappers,
    isNullable,
    toGQLWrapper,
    isWeaker,
    isSubscription,
    isOutputObject,
    isNotSystemTypeName,
    isEntNode,
    mkEnumContent,
    createScalarType,
    mkUnionContent,
    mkTypeRef,
    mkInputUnionFields,
    fieldVisibility,
    lookupDeprecated,
    lookupDeprecatedReason,
    lookupWith,
    -- Template Haskell
    hsTypeName,
    -- LOCAL
    GQLQuery (..),
    Variables,
    unsafeFromFields,
    OrdMap (..),
    GQLError (..),
    GQLErrors,
    ObjectEntry (..),
    UnionTag (..),
    __inputname,
    internalFingerprint,
    ANY,
    IN,
    OUT,
    OBJECT,
    IMPLEMENTABLE,
    fromAny,
    toAny,
    TRUE,
    FALSE,
    TypeName (..),
    Token,
    Msg (..),
    intercalateName,
    toFieldName,
    TypeNameRef (..),
    isEnum,
    fieldsToArguments,
    mkCons,
    mkConsEnum,
    Directives,
    DirectiveDefinitions,
    DirectiveDefinition (..),
    DirectiveLocation (..),
    FieldContent (..),
    fieldContentArgs,
    mkInputValue,
    mkType,
    TypeNameTH (..),
    isOutput,
    mkObjectField,
    UnionMember (..),
    mkUnionMember,
    RawTypeDefinition (..),
    RootOperationTypeDefinition (..),
    UnionSelection,
    SchemaDefinition (..),
    buildSchema,
    InternalError (..),
    ValidationError (..),
    msgInternal,
    getOperationDataType,
    Typed (Typed),
    typed,
    untyped,
    msgValidation,
    withPosition,
    ValidationErrors,
    toGQLError,
    ELEM,
    LEAF,
    REQUIRE_IMPLEMENTABLE,
    ToCategory (..),
    FromCategory (..),
    possibleTypes,
    possibleInterfaceTypes,
    mkField,
    isTypeDefined,
    safeDefineType,
  )
where

import Data.HashMap.Lazy (HashMap)
-- Morpheus

import Data.Morpheus.Ext.OrdMap
import Data.Morpheus.Types.Internal.AST.Base
import Data.Morpheus.Types.Internal.AST.DirectiveLocation (DirectiveLocation (..))
import Data.Morpheus.Types.Internal.AST.Fields
import Data.Morpheus.Types.Internal.AST.Selection
import Data.Morpheus.Types.Internal.AST.Stage
import Data.Morpheus.Types.Internal.AST.TH
import Data.Morpheus.Types.Internal.AST.TypeCategory
import Data.Morpheus.Types.Internal.AST.TypeSystem
import Data.Morpheus.Types.Internal.AST.Value
import Language.Haskell.TH.Syntax (Lift)
import Prelude (Show)

type Variables = HashMap FieldName ResolvedValue

data GQLQuery = GQLQuery
  { inputVariables :: [(FieldName, ResolvedValue)],
    operation :: Operation RAW,
    fragments :: Fragments RAW
  }
  deriving (Show, Lift)
