module MiniML.Frontend.Interp.MiniMLInterp where

import Control.Monad.Except
import Control.Monad.Identity
import qualified Data.Map.Strict as Map

import MiniML.Frontend.Syntax.Exp
import MiniML.Frontend.Syntax.Type (Name)


data Value
  = VInt  Int
  | VBool Bool
  | VClosure Name Exp Env
  deriving (Eq)

instance Show Value where
  show (VInt n)        = show n
  show (VBool True)    = "true"
  show (VBool False)   = "false"
  show (VClosure {})   = "<fun>"

type Env = Map.Map Name Value

emptyEnv :: Env
emptyEnv = Map.empty

-- Evaluation monad

type EvalM a = ExceptT String Identity a

runEval :: Env -> Exp -> Either String Value
runEval env e = runIdentity (runExceptT (eval env e))

-- Big-step call-by-value interpreter

eval :: Env -> Exp -> EvalM Value
eval env (Var n)
  = case Map.lookup n env of
      Just v  -> return v
      Nothing -> throwError $ "Unbound variable: " ++ n
eval _ (Lit (LInt  n)) = return (VInt  n)
eval _ (Lit (LBool b)) = return (VBool b)
eval env (Lam x _ body)
  = return (VClosure x body env)
eval env (App e1 e2)
  = do
      v1 <- eval env e1
      v2 <- eval env e2
      case v1 of
        VClosure x body closEnv ->
          eval (Map.insert x v2 closEnv) body
        _ -> throwError "Application of a non-function value"
eval env (Let n _ e body)
  = do
      v <- eval env e
      eval (Map.insert n v env) body
