{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE GADTs           #-}
{-# LANGUAGE KindSignatures  #-}
{-# LANGUAGE QuasiQuotes     #-}
{-# LANGUAGE TemplateHaskell #-}
module PEG.Examples.Arith
  ( Exp (..)
  , evalExp
  , showExp
  , arith
  ) where

import PEG.QQ (pegGrammar)

data Exp
  = Lit Int
  | Neg Exp
  | Add Exp Exp
  | Sub Exp Exp
  | Mul Exp Exp
  | Div Exp Exp
  deriving (Eq, Show)

evalExp :: Exp -> Int
evalExp (Lit n)   = n
evalExp (Neg e)   = negate (evalExp e)
evalExp (Add a b) = evalExp a + evalExp b
evalExp (Sub a b) = evalExp a - evalExp b
evalExp (Mul a b) = evalExp a * evalExp b
evalExp (Div a b) = evalExp a `div` evalExp b

showExp :: Exp -> String
showExp (Lit n)   = show n
showExp (Neg e)   = "(-" ++ showExp e ++ ")"
showExp (Add a b) = bin "+" a b
showExp (Sub a b) = bin "-" a b
showExp (Mul a b) = bin "*" a b
showExp (Div a b) = bin "/" a b

bin :: String -> Exp -> Exp -> String
bin op a b = "(" ++ showExp a ++ " " ++ op ++ " " ++ showExp b ++ ")"

addOp :: Exp -> (Char, Exp) -> Exp
addOp l ('+', r) = Add l r
addOp l ('-', r) = Sub l r
addOp l ('*', r) = Mul l r
addOp l ('/', r) = Div l r
addOp _ (c  , _) = error ("addOp: unexpected operator " ++ show c)

[pegGrammar|
  %name   arith
  %stream String
  %start  expr

  expr   :: Exp <- t:term ts:(o:[+-] u:term { (o, u) })*
                     { foldl addOp t ts }
  term   :: Exp <- f:factor fs:(o:[*/] g:factor { (o, g) })*
                     { foldl addOp f fs }
  factor :: Exp <- n:number { n }
                 / '(' e:expr ')' { e }
                 / '-' f:factor { Neg f }
  number :: Exp <- ds:[0-9]+ { Lit (read ds :: Int) }
|]
