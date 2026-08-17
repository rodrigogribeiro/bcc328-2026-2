module Parsing.LR.LR0.BuildTable
  ( Item (..)
  , State
  , closure
  , goto
  , nextSymbols
  , findStateIndex
  , buildLR0States
  , constructLR0Table
  , printLR0Table
  ) where

import Data.List (nub, findIndex)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Maybe (mapMaybe)

import Parsing.Grammar
import Parsing.LR.LRParser
import Utils.Fixpoint


-- LR(0) Items and States

-- LR(0) Item: A -> alpha . beta
data Item = Item
    { itemLHS    :: String
    , itemBefore :: [Symbol]
    , itemAfter  :: [Symbol]
    } deriving (Eq, Ord)

instance Show Item where
    show (Item lhs before after) =
        lhs ++ " -> " ++ showSyms before ++ " . " ++ showSyms after
      where
        showSyms = unwords . map symbolString

-- LR(0) State: a set of items
type State = Set Item


-- Closure and Goto

-- Compute the closure of a set of LR(0) items.
closure :: Grammar -> State -> State
closure g = fixedPoint step
  where
    step current = Set.union current newItems
      where
        newItems = Set.fromList $ concatMap expand (Set.toList current)

        expand item = case itemAfter item of
            (NonTerminal b : _) ->
                case Map.lookup b g of
                    Just prods -> [Item b [] prod | prod <- prods]
                    Nothing    -> []
            _ -> []

-- Compute goto(I, X): advance the dot past X and close the result.
goto :: Grammar -> State -> Symbol -> State
goto g items sym = closure g $ Set.fromList shifted
  where
    shifted = mapMaybe shiftItem (Set.toList items)

    shiftItem item = case itemAfter item of
        (s : rest) | s == sym ->
            Just $ Item (itemLHS item) (itemBefore item ++ [s]) rest
        _ -> Nothing

-- Symbols immediately after the dot in some item of a state.
nextSymbols :: State -> [Symbol]
nextSymbols state = nub $ mapMaybe getNext (Set.toList state)
  where
    getNext item = case itemAfter item of
        (s : _) -> Just s
        []      -> Nothing


-- Build all LR(0) states via BFS from the closure of {S' -> . S}.
buildLR0States :: Grammar -> [State]
buildLR0States g = buildFrom [initial] [initial]
  where
    startSym = head (nonTerminals g)
    g'       = Map.insert "S'" [[NonTerminal startSym]] g
    initial  = closure g' (Set.singleton (Item "S'" [] [NonTerminal startSym]))

    buildFrom seen [] = seen
    buildFrom seen (current : queue) =
        let syms      = nextSymbols current
            newStates = [goto g' current sym | sym <- syms]
            unseen    = filter (`notElem` seen) newStates
        in buildFrom (seen ++ unseen) (queue ++ unseen)

findStateIndex :: [State] -> State -> Maybe Int
findStateIndex sts st = findIndex (== st) sts


-- Building the LR(0) Parsing Table

buildParsingTable :: Grammar -> [State] -> ParsingTable
buildParsingTable g sts = ParsingTable actions gotos
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

        -- LR(0): reduce on ALL terminals (no lookahead)
        reduceA =
            [ ((i, t), Reduce lhs alpha)
            | item  <- Set.toList state
            , null (itemAfter item)
            , let lhs   = itemLHS item
            , let alpha = itemBefore item
            , lhs /= "S'"
            , t <- terminals g ++ ["$"]
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

constructLR0Table :: Grammar -> ParsingTable
constructLR0Table g = buildParsingTable g (buildLR0States g)

printLR0Table :: Grammar -> IO ()
printLR0Table g = do
    let sts = buildLR0States g
        tbl = buildParsingTable g sts
    putStrLn "\n=== LR(0) States ==="
    mapM_ printState (zip [0 :: Int ..] sts)
    putStrLn "\n=== Action Table ==="
    mapM_ printAction (Map.toList (actionTable tbl))
    putStrLn "\n=== Goto Table ==="
    mapM_ printGoto (Map.toList (gotoTable tbl))
  where
    printState (i, state) = do
        putStrLn $ "State " ++ show i ++ ":"
        mapM_ (putStrLn . ("  " ++) . show) (Set.toList state)
    printAction ((st, term), act) =
        putStrLn $ "  [" ++ show st ++ ", " ++ term ++ "] = " ++ show act
    printGoto ((st, nt), dest) =
        putStrLn $ "  [" ++ show st ++ ", " ++ nt ++ "] = " ++ show dest
