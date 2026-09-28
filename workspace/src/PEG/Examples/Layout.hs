{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE GADTs           #-}
{-# LANGUAGE KindSignatures  #-}
{-# LANGUAGE QuasiQuotes     #-}
{-# LANGUAGE TemplateHaskell #-}
module PEG.Examples.Layout
  ( DoStmt (..)
  , doExp
  , layoutOpts
  ) where

import PEG
import PEG.QQ (pegGrammar)

data DoStmt
  = Atom   String
  | Nested [DoStmt]
  deriving (Eq, Show)

[pegGrammar|
  %name   doExp
  %stream String
  %start  start

  start  :: [DoStmt] <- ws d:doexp ws !. { d }
  doexp  :: [DoStmt] <- "do" b:(i:istmts { i } / j:stmts { j }) { b }
  istmts :: [DoStmt] <- ss:(ws st:|s:stmt|)+^> { ss }
  stmts  :: [DoStmt] <- r:(ws '{' ws s:stmt ss:(ws ';' ws t:stmt { t })* ws '}' { s : ss })^~
  stmt   :: DoStmt   <- d:doexp { Nested d } / n:name { Atom n }
  name   :: String   <- cs:[a-z]+ { cs }
  ws     :: ()       <- [ \t\r\n]*_~
|]

layoutOpts :: Opts
layoutOpts = defaultOpts { optTokenMode = relD geR }
