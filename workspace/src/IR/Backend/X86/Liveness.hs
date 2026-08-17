module IR.Backend.X86.Liveness
  ( -- * Use / def helpers
    freeTempsExpr
  , useTemp
  , defTemp
    -- * Liveness maps
  , LiveMap
  , liveness
  , liveOut
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

import IR.Frontend.Syntax.IRSyntax
import IR.Backend.X86.CFG

-- ── Use / def helpers ────────────────────────────────────────────────────────

-- | All temporaries mentioned in an expression (all are reads).
--   For ESEQ(s, e) the temps mentioned in s are conservatively included:
--   the statement s executes as part of this expression, so any temp it reads
--   or writes must be live here.
freeTempsExpr :: Expr -> Set Temp
freeTempsExpr (TEMP t)        = Set.singleton t
freeTempsExpr (BINOP _ e1 e2) = freeTempsExpr e1 `Set.union` freeTempsExpr e2
freeTempsExpr (MEM e)         = freeTempsExpr e
freeTempsExpr (CALL ef args)  = Set.unions (map freeTempsExpr (ef : args))
freeTempsExpr (ESEQ s e)      = useTemp s `Set.union` freeTempsExpr e
freeTempsExpr _               = Set.empty  -- CONST, NAME

-- | Temporaries READ by a statement (the USE set).
--
--   For MOVE(TEMP t, e): only the RHS e provides reads; t is the def.
--   For MOVE(MEM addr, val): both addr and val are reads (addr is used to
--   compute the write address; the destination is not a temporary).
--   ESEQ contents are included conservatively via 'freeTempsExpr'.
useTemp :: Stmt -> Set Temp
useTemp (MOVE (TEMP _)   e)   = freeTempsExpr e
useTemp (MOVE dst        src) = freeTempsExpr dst `Set.union` freeTempsExpr src
useTemp (EXP e)               = freeTempsExpr e
useTemp (RETURN es)           = Set.unions (map freeTempsExpr es)
useTemp (JUMP e)              = freeTempsExpr e
useTemp (CJUMP e _ _)         = freeTempsExpr e
useTemp (LABEL _)             = Set.empty
useTemp (SEQ _ _)             = Set.empty  -- absent after linearisation

-- | Temporaries WRITTEN by a statement (the DEF set).
--   Only a top-level MOVE(TEMP t, _) constitutes a definition; assignments
--   inside ESEQ sub-expressions are not tracked here (conservative).
defTemp :: Stmt -> Set Temp
defTemp (MOVE (TEMP t) _) = Set.singleton t
defTemp _                 = Set.empty

-- ── Liveness analysis ────────────────────────────────────────────────────────

-- | live_in[i] = set of temporaries live just BEFORE statement i.
type LiveMap = Map Int (Set Temp)

-- | Compute live_in for every statement index in @cfg@ by iterating the
--   standard backward dataflow equations to a fixed point:
--
-- @
--   live_out[i]  =  ∪ { live_in[j] | j ∈ succs(i) }
--   live_in[i]   =  use[i]  ∪  (live_out[i] ∖ def[i])
-- @
--
--   Indices are processed in reverse order inside each pass, which matches
--   the direction of information flow in backward analyses and reduces the
--   number of full-pass iterations needed to reach the fixed point.
liveness :: FuncCFG -> LiveMap
liveness cfg = fixpoint initMap
  where
    idxs    = reverse (cfgIndices cfg)   -- backward order for faster convergence
    initMap = Map.fromList [ (i, Set.empty) | i <- cfgIndices cfg ]

    fixpoint m =
      let m' = foldl step m idxs
      in if m' == m then m else fixpoint m'

    -- One step: recompute live_in[i] using the current map for succs' live_in.
    -- Uses the accumulator (updated within this pass) for successors that have
    -- already been processed, matching Gauss-Seidel order.
    step acc i =
      let lo       = liveOutFrom acc i
          newIn    = useTemp (cfgStmtAt cfg i)
                     `Set.union`
                     (lo `Set.difference` defTemp (cfgStmtAt cfg i))
      in Map.insert i newIn acc

    liveOutFrom m i = Set.unions [ m Map.! j | j <- succs cfg i ]

-- | Compute live_out[i] from a completed 'LiveMap'.
--   live_out[i] = ∪ { live_in[j] | j ∈ succs(i) }
liveOut :: FuncCFG -> LiveMap -> Int -> Set Temp
liveOut cfg liveIn i =
  Set.unions [ liveIn Map.! j | j <- succs cfg i ]
