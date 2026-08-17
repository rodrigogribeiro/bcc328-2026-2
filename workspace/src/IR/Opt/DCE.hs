module IR.Opt.DCE
  ( dceProgram
  , dceFuncDef
  ) where

import Data.List            (foldl')
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import Data.Map.Strict (Map)
import Data.Set        (Set)

import IR.Frontend.Syntax.IRSyntax

-- Entry points

dceProgram :: Program -> Program
dceProgram = map dceFuncDef

dceFuncDef :: FuncDef -> FuncDef
dceFuncDef fd = fd { funcBody = process (funcBody fd) }
  where
    process = rebuildSeq . deadAssignElim . removeUnreachable . linearize

-- Phase 1: Unreachable code elimination
--
-- Statements after an unconditional JUMP or RETURN can never be executed.
-- They are dropped until the next LABEL (which may be reachable via another
-- jump and must be preserved).

removeUnreachable :: [Stmt] -> [Stmt]
removeUnreachable [] = []
removeUnreachable (s:ss)
  | isHardJump s = s : skipUntilLabel ss
  | otherwise = s : removeUnreachable ss

isHardJump :: Stmt -> Bool
isHardJump (JUMP _) = True
isHardJump (RETURN _) = True
isHardJump _ = False

skipUntilLabel :: [Stmt] -> [Stmt]
skipUntilLabel []                 = []
skipUntilLabel (s@(LABEL _) : ss) = s : removeUnreachable ss
skipUntilLabel (_ : ss)           = skipUntilLabel ss

-- Phase 2: Dead assignment elimination (forward analysis)
--
-- A pure assignment MOVE(TEMP t, e) is dead when t is overwritten before
-- being read, or the function returns without reading t.
--
-- The pass maintains a table of "pending" assignments: the most recent
-- MOVE(TEMP t, e) for each t that has not yet been read.  When t is read,
-- its entry is cleared (the assignment is live).  When t is overwritten and
-- its pending entry held a pure expression, that earlier statement is marked
-- dead.
--
-- At control-flow boundaries (LABEL, JUMP, CJUMP) the table is flushed
-- conservatively: we cannot tell which temporaries are live at jump targets,
-- so we keep all pending entries at those points.
--
-- At RETURN the flush is precise: any pending pure assignment not consumed
-- by the return values is truly dead.

type Idx = Int

data Pending = Pending
  { pendingIdx  :: Idx
  , pendingExpr :: Expr
  }

data DAEState = DAEState
  { pending :: Map Temp Pending
  , dead    :: Set Idx
  }

initDAE :: DAEState
initDAE = DAEState Map.empty Set.empty

deadAssignElim :: [Stmt] -> [Stmt]
deadAssignElim stmts =
  let indexed = zip [0::Int ..] stmts
      finalState = foldl' step initDAE indexed
      extraDead = Set.fromList
                     [ pendingIdx p
                     | p <- Map.elems (pending finalState)
                     , isPure (pendingExpr p) ]
      allDead = dead finalState `Set.union` extraDead
  in [ s | (i, s) <- indexed, i `Set.notMember` allDead ]

step :: DAEState -> (Idx, Stmt) -> DAEState

-- Assignment to a temporary.
step st (idx, MOVE (TEMP t) e) =
  -- 1. Consume uses of e: those temps are now live, clear from pending.
  let st1 = clearUses (freeTempsExpr e) st
  -- 2. t is about to be overwritten. If the previous pending def of t was
  --    pure, it was never read → mark it dead.
      st2 = case Map.lookup t (pending st1) of
              Just p | isPure (pendingExpr p) ->
                st1 { dead = Set.insert (pendingIdx p) (dead st1) }
              _ -> st1
  -- 3. Register the new (possibly impure) pending def for t.
  in st2 { pending = Map.insert t (Pending idx e) (pending st2) }

-- Write through memory: addr and val are uses; no temp is defined.
step st (_, MOVE (MEM addr) val) =
  clearUses (freeTempsExpr addr `Set.union` freeTempsExpr val) st

-- Expression as statement: all temps in e are used.
step st (_, EXP e) =
  clearUses (freeTempsExpr e) st

-- Return: consume uses, then mark all remaining pending pure defs as dead.
step st (_, RETURN es) =
  let st1     = clearUses (Set.unions (map freeTempsExpr es)) st
      deadNow = Set.fromList
                  [ pendingIdx p
                  | p <- Map.elems (pending st1)
                  , isPure (pendingExpr p) ]
  in st1 { dead = dead st1 `Set.union` deadNow, pending = Map.empty }

-- Unconditional jump: consume uses in the target expression, then flush
-- pending conservatively (we don't know what's live at the target).
step st (_, JUMP e) =
  (clearUses (freeTempsExpr e) st) { pending = Map.empty }

-- Conditional jump: consume uses in the condition, flush conservatively.
step st (_, CJUMP e _ _) =
  (clearUses (freeTempsExpr e) st) { pending = Map.empty }

-- Label: flush conservatively (unknown jump sources may use any temp).
step st (_, LABEL _) =
  st { pending = Map.empty }

step st _ = st  -- SEQ: should not appear after linearization

-- Remove pending entries for all temps in the given set (they are now live).
clearUses :: Set Temp -> DAEState -> DAEState
clearUses uses st = st { pending = foldl' (flip Map.delete) (pending st) (Set.toList uses) }

-- Expression/statement utilities

freeTempsExpr :: Expr -> Set Temp
freeTempsExpr (TEMP t) = Set.singleton t
freeTempsExpr (BINOP _ e1 e2) = freeTempsExpr e1 `Set.union` freeTempsExpr e2
freeTempsExpr (MEM e) = freeTempsExpr e
freeTempsExpr (CALL ef args) = Set.unions (map freeTempsExpr (ef : args))
freeTempsExpr (ESEQ s e) = stmtFreeTemps s `Set.union` freeTempsExpr e
freeTempsExpr _ = Set.empty

stmtFreeTemps :: Stmt -> Set Temp
stmtFreeTemps (MOVE dst src) = freeTempsExpr dst `Set.union` freeTempsExpr src
stmtFreeTemps (EXP e) = freeTempsExpr e
stmtFreeTemps (SEQ s1 s2) = stmtFreeTemps s1 `Set.union` stmtFreeTemps s2
stmtFreeTemps (JUMP e) = freeTempsExpr e
stmtFreeTemps (CJUMP e _ _) = freeTempsExpr e
stmtFreeTemps (RETURN es) = Set.unions (map freeTempsExpr es)
stmtFreeTemps (LABEL _) = Set.empty

isPure :: Expr -> Bool
isPure (CONST _) = True
isPure (TEMP _) = True
isPure (NAME _) = True
isPure (BINOP _ e1 e2) = isPure e1 && isPure e2
isPure _ = False

-- SEQ utilities (shared with CSE; local copies to keep modules independent)

linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s = [s]

rebuildSeq :: [Stmt] -> Stmt
rebuildSeq [] = EXP (CONST 0)
rebuildSeq [s] = s
rebuildSeq (s:ss) = SEQ s (rebuildSeq ss)
