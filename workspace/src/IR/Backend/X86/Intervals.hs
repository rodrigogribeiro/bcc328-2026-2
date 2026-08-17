module IR.Backend.X86.Intervals
  ( Interval (..)
  , IntervalMap
  , ivLen
  , buildIntervals
  , buildIntervalMap
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import IR.Frontend.Syntax.IRSyntax
import IR.Backend.X86.CFG
import IR.Backend.X86.Liveness

-- ── Interval type ────────────────────────────────────────────────────────────

-- | Closed live interval [ivStart, ivEnd] for a single temporary.
--
--   The interval is the smallest range of statement indices during which
--   the temporary must occupy a register or memory slot.  It is computed
--   as the span of all indices where the temporary appears in live_in,
--   live_out, or the def set of that instruction.
--
--   'ivLen' is the spilling heuristic used by the graph colourer:
--   the temporary with the longest interval exerts the most pressure on
--   the register pool and is the preferred candidate to spill.
data Interval = Interval
  { ivTemp  :: Temp  -- ^ the temporary this interval belongs to
  , ivStart :: Int   -- ^ first index where t is live or defined
  , ivEnd   :: Int   -- ^ last  index where t is live (in live_in or live_out)
  } deriving (Eq, Show)

-- | Length of an interval (ivEnd − ivStart).  Used as a spilling heuristic.
ivLen :: Interval -> Int
ivLen iv = ivEnd iv - ivStart iv

-- | Maps each temporary name to its live interval.
type IntervalMap = Map Temp Interval

-- ── Interval construction ────────────────────────────────────────────────────

-- | Build one interval per temporary from the liveness information.
--
--   A temporary's active points are all statement indices where it appears
--   in live_in, live_out, or the instruction's def set.  The interval spans
--   [minimum active point, maximum active point].
--
--   Temporaries that are defined but never live (dead assignments) receive a
--   zero-length interval [d, d] and will be assigned any colour without
--   creating interference.
buildIntervals :: FuncCFG -> LiveMap -> [Interval]
buildIntervals cfg liveIn =
  [ Interval { ivTemp = t, ivStart = minimum pts, ivEnd = maximum pts }
  | t   <- Set.toList allTemps
  , let pts = activePoints t
  , not (null pts)
  ]
  where
    idxs = cfgIndices cfg

    -- Active points for t: indices where t appears in live_in, live_out,
    -- or the def of the instruction at that index.
    activePoints t =
      [ i | i <- idxs, t `Set.member` pointSet i ]

    pointSet i =
      (liveIn Map.! i)
      `Set.union` liveOut cfg liveIn i
      `Set.union` defTemp (cfgStmtAt cfg i)

    -- Universe of temporaries: all that appear in any live set or as a def.
    allTemps =
      Set.unions (Map.elems liveIn)
      `Set.union`
      Set.unions [ defTemp (cfgStmtAt cfg i) | i <- idxs ]

-- | Index form of 'buildIntervals', keyed by temporary name.
buildIntervalMap :: FuncCFG -> LiveMap -> IntervalMap
buildIntervalMap cfg liveIn =
  Map.fromList [ (ivTemp iv, iv) | iv <- buildIntervals cfg liveIn ]
