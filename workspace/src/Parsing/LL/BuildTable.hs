module Parsing.LL.BuildTable
  ( ParseTable
  , ParseAction (..)
  , buildParseTable
  , printParseTable
  ) where

import Data.List (intercalate, (\\))
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (fromMaybe)

import Parsing.First
import Parsing.Follow
import Parsing.Grammar

-- Types

type ParseTable = Map (String, String) ParseAction

data ParseAction
  = Derive Production   -- ^ use this production
  | Accept              -- ^ accept the input
  | Error               -- ^ syntax error
  deriving (Show, Eq)

-- Table construction

-- Build the LL(1) parse table for a grammar.
-- Raises an error if the grammar is not LL(1).
buildParseTable :: Grammar -> ParseTable
buildParseTable g =
    foldl (addProduction g firstSets followSets) (initialTable g) (allProductions g)
  where
    firstSets  = computeFirstSets g
    followSets = computeFollowSets g firstSets

-- All (lhs, production) pairs in the grammar.
allProductions :: Grammar -> [(String, Production)]
allProductions g =
    [(lhs, prod) | (lhs, prods) <- Map.toList g, prod <- prods]

-- Table filled with Error entries for every (non-terminal, terminal) pair.
initialTable :: Grammar -> ParseTable
initialTable g =
    Map.fromList [((nt, t), Error) | nt <- nonTerminals g
                                   , t  <- terminals g ++ ["$"]]

-- Add the entries for one production to the table.
--
-- For  A → α:
--   • for each terminal  a ∈ FIRST(α) \ {λ}  set  table[A, a] = Derive α
--   • if λ ∈ FIRST(α), for each terminal  b ∈ FOLLOW(A)  set  table[A, b] = Derive α
addProduction :: Grammar -> FirstSet -> FollowSet
              -> ParseTable -> (String, Production) -> ParseTable
addProduction g firstSets followSets table (lhs, prod) =
    foldl insertEntry table entries
  where
    firstAlpha = firstForSequence g firstSets prod
    followLhs  = fromMaybe [] (Map.lookup lhs followSets)

    entries :: [String]
    entries = (firstAlpha \\ ["λ"])
           ++ if "λ" `elem` firstAlpha then followLhs else []

    insertEntry tbl a =
      case Map.lookup (lhs, a) tbl of
        Just Error -> Map.insert (lhs, a) (Derive prod) tbl
        Just _     -> error $ "Grammar is not LL(1): conflict at ("
                           ++ lhs ++ ", " ++ a ++ ")"
        Nothing    -> tbl

-- Pretty-printing

printParseTable :: Grammar -> IO ()
printParseTable g = do
    putStrLn "LL(1) Parse Table:"
    let tbl   = buildParseTable g
        nts   = nonTerminals g
        ts    = terminals g ++ ["$"]
        width = 12
        pad s = take width (s ++ replicate width ' ')
    putStrLn $ replicate width ' ' ++ concatMap pad ts
    mapM_ (\nt -> do
        putStr (pad nt)
        mapM_ (\t ->
            putStr $ pad $ case Map.lookup (nt, t) tbl of
                Just (Derive prod) -> showProd prod
                Just Accept        -> "acc"
                _                  -> "-"
            ) ts
        putStrLn "") nts
  where
    showProd []   = "λ"
    showProd prod = intercalate " " (map symbolString prod)
