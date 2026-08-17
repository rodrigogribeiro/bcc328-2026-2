module Parsing.LR.LR1.BuildTable
  ( LR1Item (..)
  , LR1State
  , closure
  , goto
  , nextSymbols
  , findLR1StateIndex
  , buildLR1States
  , constructLR1Table
  , parseLR1
  , Conflict (..)
  , checkConflicts
  , printLR1Table
  ) where

import Data.List (nub, findIndex, sort)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Maybe (mapMaybe)

import Parsing.Grammar
import Parsing.First
import Parsing.LR.LRParser
import Utils.Fixpoint


-- LR(1) Items and States

-- LR(1) Item: [A -> alpha . beta, a]
data LR1Item = LR1Item
    { lr1LHS       :: String
    , lr1Before    :: [Symbol]
    , lr1After     :: [Symbol]
    , lr1Lookahead :: String 
    } deriving (Eq, Ord)

instance Show LR1Item where
    show (LR1Item lhs before after la) =
        lhs ++ " -> " ++ showSyms before ++ " . " ++ showSyms after
             ++ "  [" ++ la ++ "]"
      where
        showSyms [] = ""
        showSyms ss = unwords (map symbolString ss) ++ " "

-- LR(1) State: a set of LR(1) items
type LR1State = Set LR1Item


-- Closure and Goto

-- Lookaheads for a predicted item [B -> . gamma, ?] arising from
-- [A -> alpha . B beta, a]: new lookaheads are FIRST(beta a) \ {lambda}.
lookaheadsFor :: Grammar -> FirstSet -> [Symbol] -> String -> [String]
lookaheadsFor g fs beta a =
    filter (/= "λ") $ firstForSequence g fs (beta ++ [Terminal a])

-- Compute the LR(1) closure of a set of items.
-- For each item [A -> alpha . B beta, a] and each production B -> gamma,
-- add [B -> . gamma, b] for every b in FIRST(beta a).
closure :: Grammar -> FirstSet -> LR1State -> LR1State
closure g fs = fixedPoint step
  where
    step current = Set.union current newItems
      where
        newItems = Set.fromList $ concatMap expand (Set.toList current)

        expand item = case lr1After item of
            (NonTerminal b : beta) ->
                case Map.lookup b g of
                    Just prods ->
                        [ LR1Item b [] prod la
                        | prod <- prods
                        , la   <- lookaheadsFor g fs beta (lr1Lookahead item)
                        ]
                    Nothing -> []
            _ -> []

-- Compute goto(I, X): advance the dot past X and close the result.
-- The lookahead of each item is preserved unchanged.
goto :: Grammar -> FirstSet -> LR1State -> Symbol -> LR1State
goto g fs items sym = closure g fs $ Set.fromList shifted
  where
    shifted = mapMaybe shiftItem (Set.toList items)

    shiftItem item = case lr1After item of
        (s : rest) | s == sym ->
            Just $ LR1Item (lr1LHS item) (lr1Before item ++ [s]) rest (lr1Lookahead item)
        _ -> Nothing

-- Symbols immediately after the dot in some item of a state.
nextSymbols :: LR1State -> [Symbol]
nextSymbols state = nub $ mapMaybe getNext (Set.toList state)
  where
    getNext item = case lr1After item of
        (s : _) -> Just s
        []      -> Nothing


-- Canonical Collection of LR(1) States

-- Build all LR(1) states via BFS, starting from closure({[S' -> . S, $]}).
buildLR1States :: Grammar -> [LR1State]
buildLR1States g = buildFrom [initial] [initial]
  where
    startSym = head (nonTerminals g)
    g'       = Map.insert "S'" [[NonTerminal startSym]] g
    fs       = computeFirstSets g'
    seed     = LR1Item "S'" [] [NonTerminal startSym] "$"
    initial  = closure g' fs (Set.singleton seed)

    buildFrom seen [] = seen
    buildFrom seen (current : queue) =
        let syms      = nextSymbols current
            newStates = [goto g' fs current sym | sym <- syms]
            unseen    = filter (`notElem` seen) newStates
        in buildFrom (seen ++ unseen) (queue ++ unseen)

findLR1StateIndex :: [LR1State] -> LR1State -> Maybe Int
findLR1StateIndex sts st = findIndex (== st) sts


-- Building the LR(1) Parsing Table

buildLR1ParsingTable :: Grammar -> [LR1State] -> ParsingTable
buildLR1ParsingTable g sts = ParsingTable actions gotos
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
            , Just j <- [findLR1StateIndex sts nextSt]
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
        , Just j <- [findLR1StateIndex sts nextSt]
        ]

constructLR1Table :: Grammar -> ParsingTable
constructLR1Table g = buildLR1ParsingTable g (buildLR1States g)

parseLR1 :: Grammar -> ParsingTable -> [String] -> ParseResult
parseLR1 = parseLR


-- Conflict Detection

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


printLR1Table :: Grammar -> IO ()
printLR1Table g = do
    let sts = buildLR1States g
        tbl = buildLR1ParsingTable g sts
    putStrLn "\n=== LR(1) States ==="
    mapM_ printState (zip [0 :: Int ..] sts)
    putStrLn "\n=== Action Table ==="
    mapM_ printAction (Map.toList (actionTable tbl))
    putStrLn "\n=== Goto Table ==="
    mapM_ printGoto (Map.toList (gotoTable tbl))
    putStrLn ""
    case checkConflicts tbl of
        [] -> putStrLn "No conflicts detected (grammar is LR(1))."
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
