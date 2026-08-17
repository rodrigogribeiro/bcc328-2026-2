module Parsing.LR.LALR.BuildTable
  ( buildLALRStates
  , constructLALRTable
  , parseLALR
  , Conflict (..)
  , checkConflicts
  , printLALRTable
  ) where

import Data.List (nub, findIndex, sort)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set

import Parsing.Grammar
import Parsing.First
import Parsing.LR.LRParser
import Parsing.LR.LR1.BuildTable
    ( LR1Item (..), LR1State
    , goto, nextSymbols, buildLR1States
    )


-- Core of an LR(1) State

-- The core of an LR(1) item is its LR(0) part: everything except the lookahead.
type ItemCore = (String, [Symbol], [Symbol])

itemCore :: LR1Item -> ItemCore
itemCore item = (lr1LHS item, lr1Before item, lr1After item)

-- The core of a state is the set of item cores (lookaheads stripped).
stateCore :: LR1State -> Set ItemCore
stateCore = Set.map itemCore


-- Merging LR(1) States

-- Merge a group of LR(1) states that share the same core.
-- For each unique (LHS, before, after) triple, the resulting item carries
-- the union of all lookaheads found across the group.
mergeGroup :: [LR1State] -> LR1State
mergeGroup group =
    let allItems  = concatMap Set.toList group
        byCore    = Map.fromListWith Set.union
                      [ (itemCore i, Set.singleton (lr1Lookahead i))
                      | i <- allItems ]
    in Set.fromList
         [ LR1Item lhs before after la
         | ((lhs, before, after), las) <- Map.toList byCore
         , la <- Set.toList las
         ]

-- Build the canonical collection of LALR(1) states.
--
-- Strategy:
--   1. Build all LR(1) states (BFS order).
--   2. Group them by core, preserving the first-occurrence order of each core.
--   3. Merge each group into a single state by unioning lookaheads.
--
-- The resulting list has one state per distinct LR(0) core, in the same order
-- as LR(0)/SLR would produce, so state indices match those algorithms.
buildLALRStates :: Grammar -> [LR1State]
buildLALRStates g =
    let lr1States  = buildLR1States g
        coreOrder  = nub (map stateCore lr1States)
        grouped    = Map.fromListWith (++)
                       [ (stateCore s, [s]) | s <- lr1States ]
    in [ mergeGroup (grouped Map.! core) | core <- coreOrder ]

-- Find the index of the LALR state whose core matches the target's core.
-- We match by core rather than exact equality because goto of a merged state
-- may return an intermediate LR(1) state; the correct destination is the
-- merged state with the same core.
findLALRStateIndex :: [LR1State] -> LR1State -> Maybe Int
findLALRStateIndex sts target =
    findIndex (\s -> stateCore s == stateCore target) sts


buildLALRParsingTable :: Grammar -> [LR1State] -> ParsingTable
buildLALRParsingTable g sts = ParsingTable actions gotos
  where
    startSym = head (nonTerminals g)
    g'       = Map.insert "S'" [[NonTerminal startSym]] g
    fs       = computeFirstSets g'

    actions = Map.fromList $ concat
        [ buildActions i st | (i, st) <- zip [0..] sts ]

    gotos = Map.fromList $ concat
        [ buildGotos i st | (i, st) <- zip [0..] sts ]

    buildActions i st = shiftA ++ reduceA ++ acceptA
      where
        shiftA =
            [ ((i, t), Shift j)
            | Terminal t <- nextSymbols st
            , not (isLambda (Terminal t))
            , let nextSt = goto g' fs st (Terminal t)
            , Just j <- [findLALRStateIndex sts nextSt]
            ]

        reduceA =
            [ ((i, lr1Lookahead item), Reduce (lr1LHS item) (lr1Before item))
            | item <- Set.toList st
            , null (lr1After item)
            , lr1LHS item /= "S'"
            ]

        acceptA =
            [ ((i, "$"), Accept)
            | item <- Set.toList st
            , lr1LHS item == "S'"
            , null (lr1After item)
            ]

    buildGotos i st =
        [ ((i, nt), j)
        | NonTerminal nt <- nextSymbols st
        , let nextSt = goto g' fs st (NonTerminal nt)
        , Just j <- [findLALRStateIndex sts nextSt]
        ]

constructLALRTable :: Grammar -> ParsingTable
constructLALRTable g = buildLALRParsingTable g (buildLALRStates g)

parseLALR :: Grammar -> ParsingTable -> [String] -> ParseResult
parseLALR = parseLR


-- Conflict Detection

-- Merging states can introduce reduce-reduce conflicts: two complete items
-- that had disjoint lookaheads before merging may share a lookahead after.
-- Shift-reduce conflicts are never introduced by merging (a shift is
-- determined by the core, so it would have existed in the LR(1) table too).

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


printLALRTable :: Grammar -> IO ()
printLALRTable g = do
    let sts = buildLALRStates g
        tbl = buildLALRParsingTable g sts
    putStrLn "\n=== LALR(1) States ==="
    mapM_ printState (zip [0 :: Int ..] sts)
    putStrLn "\n=== Action Table ==="
    mapM_ printAction (Map.toList (actionTable tbl))
    putStrLn "\n=== Goto Table ==="
    mapM_ printGoto (Map.toList (gotoTable tbl))
    putStrLn ""
    case checkConflicts tbl of
        [] -> putStrLn "No conflicts detected (grammar is LALR(1))."
        cs -> do
            putStrLn "=== Conflicts ==="
            mapM_ printConflict cs
  where
    printState (i, st) = do
        putStrLn $ "State " ++ show i ++ ":"
        mapM_ (putStrLn . ("  " ++) . show) (Set.toList st)
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
