module IR.Opt.ConstFold
  ( foldProgram
  , foldFuncDef
  , foldStmt
  , foldExpr
  , simplify
  ) where

import IR.Frontend.Syntax.IRSyntax
import IR.Interp.IRInterp (applyBinOp)

foldProgram :: Program -> Program
foldProgram = map foldFuncDef

foldFuncDef :: FuncDef -> FuncDef
foldFuncDef fd = fd { funcBody = foldStmt (funcBody fd) }

foldStmt :: Stmt -> Stmt
foldStmt (MOVE dst src) = MOVE (foldExpr dst) (foldExpr src)
foldStmt (EXP e) = EXP (foldExpr e)
foldStmt (SEQ s1 s2) = SEQ (foldStmt s1) (foldStmt s2)
foldStmt (JUMP e) = JUMP (foldExpr e)
foldStmt (CJUMP e lt lf) = CJUMP (foldExpr e) lt lf
foldStmt (RETURN es) = RETURN (map foldExpr es)
foldStmt s = s

foldExpr :: Expr -> Expr
foldExpr (BINOP op e1 e2) =
  let e1' = foldExpr e1
      e2' = foldExpr e2
  in case (e1', e2') of
       (CONST a, CONST b)
         | op `notElem` [BDiv, BMod] || b /= 0 -> CONST (applyBinOp op a b)
       _ -> simplify op e1' e2'
foldExpr (MEM e) = MEM (foldExpr e)
foldExpr (CALL ef as) = CALL (foldExpr ef) (map foldExpr as)
foldExpr (ESEQ s e) = ESEQ (foldStmt s) (foldExpr e)
foldExpr e = e

-- Algebraic identities applied when operands are not both CONST.
simplify :: BinOp -> Expr -> Expr -> Expr
simplify BAdd e (CONST 0) = e
simplify BAdd (CONST 0) e = e
simplify BSub e (CONST 0) = e
simplify BMul _ (CONST 0) = CONST 0
simplify BMul (CONST 0)  _ = CONST 0
simplify BMul e (CONST 1) = e
simplify BMul (CONST 1)  e = e
simplify BDiv e (CONST 1) = e
simplify BAnd _ (CONST 0) = CONST 0
simplify BAnd (CONST 0)  _ = CONST 0
simplify BAnd e (CONST 1) = e
simplify BAnd (CONST 1) e = e
simplify BOr  e (CONST 0) = e
simplify BOr  (CONST 0) e = e
simplify BXor e (CONST 0) = e
simplify BXor (CONST 0) e = e
simplify op e1 e2 = BINOP op e1 e2
