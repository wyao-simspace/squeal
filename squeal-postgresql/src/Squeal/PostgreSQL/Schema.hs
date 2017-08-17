{-# LANGUAGE
    DataKinds
  , FlexibleContexts
  , FlexibleInstances
  , GADTs
  , MagicHash
  , MultiParamTypeClasses
  , OverloadedStrings
  , PolyKinds
  , RankNTypes
  , ScopedTypeVariables
  , TypeApplications
  , TypeFamilies
  , TypeOperators
#-}

module Squeal.PostgreSQL.Schema
  ( PGType (..)
  , PGNum (..)
  , PGIntegral
  , PGFloating
  , (:::)
  , Alias (Alias)
  , renderAlias
  , Aliased (As)
  , renderAliased
  , IsTableColumn (..)
  , NullityType (..)
  , ColumnType (..)
  , Grouping (..)
  , SameTypes
  , AllNotNull
  , NotAllNull
  , NullifyType
  , NullifyColumns
  , NullifyTables
  , BaseType
  , Create
  , Drop
  , Alter
  , Rename
  , Join
  , module GHC.OverloadedLabels
  , module GHC.TypeLits
  ) where

import Data.ByteString
import Data.Monoid
import Data.String
import GHC.Exts
import GHC.OverloadedLabels
import GHC.TypeLits

data PGType
  = PGbool
  | PGint2
  | PGint4
  | PGint8
  | PGnumeric
  | PGfloat4
  | PGfloat8
  | PGchar Nat
  | PGvarchar Nat
  | PGtext
  | PGbytea
  | PGtimestamp
  | PGtimestamptz
  | PGdate
  | PGtime
  | PGtimetz
  | PGinterval
  | PGuuid
  | PGinet
  | PGjson
  | PGjsonb

class PGNum (ty :: PGType) where
  decimal :: proxy ty -> Bool
instance PGNum 'PGint2 where decimal _ = False
instance PGNum 'PGint4 where decimal _ = False
instance PGNum 'PGint8 where decimal _ = False
instance PGNum 'PGnumeric where decimal _ = True
instance PGNum 'PGfloat4 where decimal _ = True
instance PGNum 'PGfloat8 where decimal _ = True

class PGNum ty => PGIntegral (ty :: PGType) where
instance PGIntegral 'PGint2
instance PGIntegral 'PGint4
instance PGIntegral 'PGint8

class PGNum ty => PGFloating (ty :: PGType) where
instance PGFloating 'PGnumeric
instance PGFloating 'PGfloat4
instance PGFloating 'PGfloat8

type (:::) (alias :: Symbol) (ty :: polykind) = '(alias,ty)

data Alias (alias :: Symbol) = Alias

renderAlias :: KnownSymbol alias => Alias alias -> ByteString
renderAlias = fromString . symbolVal

instance alias1 ~ alias2 => IsLabel alias1 (Alias alias2) where
  fromLabel = Alias

data Aliased expression aliased where
  As
    :: KnownSymbol alias
    => expression ty
    -> Alias alias
    -> Aliased expression (alias ::: ty)

renderAliased
  :: (forall ty. expression ty -> ByteString)
  -> Aliased expression aliased
  -> ByteString
renderAliased render (expression `As` alias) =
  render expression <> " AS " <> renderAlias alias

class IsTableColumn table column expression where
  (!) :: Alias table -> Alias column -> expression
  infixl 9 !
instance IsTableColumn table column (Alias table, Alias column) where (!) = (,)

data NullityType = Null PGType | NotNull PGType

data ColumnType = Optional NullityType | Required NullityType

data Grouping
  = Ungrouped
  | Grouped [(Symbol,Symbol)]

type family BaseType (ty :: ColumnType) where
  BaseType (optionality (nullity pg)) = pg

type family SameTypes columns0 columns1 :: Constraint where
  SameTypes '[] '[] = ()
  SameTypes ((column0 ::: ty0) ': columns0) ((column1 ::: ty1) ': columns1)
    = (ty0 ~ ty1, SameTypes columns0 columns1)

type family AllNotNull columns :: Constraint where
  AllNotNull '[] = ()
  AllNotNull ((column ::: (optionality ('NotNull ty))) ': columns)
    = AllNotNull columns

type family NotAllNull columns :: Constraint where
  NotAllNull ((column ::: (optionality ('NotNull ty))) ': columns) = ()
  NotAllNull ((column ::: (optionality ('Null ty))) ': columns)
    = NotAllNull columns

type family NullifyType (ty :: ColumnType) where
  NullifyType (optionality ('Null ty)) = optionality ('Null ty)
  NullifyType (optionality ('NotNull ty)) = optionality ('Null ty)

type family NullifyColumns columns where
  NullifyColumns '[] = '[]
  NullifyColumns ((column ::: ty) ': columns) =
    (column ::: NullifyType ty) ': NullifyColumns columns

type family NullifyTables tables where
  NullifyTables '[] = '[]
  NullifyTables ((column ::: ty) ': columns) =
    (column ::: NullifyColumns ty) ': NullifyTables columns

type family Create alias x xs where
  Create alias x '[] = '[alias ::: x]
  Create alias y (x ': xs) = x ': Create alias y xs

type family Drop alias xs where
  Drop alias ((alias ::: x) ': xs) = xs
  Drop alias (x ': xs) = x ': Drop alias xs

type family Alter alias xs x where
  Alter alias ((alias ::: x0) ': xs) x1 = (alias ::: x1) ': xs
  Alter alias (x0 ': xs) x1 = x0 ': Alter alias xs x1

type family Rename alias0 alias1 xs where
  Rename alias0 alias1 ((alias0 ::: x0) ': xs) = (alias1 ::: x0) ': xs
  Rename alias0 alias1 (x ': xs) = x ': Rename alias0 alias1 xs

type family Join xs ys where
  Join '[] ys = ys
  Join (x ': xs) ys = x ': Join xs ys