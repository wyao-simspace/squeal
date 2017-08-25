{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}
{-# LANGUAGE
    DataKinds
  , DeriveGeneric
  , FlexibleInstances
  , MultiParamTypeClasses
  , OverloadedLabels
  , OverloadedStrings
  , PartialTypeSignatures
  , TypeApplications
  , TypeOperators
  , TypeSynonymInstances
#-}

module Main (main,col1,col2) where

import Control.Category ((>>>))
import Control.Monad.Base
import Data.Function ((&))
import Data.Int
import Data.Monoid
import Generics.SOP hiding (from)
import Squeal.PostgreSQL

import qualified Data.ByteString.Char8 as Char8
import qualified GHC.Generics as GHC

type Schema =
  '[ "students" ::: '["name" ::: 'Required ('NotNull 'PGtext)]
   , "table1" :::
       '[ "col1" ::: 'Required ('NotNull 'PGint4)
        , "col2" ::: 'Required ('NotNull 'PGint4)
        ]
   ]

data Row = Row { col1 :: Int32, col2 :: Int32 }
  deriving (Show, GHC.Generic)
instance Generic Row
instance HasDatatypeInfo Row

main :: IO ()
main = do
  Char8.putStrLn "squeal"
  connectionString <- pure
    "host=localhost port=5432 dbname=exampledb"
  Char8.putStrLn $ "connecting to " <> connectionString
  connection0 <- connectdb connectionString
  Char8.putStrLn "setting up schema"
  connection1 <- flip execPQ (connection0 :: Connection '[]) $ define $
    createTable #students ((text & notNull) `As` #name :* Nil ) []
    >>>
    createTable #table1
      ((int4 & notNull) `As` #col1 :* (int4 & notNull) `As` #col2 :* Nil) []
  connection2 <- flip execPQ (connection1 :: Connection Schema) $ do
    let
      insert :: Manipulation Schema '[_,_,_,_] '[]
      insert =
        insertInto #table1
          ( Values
            (param @1 `As` #col1 :* param @2 `As` #col2 :* Nil)
            [param @3 `As` #col1 :* param @4 `As` #col2 :* Nil]
          ) OnConflictDoNothing (Returning Nil)
    liftBase $ Char8.putStrLn "manipulating"
    _insertResult <- manipulateParams insert
      (1::Int32,2::Int32,3::Int32,4::Int32)
    liftBase $ Char8.putStrLn "querying"
    result <- runQuery $
      selectStar (from (Table (#table1 `As` #table1)))
    value00 <- getValue (RowNumber 0) (columnNumber @0) result
    value01 <- getValue (RowNumber 0) (columnNumber @1) result
    value10 <- getValue (RowNumber 1) (columnNumber @0) result
    value11 <- getValue (RowNumber 1) (columnNumber @1) result
    row0 <- getRow (RowNumber 0) result
    row1 <- getRow (RowNumber 1) result
    rows <- getRows result
    liftBase $ do
      print (value00 :: Int32)
      print (value01 :: Int32)
      print (value10 :: Int32)
      print (value11 :: Int32)
      print (row0 :: Row)
      print (row1 :: Row)
      print (rows :: [Row])
  Char8.putStrLn "tearing down schema"
  connection3 <- flip execPQ (connection2 :: Connection Schema) $ define $
    dropTable #table1 >>> dropTable #students
  finish (connection3 :: Connection '[])
