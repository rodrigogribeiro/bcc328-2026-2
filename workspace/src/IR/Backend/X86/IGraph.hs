module IR.Backend.X86.IGraph
  ( IGraph
  , emptyIGraph
  , nodes
  , neighbors
  , degree
  , addEdge
  , removeNode
  , buildIGraph
  ) where

import Data.List          (foldl')
import Data.Map.Strict    (Map)
import qualified Data.Map.Strict as Map
import Data.Set           (Set)
import qualified Data.Set        as Set

import IR.Frontend.Syntax.IRSyntax
import IR.Backend.X86.CFG
import IR.Backend.X86.Liveness

-- | Undirected interference graph over temporaries.
--   igAdj and igDeg are kept in sync at all times.
data IGraph = IGraph
  { igAdj :: Map Temp (Set Temp)  -- adjacency list (symmetric)
  , igDeg :: Map Temp Int          -- degree cache: |igAdj[t]|
  } deriving (Eq, Show)

emptyIGraph :: IGraph
emptyIGraph = IGraph Map.empty Map.empty

nodes :: IGraph -> Set Temp
nodes = Map.keysSet . igAdj

neighbors :: Temp -> IGraph -> Set Temp
neighbors t g = Map.findWithDefault Set.empty t (igAdj g)

degree :: Temp -> IGraph -> Int
degree t g = Map.findWithDefault 0 t (igDeg g)

-- | Ensure t appears as a node (degree 0 if previously absent).
addNode :: Temp -> IGraph -> IGraph
addNode t g = g
  { igAdj = Map.insertWith (\_ old -> old) t Set.empty (igAdj g)
  , igDeg = Map.insertWith (\_ old -> old) t 0         (igDeg g)
  }

-- | Add an undirected edge (t, u).  No-op if t == u or the edge exists.
addEdge :: Temp -> Temp -> IGraph -> IGraph
addEdge t u g
  | t == u    = addNode t g
  | u `Set.member` neighbors t g' = g'
  | otherwise = g'
      { igAdj = Map.adjust (Set.insert u) t
              $ Map.adjust (Set.insert t) u
              $ igAdj g'
      , igDeg = Map.adjust (+1) t
              $ Map.adjust (+1) u
              $ igDeg g'
      }
  where g' = addNode u (addNode t g)

-- | Remove t and all its incident edges from the graph.
removeNode :: Temp -> IGraph -> IGraph
removeNode t g =
  let nbrs = neighbors t g
      g'   = g { igAdj = Map.delete t (igAdj g)
               , igDeg = Map.delete t (igDeg g) }
  in Set.foldl' (\acc u ->
       acc { igAdj = Map.adjust (Set.delete t) u (igAdj acc)
           , igDeg = Map.adjust (subtract 1)   u (igDeg acc) })
     g' nbrs

-- | Build the interference graph from liveness information.
--
--   Edge rule: for each instruction i that defines temporary t,
--   add edge (t, u) for every u ∈ live_out(i), u ≠ t.
--   All temporaries are added as nodes, including those with no edges.
buildIGraph :: FuncCFG -> LiveMap -> IGraph
buildIGraph cfg liveIn =
  let allTemps =
        Set.unions (Map.elems liveIn)
        `Set.union`
        Set.unions [ defTemp (cfgStmtAt cfg i) | i <- cfgIndices cfg ]
      g0 = Set.foldl' (flip addNode) emptyIGraph allTemps
  in foldl' addInstr g0 (cfgIndices cfg)
  where
    addInstr g i =
      let tSet = defTemp (cfgStmtAt cfg i)
          out  = liveOut cfg liveIn i
      in if Set.null tSet
         then g
         else Set.foldl' (\g' u -> addEdge (Set.findMin tSet) u g') g out
