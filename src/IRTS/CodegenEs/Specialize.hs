{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}

module IRTS.CodegenEs.Specialize
  ( SCtor
  , STest
  , SProj
  , specialCased
  , specialCall
  , qualifyN
  ) where

import Data.Char
import Data.List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import IRTS.CodegenEs.JsAST
import Idris.Core.TT

split :: Char -> String -> [String]
split c "" = [""]
split c (x:xs)
  | c == x = "" : split c xs
  | otherwise =
    let ~(h:t) = split c xs
    in ((x : h) : t)

qualify :: String -> Name -> Name
qualify "" n = n
qualify ns n = sNS n (reverse $ split '.' ns)

qualifyN :: String -> String -> Name
qualifyN ns n = qualify ns $ sUN n

-- special-cased constructors
type SCtor = [JsExpr] -> JsExpr

type STest = JsExpr -> JsExpr

type SProj = JsExpr -> Int -> JsExpr

constructorOptimizeDB :: Map.Map Name (SCtor, STest, SProj)
constructorOptimizeDB =
  Map.fromList
    [ item "Prelude.Bool" "True" (const $ JsBool True) id cantProj
    , item "Prelude.Bool" "False" (const $ JsBool False) falseTest cantProj
    -- , item "Prelude.List" "::" cons fillList uncons
    -- , item "Prelude.List" "Nil" nil emptyList cantProj
    -- , item "Prelude.Maybe" "Just" (\[x] -> x) notNoneTest justProj
    -- , item "Prelude.Maybe" "Nothing" (const $ JsUndefined) noneTest cantProj
    ]
    -- constructors
  where
    nil = const $ JsArray []
    cons [h, t] = JsMethod (JsArray [h]) "concat" [t]
    -- tests
    falseTest e = JsUniOp (T.pack "!") e
    emptyList e = JsBinOp "===" (JsProp e "length") (JsInt 0)
    fillList e = JsBinOp ">" (JsProp e "length") (JsInt 0)
    noneTest e = JsBinOp "===" e JsUndefined
    notNoneTest e = JsBinOp "!==" e JsUndefined
    -- projections
    justProj x n = x
    uncons x 1 = JsArrayProj (JsInt 0) x
    uncons x 2 = JsMethod x "slice" [JsInt 1]
    cantProj x j = error $ "This type should be projected"
    item :: String
         -> String
         -> SCtor
         -> STest
         -> SProj
         -> (Name, (SCtor, STest, SProj))
    item ns n ctor test match = (qualifyN ns n, (ctor, test, match))

specialCased :: Name -> Maybe (SCtor, STest, SProj)
specialCased n = Map.lookup n constructorOptimizeDB

-- special functions
type SSig = (Int, [JsExpr] -> JsExpr)

callSpecializeDB :: Map.Map Name (SSig)
callSpecializeDB =
  Map.fromList
    [ qb "Eq" "Int" "==" "==="
    , qb "Ord" "Int" "<" "<"
    , qb "Ord" "Int" ">" ">"
    , qb "Ord" "Int" "<=" "<="
    , qb "Ord" "Int" ">=" ">="
    , qb "Eq" "Double" "==" "==="
    , qb "Ord" "Double" "<" "<"
    , qb "Ord" "Double" ">" ">"
    , qb "Ord" "Double" "<=" "<="
    , qb "Ord" "Double" ">=" ">="
    ]
  where
    qb intf ty op jsop =
      ( qualify "Prelude.Interfaces" $
        SN $
        WhereN
          0
          (qualify "Prelude.Interfaces" $
           SN $ ImplementationN (qualifyN "Prelude.Interfaces" intf) [ty])
          (SN $ MethodN $ UN op)
      , (2, \[x, y] -> JsBinOp jsop x y))

specialCall :: Name -> Maybe SSig
specialCall n = Map.lookup n callSpecializeDB
