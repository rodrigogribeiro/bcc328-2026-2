module TExp.Interp.TExpInterp where

import Control.Monad.Except
import Control.Monad.Identity

import TExp.Frontend.Syntax.TExpSyntax

-- Values produced by the interpreter

data Value
  = VBool Bool
  | VNat  Int
  deriving (Eq, Ord, Show)

-- Interpreter monad:
-- ExceptT String Identity is sufficient because the language
-- has no variables (no state) and no I/O effects.

type Interp a = ExceptT String Identity a

-- Top-level entry point

eval :: Term -> Either String Value
eval t = runIdentity (runExceptT (evalTerm t))

-- Display a value

showValue :: Value -> String
showValue (VBool True)  = "true"
showValue (VBool False) = "false"
showValue (VNat n)      = show n

-- Big-step evaluation

evalTerm :: Term -> Interp Value
evalTerm TTrue = pure (VBool True)
evalTerm TFalse = pure (VBool False)
evalTerm (TIf t1 t2 t3) = do
    v1 <- evalTerm t1
    case v1 of
      VBool True  -> evalTerm t2
      VBool False -> evalTerm t3
      _           -> throwError "Runtime error in if: condition is not a boolean"
evalTerm TZero = pure (VNat 0)
evalTerm (TSucc t1) = do
    v <- evalTerm t1
    case v of
      VNat n -> pure (VNat (n + 1))
      _      -> throwError "Runtime error in succ: argument is not a natural number"
evalTerm (TPred t1) = do
    v <- evalTerm t1
    case v of
      VNat 0 -> pure (VNat 0)
      VNat n -> pure (VNat (n - 1))
      _      -> throwError "Runtime error in pred: argument is not a natural number"
evalTerm (TIsZero t1) = do
    v <- evalTerm t1
    case v of
      VNat 0 -> pure (VBool True)
      VNat _ -> pure (VBool False)
      _      -> throwError "Runtime error in iszero: argument is not a natural number"
