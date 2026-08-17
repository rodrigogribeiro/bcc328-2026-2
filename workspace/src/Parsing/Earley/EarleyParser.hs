module Parsing.Earley.EarleyParser
  ( EarleyItem (..)
  , EarleyResult (..)
  , Chart
  , EarleySet
  , earleyParse
  , buildChart
  , printChart
  , printAccepted
  ) where

import qualified Data.Map as Map
import Data.Maybe (fromMaybe)

import Parsing.Grammar

-- Types

-- An Earley chart item: a dotted production with an origin position.
data EarleyItem = EarleyItem
  { itemLhs    :: String 
  , itemBefore :: [Symbol]
  , itemAfter  :: [Symbol]
  , itemOrigin :: Int  
  } deriving (Eq, Ord)

instance Show EarleyItem where
  show (EarleyItem lhs before after origin) =
      lhs ++ " -> " ++ showBefore ++ "." ++ showAfter
          ++ "  [" ++ show origin ++ "]"
    where
      showBefore = if null before then "" else unwords (map symbolString before) ++ " "
      showAfter  = if null after  then "" else " " ++ unwords (map symbolString after)

data EarleyResult
  = EarleyAccept
  | EarleyReject
  deriving (Show, Eq)

type EarleySet = [EarleyItem]

type Chart = [EarleySet]


normProd :: Production -> [Symbol]
normProd [Terminal "\955"] = []   -- λ (U+03BB)
normProd [Terminal "lambda"] = []
normProd p = p

nextSymbol :: EarleyItem -> Maybe Symbol
nextSymbol item = case itemAfter item of
  []    -> Nothing
  (s:_) -> Just s

advanceDot :: Symbol -> EarleyItem -> EarleyItem
advanceDot sym item = item
  { itemBefore = itemBefore item ++ [sym]
  , itemAfter  = tail (itemAfter item)
  }


-- PREDICT
--   For an item (A → α • B β, j) in S(k), add (B → • γ, k) to S(k)
--   for every production B → γ in the grammar.
predictItems :: Grammar -> Int -> EarleyItem -> [EarleyItem]
predictItems grammar k item =
    case nextSymbol item of
      Just (NonTerminal b) ->
        [ EarleyItem b [] (normProd prod) k
        | prod <- fromMaybe [] (Map.lookup b grammar)
        ]
      _ -> []

-- COMPLETE
--   For a completed item (A → γ •, j) in S(k), advance every item
--   (B → α • A β, i) found in S(j).
--
--   When j == k the source set is 'currentSet' (S(k) as built so far);
--   when j < k  the source set is the already-closed prevSets !! j.
completeItems :: Chart -> EarleySet -> Int -> EarleyItem -> [EarleyItem]
completeItems prevSets currentSet k item =
    case nextSymbol item of
      Nothing ->
        let j       = itemOrigin item
            fromSet = if j < k then prevSets !! j else currentSet
        in [ advanceDot (NonTerminal (itemLhs item)) parent
           | parent  <- fromSet
           , nextSymbol parent == Just (NonTerminal (itemLhs item))
           ]
      _ -> []

--  SCAN
--   For every item (A → α • a β, j) in S(k), if the current input token
--   equals a, produce (A → α a • β, j) for S(k+1).
scanItems :: String -> EarleySet -> [EarleyItem]
scanItems token items =
  [ advanceDot (Terminal token) item
  | item <- items
  , nextSymbol item == Just (Terminal token)
  ]

-- Close S(k) under Predict and Complete using a worklist algorithm.
--
--   New items are appended to the worklist to preserve the Earley ordering
--   property (items are processed in insertion order).
closeSet :: Grammar -> Chart -> Int -> [EarleyItem] -> EarleySet
closeSet grammar prevSets k = go []
  where
    go current []           = current
    go current (item : rest)
      | item `elem` current = go current rest
      | otherwise =
          let current' = current ++ [item]
              new      = predictItems grammar k item
                      ++ completeItems prevSets current' k item
          in go current' (rest ++ new)

-- Build the full Earley chart for the given list of tokens.
--   Returns a list of (length tokens + 1) sets: S(0) through S(n).
buildChart :: Grammar -> [String] -> Chart
buildChart grammar tokens = go [s0] tokens
  where
    start  = head (nonTerminals grammar)
    s0Init = [ EarleyItem start [] (normProd prod) 0
             | prod <- fromMaybe [] (Map.lookup start grammar) ]
    s0     = closeSet grammar [] 0 s0Init

    go chart []           = chart
    go chart (tok : toks) =
        let sk      = last chart
            k1      = length chart
            scanned = scanItems tok sk
            sk1     = closeSet grammar chart k1 scanned
        in go (chart ++ [sk1]) toks

-- Acceptance check

isAccepted :: Grammar -> Chart -> Int -> Bool
isAccepted grammar chart n = any accept (chart !! n)
  where
    start  = head (nonTerminals grammar)
    accept item = itemLhs    item == start
               && itemOrigin item == 0
               && null (itemAfter item)

earleyParse :: Grammar -> [String] -> EarleyResult
earleyParse grammar tokens
    | isAccepted grammar chart n = EarleyAccept
    | otherwise                  = EarleyReject
  where
    n     = length tokens
    chart = buildChart grammar tokens

-- Pretty-printing

printChart :: Chart -> IO ()
printChart chart = mapM_ printSet (zip [0 :: Int ..] chart)
  where
    printSet (k, items) = do
        putStrLn $ "=== S(" ++ show k ++ ") ==="
        if null items
          then putStrLn "  (empty)"
          else mapM_ (putStrLn . ("  " ++) . show) items
        putStrLn ""

printAccepted :: Grammar -> Chart -> IO ()
printAccepted grammar chart = do
    let n      = length chart - 1
        start  = head (nonTerminals grammar)
        done   = filter (\i -> itemLhs i == start
                            && itemOrigin i == 0
                            && null (itemAfter i))
                        (chart !! n)
    putStrLn $ "=== Completed start items in S(" ++ show n ++ ") ==="
    if null done
      then putStrLn "  none (input rejected)"
      else mapM_ (putStrLn . ("  " ++) . show) done
