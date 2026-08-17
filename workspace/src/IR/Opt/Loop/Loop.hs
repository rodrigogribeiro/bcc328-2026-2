module IR.Opt.Loop.Loop
  ( Loop (..)
  , findLoops
  , loopDefSet
  , loopLabelSet
  , loopSliceSize
  , freeTempsExpr
  , stmtReadTemps
  , stmtDefs
  , firstUses
  , isPure
  , linearize
  , rebuildSeq
  , renameLabels
  , renameExpr
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import Data.Map.Strict (Map)
import Data.Set        (Set)

import IR.Frontend.Syntax.IRSyntax

-- Loop representation

data Loop = Loop
  { loopHeadLabel :: Label   -- lh: LABEL that starts the loop
  , loopBodyLabel :: Label   -- lb: LABEL that starts the body (true branch of CJUMP)
  , loopExitLabel :: Label   -- lf: LABEL after the loop
  , loopCond      :: Expr    -- condition expression in CJUMP
  , loopBodyStmts :: [Stmt]  -- body between LABEL(lb) and JUMP(NAME lh)
  , loopHeadIdx   :: Int     -- index of LABEL(lh) in the enclosing flat list
  , loopExitIdx   :: Int     -- index of LABEL(lf) in the enclosing flat list
  }

-- Loop detection

-- Find all top-level loops in a linearised statement list.
--
-- Recognised pattern:
--   LABEL(lh)
--   CJUMP(cond, l1, l2)
--   LABEL(lnext)          where lnext ∈ {l1, l2}  →  body label
--   … body …
--   JUMP(NAME(lh))        back edge
--   LABEL(lf)             the other CJUMP target
findLoops :: [Stmt] -> [Loop]
findLoops stmts = go 0 stmts
  where
    go _ [] = []
    go i (LABEL lh : CJUMP cond l1 l2 : LABEL lnext : rest)
      | lnext == l1 || lnext == l2 =
          let (lb, lf) = if lnext == l1 then (l1, l2) else (l2, l1)
          in case splitAtBackEdge lh rest of
               Just (body, LABEL lf' : remaining) | lf' == lf ->
                 let exitIdx = i + 3 + length body + 1
                     loop    = Loop lh lb lf cond body i exitIdx
                 in loop : go (exitIdx + 1) remaining
               _ -> go (i + 1) (CJUMP cond l1 l2 : LABEL lnext : rest)
    go i (_ : rest) = go (i + 1) rest

-- Split a list at the first JUMP(NAME lh), consuming that JUMP.
splitAtBackEdge :: Label -> [Stmt] -> Maybe ([Stmt], [Stmt])
splitAtBackEdge lh = go []
  where
    go _   []                             = Nothing
    go acc (JUMP (NAME l) : rest) | l == lh = Just (reverse acc, rest)
    go acc (s : rest)                     = go (s : acc) rest

-- Loop properties

loopDefSet :: Loop -> Set Temp
loopDefSet loop = Set.fromList
  [ t | MOVE (TEMP t) _ <- loopBodyStmts loop ]

loopLabelSet :: Loop -> Set Label
loopLabelSet loop = Set.fromList
  [ l | LABEL l <- loopBodyStmts loop ]

loopSliceSize :: Loop -> Int
loopSliceSize loop = 3 + length (loopBodyStmts loop) + 2

-- Expression / statement utilities

freeTempsExpr :: Expr -> Set Temp
freeTempsExpr (TEMP t) = Set.singleton t
freeTempsExpr (BINOP _ e1 e2) = freeTempsExpr e1 `Set.union` freeTempsExpr e2
freeTempsExpr (MEM e) = freeTempsExpr e
freeTempsExpr (CALL ef args) = Set.unions (map freeTempsExpr (ef : args))
freeTempsExpr (ESEQ s e) = stmtAllTemps s `Set.union` freeTempsExpr e
freeTempsExpr _ = Set.empty  -- CONST, NAME

-- Temps that are READ (not just written) in a statement.
stmtReadTemps :: Stmt -> Set Temp
stmtReadTemps (MOVE (TEMP _) e) = freeTempsExpr e
stmtReadTemps (MOVE (MEM a) e) = freeTempsExpr a `Set.union` freeTempsExpr e
stmtReadTemps (EXP e) = freeTempsExpr e
stmtReadTemps (JUMP e) = freeTempsExpr e
stmtReadTemps (CJUMP e _ _) = freeTempsExpr e
stmtReadTemps (RETURN es) = Set.unions (map freeTempsExpr es)
stmtReadTemps (LABEL _) = Set.empty
stmtReadTemps (SEQ s1 s2) = stmtReadTemps s1 `Set.union` stmtReadTemps s2
stmtReadTemps _ = Set.empty

-- Temps that are WRITTEN in a statement.
stmtDefs :: Stmt -> Set Temp
stmtDefs (MOVE (TEMP t) _) = Set.singleton t
stmtDefs (SEQ s1 s2) = stmtDefs s1 `Set.union` stmtDefs s2
stmtDefs _ = Set.empty

-- All temps appearing anywhere in a statement (reads and writes).
stmtAllTemps :: Stmt -> Set Temp
stmtAllTemps (MOVE dst src) = freeTempsExpr dst `Set.union` freeTempsExpr src
stmtAllTemps (EXP e) = freeTempsExpr e
stmtAllTemps (SEQ s1 s2) = stmtAllTemps s1 `Set.union` stmtAllTemps s2
stmtAllTemps (JUMP e) = freeTempsExpr e
stmtAllTemps (CJUMP e _ _) = freeTempsExpr e
stmtAllTemps (RETURN es) = Set.unions (map freeTempsExpr es)
stmtAllTemps (LABEL _) = Set.empty

-- Temps read before they are first written in a statement list.
--   Used for the cross-dependency check in loop fusion.
firstUses :: [Stmt] -> Set Temp
firstUses = go Set.empty Set.empty
  where
    go _ uses [] = uses
    go defs uses (s : rest) =
      let reads'  = stmtReadTemps s `Set.difference` defs
          writes = stmtDefs s
      in go (defs `Set.union` writes) (uses `Set.union` reads') rest

isPure :: Expr -> Bool
isPure (CONST _) = True
isPure (TEMP _) = True
isPure (NAME _) = True
isPure (BINOP _ e1 e2)  = isPure e1 && isPure e2
isPure _ = False

-- SEQ utilities

linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s = [s]

rebuildSeq :: [Stmt] -> Stmt
rebuildSeq [] = EXP (CONST 0)
rebuildSeq [s] = s
rebuildSeq (s:ss) = SEQ s (rebuildSeq ss)

-- Label renaming (for loop unrolling)

renameLabels :: Map Label Label -> Stmt -> Stmt
renameLabels m (LABEL l) = LABEL (rename m l)
renameLabels m (JUMP e) = JUMP (renameExpr m e)
renameLabels m (CJUMP e lt lf) 
   = CJUMP (renameExpr m e) (rename m lt) (rename m lf)
renameLabels m (MOVE d s) = MOVE (renameExpr m d) (renameExpr m s)
renameLabels m (EXP e) = EXP (renameExpr m e)
renameLabels m (SEQ s1 s2) = SEQ (renameLabels m s1) (renameLabels m s2)
renameLabels m (RETURN es) = RETURN (map (renameExpr m) es)

renameExpr :: Map Label Label -> Expr -> Expr
renameExpr m (NAME l) = NAME (rename m l)
renameExpr m (BINOP op e1 e2) = BINOP op (renameExpr m e1) (renameExpr m e2)
renameExpr m (MEM e) = MEM (renameExpr m e)
renameExpr m (CALL ef args) = CALL (renameExpr m ef) (map (renameExpr m) args)
renameExpr m (ESEQ s e) = ESEQ (renameLabels m s) (renameExpr m e)
renameExpr _ e = e  -- CONST, TEMP: unchanged

rename :: Map Label Label -> Label -> Label
rename m l = Map.findWithDefault l l m
