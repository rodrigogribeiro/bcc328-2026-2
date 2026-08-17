module IR.Opt.Pipeline
  ( optFold
  , optProp
  , optFoldProp
  , optCSE
  , optDCE
  , optLICM
  , optUnroll
  , optUnrollN
  , optFusion
  , optTCO
  , optInline
  , optAll
  ) where

import IR.Frontend.Syntax.IRSyntax     (Program)
import IR.Opt.ConstFold                (foldProgram)
import IR.Opt.ConstFoldProp            (foldPropProgram)
import IR.Opt.CSE                      (cseProgram)
import IR.Opt.DCE                      (dceProgram)
import IR.Opt.Loop.LICM                (licmProgram)
import IR.Opt.Loop.Unroll              (UnrollConfig (..), defaultUnrollConfig, unrollProgram)
import IR.Opt.Loop.Fusion              (fuseProgram)
import IR.Opt.TCO                      (tcoProgram)
import IR.Opt.Inline                   (defaultInlineConfig, inlineProgram)
import Utils.Fixpoint                  (fixedPoint)

optFold     :: Program -> Program
optFold     = foldProgram

optProp     :: Program -> Program
optProp     = foldPropProgram

optFoldProp :: Program -> Program
optFoldProp = foldPropProgram

optCSE      :: Program -> Program
optCSE      = cseProgram

optDCE      :: Program -> Program
optDCE      = dceProgram

optLICM     :: Program -> Program
optLICM     = licmProgram

-- | Loop unrolling with the default factor (2).
optUnroll   :: Program -> Program
optUnroll   = unrollProgram defaultUnrollConfig

-- | Loop unrolling with an explicit factor.
optUnrollN  :: Int -> Program -> Program
optUnrollN k = unrollProgram (UnrollConfig k)

optFusion   :: Program -> Program
optFusion   = fuseProgram

-- | Tail-call elimination: self-tail-calls become loops.
optTCO      :: Program -> Program
optTCO      = tcoProgram

-- | Function inlining: replace calls to small non-recursive functions with
--   their bodies, then remove dead function definitions.
optInline   :: Program -> Program
optInline   = inlineProgram defaultInlineConfig

-- | Full optimisation pipeline:
--   1. TCO           (self-tail-calls → loops, enables further loop opts)
--   2. inline        (to fixpoint; may expose new tail calls or constants)
--   3. fold+prop     (to fixpoint; cleans up after inlining)
--   4. LICM          (loop-invariant code motion)
--   5. fold+prop     (second pass after hoisting)
--   6. CSE
--   7. loop fusion   (to fixpoint)
--   8. loop unrolling
--   9. CSE + DCE     (final cleanup)
optAll :: Program -> Program
optAll =
    dceProgram
  . cseProgram
  . unrollProgram defaultUnrollConfig
  . fixedPoint fuseProgram
  . cseProgram
  . fixedPoint foldPropProgram
  . licmProgram
  . fixedPoint foldPropProgram
  . fixedPoint (inlineProgram defaultInlineConfig)
  . tcoProgram
