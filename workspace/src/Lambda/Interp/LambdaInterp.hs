module Lambda.Interp.LambdaInterp
  ( Value(..)
  , runEval
  ) where

import Control.Monad (when)
import Control.Monad.Except
import Control.Monad.State
import qualified Data.Map.Strict as Map

import Lambda.Frontend.Syntax.Term
import Lambda.Frontend.Pretty.LambdaPretty

-- Values and runtime environment

data Value
  = VClosure Name Term Env
  | VInt  Int
  | VBool Bool

instance Show Value where
  show (VClosure x body _) = prettyTerm (Lam x body)
  show (VInt n)  = show n
  show (VBool b) = if b then "true" else "false"

type Env = Map.Map Name Value

-- Evaluation monad

type EvalM a = ExceptT String (State Int) a

stepLimit :: Int
stepLimit = 100000

tick :: EvalM ()
tick = do
    n <- lift get
    when (n >= stepLimit) $
      throwError $  "Step limit exceeded after "
                 ++ show stepLimit
                 ++ " steps (possible non-terminating term)"
    lift $ modify (+1)

-- Big-step call-by-value interpreter

eval :: Env -> Term -> EvalM Value
eval env (Var x) =
  case Map.lookup x env of
    Just v  -> return v
    Nothing -> throwError $ "Unbound variable: " ++ x
eval _   (Lit (LInt n))  = return (VInt n)
eval _   (Lit (LBool b)) = return (VBool b)
eval env (Lam x body) =
  return (VClosure x body env)
eval env (App t1 t2) = do
    tick
    v1 <- eval env t1
    v2 <- eval env t2
    case v1 of
      VClosure x body closEnv ->
        eval (Map.insert x v2 closEnv) body
      _ -> throwError "Application of non-function value"

runEval :: Term -> Either String Value
runEval t = evalState (runExceptT (eval Map.empty t)) 0
