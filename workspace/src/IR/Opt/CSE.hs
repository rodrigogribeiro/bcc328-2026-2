module IR.Opt.CSE
  ( cseProgram
  , cseFuncDef
  ) where

import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

import IR.Frontend.Syntax.IRSyntax

-- Map from a pure expression to the temp that holds its first computed value.
type CSETable = Map Expr Temp

data CSEState = CSEState
  { cseTable   :: CSETable
  , cseCounter :: Int
  }

initCSEState :: CSEState
initCSEState = CSEState Map.empty 0

-- Entry points

cseProgram :: Program -> Program
cseProgram = map cseFuncDef

cseFuncDef :: FuncDef -> FuncDef
cseFuncDef fd = fd { funcBody = rebuildSeq result }
  where
    stmts  = linearize (funcBody fd)
    result = cseStmts initCSEState stmts

-- Core algorithm

cseStmts :: CSEState -> [Stmt] -> [Stmt]
cseStmts _  []     = []
cseStmts st (s:ss) =
  let (emitted, st') = cseOneStmt st s
  in emitted ++ cseStmts st' ss

cseOneStmt :: CSEState -> Stmt -> ([Stmt], CSEState)

-- MOVE(TEMP t, e): the main CSE case.
cseOneStmt st (MOVE (TEMP t) e)
  | isPure e && not (isTrivial e) =
      case Map.lookup e (cseTable st) of
        Just cseT ->
          -- Expression already computed; reuse its temp.
          let st' = killTemp t st
          in ([MOVE (TEMP t) (TEMP cseT)], st')
        Nothing ->
          -- First occurrence: materialise into a fresh CSE temp.
          let k    = cseCounter st
              cseT = "_cse" ++ show k
              tbl1 = Map.insert e cseT (cseTable st)
              st1  = st { cseCounter = k + 1, cseTable = tbl1 }
              st2  = killTemp t st1
          in ( [ MOVE (TEMP cseT) e
               , MOVE (TEMP t)    (TEMP cseT) ]
             , st2 )

-- MOVE(TEMP t, e) where e is not CSE-eligible: kill t from the table.
cseOneStmt st (MOVE (TEMP t) e) =
  ([MOVE (TEMP t) e], killTemp t st)

-- Block boundaries: clear the CSE table.
cseOneStmt st s | isBlockBoundary s =
  ([s], st { cseTable = Map.empty })

-- Everything else (EXP, MOVE(MEM,...), LABEL): pass through unchanged.
cseOneStmt st s = ([s], st)

-- Helpers

-- An expression is pure if it has no side effects or memory dependencies.
isPure :: Expr -> Bool
isPure (CONST _)        = True
isPure (TEMP _)         = True
isPure (NAME _)         = True
isPure (BINOP _ e1 e2)  = isPure e1 && isPure e2
isPure (MEM _)          = False
isPure (CALL _ _)       = False
isPure (ESEQ _ _)       = False

-- Trivial expressions gain nothing from CSE.
isTrivial :: Expr -> Bool
isTrivial (CONST _) = True
isTrivial (TEMP _)  = True
isTrivial (NAME _)  = True
isTrivial _         = False

-- True at control-flow boundaries where the CSE table must be cleared.
isBlockBoundary :: Stmt -> Bool
isBlockBoundary (LABEL _)     = True
isBlockBoundary (JUMP _)      = True
isBlockBoundary (CJUMP _ _ _) = True
isBlockBoundary (RETURN _)    = True
isBlockBoundary _             = False

-- Evict all CSE table entries whose expression mentions the given temp.
killTemp :: Temp -> CSEState -> CSEState
killTemp t st = st { cseTable = Map.filterWithKey ok (cseTable st) }
  where ok e _ = not (exprMentions t e)

-- True if the expression contains a reference to the given temp.
exprMentions :: Temp -> Expr -> Bool
exprMentions t (TEMP s)        = s == t
exprMentions t (BINOP _ e1 e2) = exprMentions t e1 || exprMentions t e2
exprMentions _ _               = False

-- Flatten a SEQ tree into a left-to-right list.
linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s           = [s]

-- Rebuild a right-associative SEQ tree from a flat list.
rebuildSeq :: [Stmt] -> Stmt
rebuildSeq []     = EXP (CONST 0)
rebuildSeq [s]    = s
rebuildSeq (s:ss) = SEQ s (rebuildSeq ss)
