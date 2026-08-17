module IR.Opt.Loop.Unroll
  ( UnrollConfig (..)
  , defaultUnrollConfig
  , unrollProgram
  , unrollFuncDef
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import Data.Set (Set)

import IR.Frontend.Syntax.IRSyntax
import IR.Opt.Loop.Loop

-- Configuration

newtype UnrollConfig = UnrollConfig { unrollFactor :: Int }

defaultUnrollConfig :: UnrollConfig
defaultUnrollConfig = UnrollConfig 2

-- Entry points

unrollProgram :: UnrollConfig -> Program -> Program
unrollProgram cfg = map (unrollFuncDef cfg)

unrollFuncDef :: UnrollConfig -> FuncDef -> FuncDef
unrollFuncDef cfg fd =
  fd { funcBody = let bs = linearize (funcBody fd) 
                  in rebuildSeq (applyUnroll cfg Set.empty bs) }

-- Core algorithm

applyUnroll :: UnrollConfig -> Set Label -> [Stmt] -> [Stmt]
applyUnroll cfg done stmts =
  case filter (\l -> loopHeadLabel l `Set.notMember` done) (findLoops stmts) of
    []       -> stmts
    (loop:_) ->
      let stmts' = unrollOneLoop cfg stmts loop
          done' = Set.insert (loopHeadLabel loop) done
      in applyUnroll cfg done' stmts'

unrollOneLoop :: UnrollConfig -> [Stmt] -> Loop -> [Stmt]
unrollOneLoop cfg stmts loop
  | k <= 1 = stmts
  | otherwise = before ++ newLoopSlice ++ after
  where
    k = unrollFactor cfg
    lh = loopHeadLabel loop
    lb = loopBodyLabel loop
    lf = loopExitLabel loop
    cond = loopCond loop
    body = loopBodyStmts loop
    intLabels = Set.toList (loopLabelSet loop)

    hi = loopHeadIdx loop
    origSize = loopSliceSize loop
    before = take hi stmts
    after = drop (hi + origSize) stmts

    -- Extra copies: copies 1 .. k-1 (copy 0 is the original body).
    -- Each extra copy gets a fresh entry label and renamed internal labels.
    makeCopy copyIdx =
      let suffix = "_u" ++ show copyIdx
          renameMap = Map.fromList [ (l, l ++ suffix) | l <- intLabels ]
          entryLb = lh ++ "_unroll_" ++ show copyIdx
          renamedBody = map (renameLabels renameMap) body
      in [CJUMP cond entryLb lf, LABEL entryLb] ++ renamedBody

    extraCopies = concatMap makeCopy [1 .. k - 1]

    -- New loop: original body + (k-1) extra copies, all under one header.
    newLoopSlice =
      [ LABEL lh, CJUMP cond lb lf, LABEL lb ]
      ++ body
      ++ extraCopies
      ++ [ JUMP (NAME lh), LABEL lf ]
