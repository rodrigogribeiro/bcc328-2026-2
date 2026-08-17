module IR.Opt.Loop.Fusion
  ( fuseProgram
  , fuseFuncDef
  ) where

import qualified Data.Set as Set

import IR.Frontend.Syntax.IRSyntax
import IR.Opt.Loop.Loop

-- Entry points

fuseProgram :: Program -> Program
fuseProgram = map fuseFuncDef

fuseFuncDef :: FuncDef -> FuncDef
fuseFuncDef fd = fd { funcBody = rebuildSeq (applyFusion (linearize (funcBody fd))) }

-- Core algorithm

-- Repeatedly fuse adjacent fusible loop pairs until none remain.
applyFusion :: [Stmt] -> [Stmt]
applyFusion stmts =
  case findFusiblePair stmts of
    Nothing       -> stmts
    Just (l1, l2) -> applyFusion (fuseTwo stmts l1 l2)

-- Find the first pair of adjacent fusible loops (left to right).
findFusiblePair :: [Stmt] -> Maybe (Loop, Loop)
findFusiblePair stmts =
  let loops = findLoops stmts
      pairs = zip loops (tail loops)
  in case filter (\(a,b) -> adjacent a b && areFusible a b) pairs of
       []        -> Nothing
       ((a,b):_) -> Just (a, b)

-- Two loops are adjacent when L2 starts immediately after L1's exit label.
adjacent :: Loop -> Loop -> Bool
adjacent l1 l2 = loopExitIdx l1 + 1 == loopHeadIdx l2

-- Fusibility check

-- Two loops are fusible when:
--   1. They have the same condition expression (structural equality).
--   2. The trailing update statement is identical in both bodies
--      (ensures the same induction-variable step).
--   3. No temp written in L1 (other than the induction variable) is
--      read before being written in L2.
areFusible :: Loop -> Loop -> Bool
areFusible l1 l2 =
  loopCond l1 == loopCond l2
  && not (null (loopBodyStmts l1))
  && not (null (loopBodyStmts l2))
  && last (loopBodyStmts l1) == last (loopBodyStmts l2)
  && noCrossDep l1 l2

-- True when no temp written in L1 (besides the induction-variable temps)
--   is read before being overwritten in L2.
noCrossDep :: Loop -> Loop -> Bool
noCrossDep l1 l2 =
  Set.null (defs1NoIndVar `Set.intersection` firstUses (loopBodyStmts l2))
  where
    indVars      = freeTempsExpr (loopCond l1)
    defs1NoIndVar = loopDefSet l1 `Set.difference` indVars

-- Fusion

-- Fuse two adjacent loops into one, replacing both in the flat list.
fuseTwo :: [Stmt] -> Loop -> Loop -> [Stmt]
fuseTwo stmts l1 l2 = before ++ fusedSlice ++ after
  where
    body1NoUpdate = init (loopBodyStmts l1)
    body2          = loopBodyStmts l2
    fusedBody      = body1NoUpdate ++ body2

    lh    = loopHeadLabel l1
    lb    = loopBodyLabel l1
    lf    = loopExitLabel l1
    cond  = loopCond l1

    hi1   = loopHeadIdx  l1
    ei2   = loopExitIdx  l2
    before = take hi1 stmts
    after  = drop (ei2 + 1) stmts

    fusedSlice =
      [ LABEL lh, CJUMP cond lb lf, LABEL lb ]
      ++ fusedBody
      ++ [ JUMP (NAME lh), LABEL lf ]
