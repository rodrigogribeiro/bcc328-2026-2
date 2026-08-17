module IR.Opt.Loop.LICM
  ( licmProgram
  , licmFuncDef
  ) where

import qualified Data.Set as Set
import Data.Set (Set)

import IR.Frontend.Syntax.IRSyntax
import IR.Opt.Loop.Loop

-- Entry points

licmProgram :: Program -> Program
licmProgram = map licmFuncDef

licmFuncDef :: FuncDef -> FuncDef
licmFuncDef fd = fd { funcBody = rebuildSeq (applyLICM Set.empty (linearize (funcBody fd))) }

-- Core algorithm

-- Apply LICM to the flat statement list, skipping loops whose head label
--   is already in the 'done' set.  After processing each loop the list is
--   rebuilt and the algorithm restarts (to maintain valid indices).
applyLICM :: Set Label -> [Stmt] -> [Stmt]
applyLICM done stmts =
  case filter (\l -> loopHeadLabel l `Set.notMember` done) (findLoops stmts) of
    []       -> stmts
    (loop:_) ->
      let (hoisted, newBody) = hoistInvariants loop
          stmts'             = spliceLoop stmts loop hoisted newBody
          done'              = Set.insert (loopHeadLabel loop) done
      in applyLICM done' stmts'

-- Hoist loop-invariant pure assignments out of the loop body.
--   Returns (stmts to place before the loop, reduced body).
hoistInvariants :: Loop -> ([Stmt], [Stmt])
hoistInvariants loop = go [] [] [] (loopBodyStmts loop)
  where
    defs = loopDefSet loop

    go hoisted kept _ [] = (reverse hoisted, reverse kept)
    go hoisted kept seen (s@(MOVE (TEMP t) e) : rest)
      | canHoist t e seen =
          go (s : hoisted) kept (s : seen) rest
    go hoisted kept seen (s : rest) =
          go hoisted (s : kept) (s : seen) rest

    canHoist t e seen =
      isPure e
      && Set.null (freeTempsExpr e `Set.intersection` defs)
      && defCount t (loopBodyStmts loop) == 1
      && Set.notMember t (Set.unions (map stmtReadTemps seen))

defCount :: Temp -> [Stmt] -> Int
defCount t stmts = length [ () | MOVE (TEMP t') _ <- stmts, t' == t ]

-- Replace the original loop in the flat list with:
--   hoisted stmts (placed just before LABEL lh) + loop with reduced body.
spliceLoop :: [Stmt] -> Loop -> [Stmt] -> [Stmt] -> [Stmt]
spliceLoop stmts loop hoisted newBody =
  before ++ hoisted ++ newLoopSlice ++ after
  where
    hi       = loopHeadIdx loop
    origSize = loopSliceSize loop
    before   = take hi stmts
    slice    = take origSize (drop hi stmts)
    after    = drop (hi + origSize) stmts
    prefix        = take 3 slice
    suffix        = drop (3 + length (loopBodyStmts loop)) slice
    newLoopSlice  = prefix ++ newBody ++ suffix
