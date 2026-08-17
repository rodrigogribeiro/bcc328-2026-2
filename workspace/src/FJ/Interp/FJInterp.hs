module FJ.Interp.FJInterp
  ( FJValue(..)
  , evalProgram
  , evalExpr
  , showValue
  ) where

import Control.Monad (unless)
import Control.Monad.Except
import Data.List (intercalate, findIndex)

import FJ.Frontend.Syntax.FJSyntax
import FJ.Frontend.ClassTable.ClassTable

-- Runtime values

data FJValue = FJVal ClassName [FJValue]
  deriving (Eq)

showValue :: FJValue -> String
showValue (FJVal c [])   = "new " ++ c ++ "()"
showValue (FJVal c args) =
    "new " ++ c ++ "(" ++ intercalate ", " (map showValue args) ++ ")"

instance Show FJValue where
  show = showValue

-- Evaluation monad

type EvalM a = Except String a

subst :: [(VarName, Expr)] -> Expr -> Expr
subst env (EVar x) =
  case lookup x env of
    Just e  -> e
    Nothing -> EVar x
subst env (EField e f)   = EField (subst env e) f
subst env (EInvk e m as) = EInvk (subst env e) m (map (subst env) as)
subst env (ENew c as)    = ENew c (map (subst env) as)
subst env (ECast c e)    = ECast c (subst env e)

-- Convert a value back to a canonical expression (for substitution).
valToExpr :: FJValue -> Expr
valToExpr (FJVal c args) = ENew c (map valToExpr args)

-- Big-step call-by-value interpreter

eval :: ClassTable -> Expr -> EvalM FJValue
eval ct (ENew c args) = do
    vs <- mapM (eval ct) args
    return (FJVal c vs)
eval _ (EVar x) = throwError $ "Unbound variable at runtime: " ++ x
eval ct (EField e f) = do
    v@(FJVal c _) <- eval ct e
    fs <- maybe (throwError $ "Unknown class at runtime: " ++ c)
                return
                (classFields ct c)
    case findIndex (\(_, fn) -> fn == f) fs of
      Nothing -> throwError $ "Field '" ++ f ++ "' not found in '" ++ c ++ "'"
      Just i  -> return (nthArg v i)
eval ct (EInvk e m args) = do
    v@(FJVal c _) <- eval ct e
    argVals <- mapM (eval ct) args
    (params, body) <-
      maybe (throwError $ "Method '" ++ m ++ "' not found in '" ++ c ++ "'")
            return
            (mbody ct m c)
    let env = ("this", valToExpr v) :
              zip params (map valToExpr argVals)
    eval ct (subst env body)
eval ct (ECast c e) = do
    v@(FJVal d _) <- eval ct e
    unless (isSubtype ct d c) $
      throwError $ "ClassCastException: '" ++ d ++ "' is not a subtype of '" ++ c ++ "'"
    return v

nthArg :: FJValue -> Int -> FJValue
nthArg (FJVal _ vs) i = vs !! i

evalProgram :: Program -> Either String FJValue
evalProgram (Program cls main) =
  runExcept (eval (buildCT cls) main)

evalExpr :: ClassTable -> Expr -> Either String FJValue
evalExpr ct e = runExcept (eval ct e)
