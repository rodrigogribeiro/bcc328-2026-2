module Parsing.LR.SLR.BuildTable
  ( constructSLRTable
  , parseSLR
  , Conflict (..)
  , checkConflicts
  , printSLRTable
  ) where

import Data.List (sort)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Maybe (fromMaybe)

import Parsing.First
import Parsing.Follow
import Parsing.Grammar
import Parsing.LR.LRParser
import Parsing.LR.LR0.BuildTable
    ( Item (..), State
    , goto, nextSymbols, findStateIndex, buildLR0States
    )


-- SLR Parsing Table Construction
--
-- The only difference from LR(0) is the reduce step:
--   LR(0)  adds Reduce(A→α) on ALL terminals.
--   SLR(1) adds Reduce(A→α) ONLY for terminals in FOLLOW(A).
--
-- This resolves many shift-reduce conflicts that LR(0) cannot handle.

buildSLRParsingTable :: Grammar -> FollowSet -> [State] -> ParsingTable
buildSLRParsingTable g followSets sts = ParsingTable actions gotos
  where
    startSym = head (nonTerminals g)
    g'       = Map.insert "S'" [[NonTerminal startSym]] g

    actions = Map.fromList $ concat
        [ buildActions i state | (i, state) <- zip [0..] sts ]

    gotos = Map.fromList $ concat
        [ buildGotos i state | (i, state) <- zip [0..] sts ]

    buildActions i state = shiftA ++ reduceA ++ acceptA
      where
        shiftA =
            [ ((i, t), Shift j)
            | Terminal t <- nextSymbols state
            , not (isLambda (Terminal t))
            , let nextSt = goto g' state (Terminal t)
            , Just j <- [findStateIndex sts nextSt]
            ]

        reduceA =
            [ ((i, t), Reduce lhs alpha)
            | item  <- Set.toList state
            , null (itemAfter item)
            , let lhs   = itemLHS item
            , let alpha = itemBefore item
            , lhs /= "S'"
            , t <- fromMaybe [] (Map.lookup lhs followSets)
            ]

        acceptA =
            [ ((i, "$"), Accept)
            | item <- Set.toList state
            , itemLHS item == "S'"
            , null (itemAfter item)
            ]

    buildGotos i state =
        [ ((i, nt), j)
        | NonTerminal nt <- nextSymbols state
        , let nextSt = goto g' state (NonTerminal nt)
        , Just j <- [findStateIndex sts nextSt]
        ]

constructSLRTable :: Grammar -> ParsingTable
constructSLRTable g =
    buildSLRParsingTable g followSets sts
  where
    sts        = buildLR0States g
    firstSets  = computeFirstSets g
    followSets = computeFollowSets g firstSets

-- Parse using an SLR table. The algorithm is identical to the generic LR parser.
parseSLR :: Grammar -> ParsingTable -> [String] -> ParseResult
parseSLR = parseLR


data Conflict
    = ShiftReduceConflict  Int String Action Action
    | ReduceReduceConflict Int String Action Action
    deriving (Eq, Show)

checkConflicts :: ParsingTable -> [Conflict]
checkConflicts table = Map.foldrWithKey checkEntry [] grouped
  where
    grouped = Map.fromListWith (++)
        [ (k, [a]) | (k, a) <- Map.toList (actionTable table) ]

    checkEntry (st, tok) acts acc
        | length acts > 1 = detectConflict st tok acts ++ acc
        | otherwise       = acc

    detectConflict st tok acts =
        case sort acts of
            [s@(Shift _),      r@(Reduce _ _)] -> [ShiftReduceConflict  st tok s r]
            [r1@(Reduce _ _), r2@(Reduce _ _)] -> [ReduceReduceConflict st tok r1 r2]
            _                                  -> []


printSLRTable :: Grammar -> IO ()
printSLRTable g = do
    let tbl = constructSLRTable g
    putStrLn "\n=== Action Table ==="
    mapM_ printAction (Map.toList (actionTable tbl))
    putStrLn "\n=== Goto Table ==="
    mapM_ printGoto (Map.toList (gotoTable tbl))
    putStrLn ""
    case checkConflicts tbl of
        [] -> putStrLn "No conflicts detected (grammar is SLR(1))."
        cs -> do
            putStrLn "=== Conflicts ==="
            mapM_ printConflict cs
  where
    printAction ((st, term), act) =
        putStrLn $ "  [" ++ show st ++ ", " ++ term ++ "] = " ++ show act
    printGoto ((st, nt), dest) =
        putStrLn $ "  [" ++ show st ++ ", " ++ nt ++ "] = " ++ show dest
    printConflict (ShiftReduceConflict  st tok a1 a2) =
        putStrLn $ "Shift-Reduce in state "  ++ show st
               ++ " on '" ++ tok ++ "': " ++ show a1 ++ " vs " ++ show a2
    printConflict (ReduceReduceConflict st tok a1 a2) =
        putStrLn $ "Reduce-Reduce in state " ++ show st
               ++ " on '" ++ tok ++ "': " ++ show a1 ++ " vs " ++ show a2
