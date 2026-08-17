module IR.Backend.X86.GraphColor
  ( TempLoc (..)
  , Coloring
  , colorFunc
  , calleeSavedInCol
  , frameAdj
  ) where

import Data.List       (foldl', maximumBy, nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe      (listToMaybe)
import Data.Ord        (comparing)
import Data.Set        (Set)
import qualified Data.Set        as Set

import IR.Frontend.Syntax.IRSyntax
import IR.Backend.X86.X86Syntax
import IR.Backend.X86.CFG
import IR.Backend.X86.Liveness
import IR.Backend.X86.Intervals
import IR.Backend.X86.IGraph

-- ── Result type ──────────────────────────────────────────────────────────────

-- | Allocation result for a temporary.
data TempLoc
  = InReg Reg   -- lives in a physical register
  | InMem Int   -- spilled; offset from %rbp (negative multiple of 8)
  deriving (Eq, Show)

type Coloring = Map Temp TempLoc

-- ── Register preference ──────────────────────────────────────────────────────

-- | Number of registers in the allocation pool.
k :: Int
k = length allocPool

-- | Preferred colour order: callee-saved first (fewer saves/restores at
--   CALLs), then the caller-saved pool registers.
preferOrder :: [Reg]
preferOrder =
  Set.toList calleeSaved ++
  filter (`Set.notMember` calleeSaved) allocPool

-- ── Public entry point ───────────────────────────────────────────────────────

-- | Colour all temporaries in a function body using graph colouring.
--
--   'params' are the function's formal parameters.  All pairs of parameters
--   get interference edges added before colouring because they are all
--   simultaneously live on function entry (each in a distinct ABI register).
--
--   Returns (coloring, spillBytes) where spillBytes is the number of bytes
--   that must be subtracted from %rsp (beyond the callee-saved pushes) to
--   accommodate spilled temporaries.  Use 'frameAdj' to compute the actual
--   subq amount that maintains 16-byte alignment.
colorFunc :: [Temp] -> Stmt -> (Coloring, Int)
colorFunc params body =
  let cfg  = buildCFG body
      livm = liveness cfg
      ivm  = buildIntervalMap cfg livm
      ig0  = buildIGraph cfg livm
      ig   = addParamEdges params ig0
      (stack, potSpills) = simplify ig ivm
      (col,   nextSlot)  = selectColors stack potSpills ig (-8)
      spillBytes         = negate nextSlot - 8   -- 0 when no spills
  in (col, spillBytes)
  where
    addParamEdges ps g =
      foldr (\(p1, p2) acc -> addEdge p1 p2 acc) g
            [(p1, p2) | p1 <- ps, p2 <- ps, p1 /= p2]

-- | Callee-saved registers actually used in the coloring (need push/pop).
calleeSavedInCol :: Coloring -> [Reg]
calleeSavedInCol col =
  nub [ r | InReg r <- Map.elems col, r `Set.member` calleeSaved ]

-- | Compute the frame adjustment (the 'subq $F, %rsp' amount) such that
--   RSP remains 16-byte aligned inside the function body.
--
--   After pushq %rbp the stack is 16-aligned; each of the N callee-saved
--   pushes shifts it by 8.  We need:
--
--   @  8 * N + F  ≡  0  (mod 16)  @
--
--   subject to F ≥ spillBytes.  If F = 0 the 'subq' is omitted.
frameAdj :: Int   -- N = number of callee-saved registers pushed
         -> Int   -- spillBytes from 'colorFunc'
         -> Int
frameAdj nCallee spillBytes =
  let base     = align16 spillBytes
      total    = 8 * nCallee + base
      misalign = total `mod` 16
  in if misalign == 0 then base else base + (16 - misalign)

align16 :: Int -> Int
align16 n = ((n + 15) `div` 16) * 16

-- ── Simplification (Kempe) ───────────────────────────────────────────────────

simplify :: IGraph -> IntervalMap -> ([Temp], Set Temp)
simplify ig0 ivm = go ig0 [] Set.empty (Set.toList (nodes ig0))
  where
    go _  stk spills []  = (stk, spills)
    go ig stk spills wl  =
      case findLow ig wl of
        Just t ->
          go (removeNode t ig) (t : stk) spills (filter (/= t) wl)
        Nothing ->
          let t = selectSpill ivm wl
          in  go (removeNode t ig) (t : stk) (Set.insert t spills) (filter (/= t) wl)

findLow :: IGraph -> [Temp] -> Maybe Temp
findLow ig = listToMaybe . filter (\t -> degree t ig < k)

-- | Spill the temporary with the longest live interval (maximum register
--   pressure over the widest region of the function).
selectSpill :: IntervalMap -> [Temp] -> Temp
selectSpill ivm = maximumBy (comparing (\t -> maybe 0 ivLen (Map.lookup t ivm)))

-- ── Select (colouring) ───────────────────────────────────────────────────────

-- | Assign colours by popping from the simplification stack.
--   Returns (coloring, nextSlot) where nextSlot is the next available stack
--   offset (starts at -8; decrements by 8 for each spill).
selectColors :: [Temp] -> Set Temp -> IGraph -> Int -> (Coloring, Int)
selectColors stack _potSpills origGraph startSlot =
  foldl' step (Map.empty, startSlot) stack
  where
    step (col, nextSlot) t =
      let used  = Set.fromList
                    [ r | u <- Set.toList (neighbors t origGraph)
                        , Just (InReg r) <- [Map.lookup u col] ]
          avail = filter (`Set.notMember` used) preferOrder
      in case avail of
           (r : _) -> (Map.insert t (InReg r)       col, nextSlot)
           []      -> (Map.insert t (InMem nextSlot) col, nextSlot - 8)
