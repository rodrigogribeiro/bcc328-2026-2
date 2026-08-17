module Parsing.CYK.CYKParser
  ( CYKResult (..)
  , CYKTable
  , cykParse
  , buildTable
  , isCNF
  , isCNFProduction
  , toCNF
  ) where

import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.List (nub, foldl')
import Data.Maybe (fromMaybe)

import Parsing.Grammar

data CYKResult = CYKAccept | CYKReject
  deriving (Show, Eq)

type CYKTable = Map (Int, Int) (Set String)

isCNFProduction :: Production -> Bool
isCNFProduction [Terminal _]                   = True
isCNFProduction [NonTerminal _, NonTerminal _] = True
isCNFProduction _                              = False

isCNF :: Grammar -> Bool
isCNF g = all (all isCNFProduction) (Map.elems g)

buildTable :: Grammar -> [String] -> CYKTable
buildTable g tokens = foldl' fillSpan base spans
  where
    n       = length tokens
    indexed = zip [1..] tokens
    base    = Map.fromList
        [ ((i, i), Set.fromList
              [ lhs
              | (lhs, prods) <- Map.toList g
              , [Terminal tok] `elem` prods
              ])
        | (i, tok) <- indexed
        ]
    spans = [ (i, i + l - 1)
            | l <- [2..n]
            , i <- [1..n - l + 1]
            ]
    look k m = fromMaybe Set.empty (Map.lookup k m)
    binaryProds = [ (lhs, b, c)
                  | (lhs, prods) <- Map.toList g
                  , [NonTerminal b, NonTerminal c] <- prods
                  ]
    fillSpan tbl (i, j) =
        let new = Set.fromList
                    [ lhs
                    | k <- [i..j-1]
                    , let bs = look (i, k) tbl
                    , let cs = look (k+1, j) tbl
                    , not (Set.null bs || Set.null cs)
                    , (lhs, b, c) <- binaryProds
                    , Set.member b bs
                    , Set.member c cs
                    ]
        in if Set.null new
           then tbl
           else Map.insertWith Set.union (i, j) new tbl

cykParse :: Grammar -> String -> [String] -> CYKResult
cykParse g start tokens
    | null tokens              = if acceptsEmpty then CYKAccept else CYKReject
    | Set.member start topCell = CYKAccept
    | otherwise                = CYKReject
  where
    n            = length tokens
    tbl          = buildTable g tokens
    topCell      = fromMaybe Set.empty (Map.lookup (1, n) tbl)
    startProds   = fromMaybe [] (Map.lookup start g)
    acceptsEmpty = any isEpsilon startProds
    isEpsilon p  = null p || p == [Terminal "\955"] || p == [Terminal "lambda"]

fixedPoint :: Eq a => (a -> a) -> a -> a
fixedPoint f x = let x' = f x in if x' == x then x else fixedPoint f x'

toCNF :: String -> Grammar -> (String, Grammar)
toCNF start g = (start', g4)
  where
    start' = start ++ "0"
    g0     = Map.insert start' [[NonTerminal start]] g
    g1     = eliminateEpsilon start' g0
    g2     = eliminateUnits g1
    g3     = terminalify g2
    g4     = binarize g3

nullables :: Grammar -> Set String
nullables g = fixedPoint expand direct
  where
    direct = Set.fromList
        [ lhs
        | (lhs, prods) <- Map.toList g
        , any isEps prods
        ]
    isEps p = null p || p == [Terminal "\955"] || p == [Terminal "lambda"]
    expand ns = Set.union ns $ Set.fromList
        [ lhs
        | (lhs, prods) <- Map.toList g
        , any (all (isNullableSym ns)) prods
        ]
    isNullableSym ns (NonTerminal x) = Set.member x ns
    isNullableSym _  _               = False

eliminateEpsilon :: String -> Grammar -> Grammar
eliminateEpsilon start g =
    Map.mapWithKey (\k prods -> nub (concatMap (variants k) prods)) g
  where
    ns = nullables g
    isNullableSym (NonTerminal x) = Set.member x ns
    isNullableSym _               = False
    variants lhs prod =
        let choices = sequence [ if isNullableSym s then [True, False] else [True]
                                 | s <- prod ]
            keep mask = [s | (s, b) <- zip prod mask, b]
        in  [ kept
            | mask <- choices
            , let kept = keep mask
            , not (null kept) || lhs == start
            ]

eliminateUnits :: Grammar -> Grammar
eliminateUnits g = fixedPoint step g
  where
    step g' = Map.mapWithKey expand g'
    expand lhs prods =
        nub $ concatMap (resolveUnit lhs) prods ++ prods
    resolveUnit lhs [NonTerminal b]
        | b /= lhs  = fromMaybe [] (Map.lookup b g)
    resolveUnit _   _ = []

terminalify :: Grammar -> Grammar
terminalify g = foldl' addTermProd gExtended allTerms
  where
    allTerms = nub
        [ t
        | (_lhs, prods) <- Map.toList g
        , prod          <- prods
        , length prod   > 1
        , Terminal t    <- prod
        ]
    termNT t = "N_" ++ t
    replaceTerms prod
        | length prod > 1 = map (\s -> case s of
                                    Terminal t -> NonTerminal (termNT t)
                                    _          -> s) prod
        | otherwise       = prod
    gExtended = Map.map (map replaceTerms) g
    addTermProd acc t =
        Map.insertWith (++) (termNT t) [[Terminal t]] acc

binarize :: Grammar -> Grammar
binarize g = Map.foldlWithKey' expandNT Map.empty g
  where
    expandNT acc lhs prods =
        let (newProds, aux) = unzip (map (binarizeProd lhs) (zip [(0::Int)..] prods))
        in Map.unionsWith (++) (Map.singleton lhs newProds : acc : aux)
    binarizeProd _   (_idx, prod)
        | length prod <= 2 = (prod, Map.empty)
    binarizeProd lhs (idx, s1:rest) =
        let auxNT    = lhs ++ "_" ++ show idx
            (auxProd, nested) = binarizeProd auxNT (0, rest)
        in ([s1, NonTerminal auxNT], Map.insertWith (++) auxNT [auxProd] nested)
    binarizeProd _   (_idx, prod) = (prod, Map.empty)
