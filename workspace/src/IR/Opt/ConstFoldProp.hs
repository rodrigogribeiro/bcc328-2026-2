module IR.Opt.ConstFoldProp
  ( foldPropProgram
  , foldPropFuncDef
  , foldPropStmt
  , foldPropExpr
  ) where

import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

import IR.Frontend.Syntax.IRSyntax
import IR.Interp.IRInterp (applyBinOp)
import IR.Opt.ConstFold   (simplify)

-- Map from temp name to its statically known constant value.
type Env = Map Temp Int

-- Entry points

foldPropProgram :: Program -> Program
foldPropProgram = map foldPropFuncDef

foldPropFuncDef :: FuncDef -> FuncDef
foldPropFuncDef fd = fd { funcBody = fst (foldPropStmt Map.empty (funcBody fd)) }

-- Combined statement pass

-- Transform a statement, threading the constant environment left-to-right
-- through SEQ.  Returns the optimised statement and the updated environment.
foldPropStmt :: Env -> Stmt -> (Stmt, Env)

foldPropStmt env (SEQ s1 s2) =
  let (s1', env1) = foldPropStmt env  s1
      (s2', env2) = foldPropStmt env1 s2
  in (SEQ s1' s2', env2)
foldPropStmt env (MOVE (TEMP t) src) =
  let src' = foldPropExpr env src
      env'  = case src' of
                CONST n -> Map.insert t n env
                _       -> Map.delete t env
  in (MOVE (TEMP t) src', env')
foldPropStmt env (MOVE (MEM addr) src) =
  ( MOVE (MEM (foldPropExpr env addr)) (foldPropExpr env src)
  , env )
foldPropStmt env s = (mapStmtExprs (foldPropExpr env) s, env)

-- Combined expression pass

-- Substitute known-constant temporaries and fold constant sub-expressions
-- in a single bottom-up traversal.
foldPropExpr :: Env -> Expr -> Expr
foldPropExpr env (TEMP t) =
  case Map.lookup t env of
    Just n  -> CONST n
    Nothing -> TEMP t
foldPropExpr env (BINOP op e1 e2) =
  let e1' = foldPropExpr env e1
      e2' = foldPropExpr env e2
  in case (e1', e2') of
       (CONST a, CONST b)
         | op `notElem` [BDiv, BMod] || b /= 0 -> CONST (applyBinOp op a b)
       _ -> simplify op e1' e2'
foldPropExpr env (MEM e) 
  = MEM (foldPropExpr env e)
foldPropExpr env (CALL ef as) 
  = CALL (foldPropExpr env ef) (map (foldPropExpr env) as)
foldPropExpr env (ESEQ s e) 
  = ESEQ (fst (foldPropStmt env s)) (foldPropExpr env e)
foldPropExpr _   e = e

-- Helper

mapStmtExprs :: (Expr -> Expr) -> Stmt -> Stmt
mapStmtExprs f (EXP e) = EXP (f e)
mapStmtExprs f (JUMP e) = JUMP (f e)
mapStmtExprs f (CJUMP e lt lf) = CJUMP (f e) lt lf
mapStmtExprs f (RETURN es) = RETURN (map f es)
mapStmtExprs _ s = s
