module TLine.Frontend.TypeCheck.TLineTypeCheck where

import Control.Monad
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map

import TLine.Frontend.Syntax.TLineSyntax

-- top level type checking

typeCheck :: TLine -> Either String [(Var, Ty)]
typeCheck p = either Left (Right . Map.toList) (runTcM (tcTLine p))

-- type checking programs

tcTLine :: TLine -> TcM ()
tcTLine (TLine ss)
  = mapM_ tcStmt ss

-- type checking statements

tcStmt :: Stmt -> TcM ()
tcStmt (SDecl v t e)
  = do
      t' <- tcExp e
      unless (t == t') $
        throwError "Type error"
      addNewVar v t
tcStmt (SAssign v e)
  = do
      t <- lookupVar v
      t' <- tcExp e
      unless (t == t') $
        throwError "Type error"
tcStmt (SRead e v)
  = do
      t <- tcExp e
      unless (t == TString) $
        throwError "Type error"
      t' <- lookupVar v
      unless (t' == TInt) $
        throwError "Type error"
      pure ()
tcStmt (SPrint e)
  = do
      _ <- tcExp e
      pure ()

-- type checking expressions

tcExp :: Exp -> TcM Ty
tcExp (EInt _) = pure TInt
tcExp (EBool _) = pure TBool
tcExp (EString _) = pure TString
tcExp (EVar v) = lookupVar v
tcExp (e1 :+: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TInt) $
        throwError "Type error"
      unless (ty2 == TInt) $
        throwError "Type error"
      pure TInt
tcExp (e1 :*: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TInt) $
        throwError "Type error"
      unless (ty2 == TInt) $
        throwError "Type error"
      pure TInt
tcExp (e1 :-: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TInt) $
        throwError "Type error"
      unless (ty2 == TInt) $
        throwError "Type error"
      pure TInt
tcExp (e1 :/: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TInt) $
        throwError "Type error"
      unless (ty2 == TInt) $
        throwError "Type error"
      pure TInt
tcExp (e1 :<: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TInt) $
        throwError "Type error"
      unless (ty2 == TInt) $
        throwError "Type error"
      pure TBool
tcExp (e1 :=: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TInt) $
        throwError "Type error"
      unless (ty2 == TInt) $
        throwError "Type error"
      pure TBool
tcExp (Not e1)
  = do
      ty <- tcExp e1
      unless (ty == TBool) $
        throwError "Type error"
      pure TBool

-- definition of the typing context

type Ctx = Map Var Ty

-- definition of the type checking monad

type TcM a = StateT Ctx (ExceptT String Identity) a

runTcM :: TcM a -> Either String Ctx
runTcM m = runIdentity (runExceptT (execStateT m Map.empty))

addNewVar :: Var -> Ty -> TcM ()
addNewVar v t = modify (Map.insert v t)

lookupVar :: Var -> TcM Ty
lookupVar v
  = do
      mt <- gets (Map.lookup v)
      case mt of
        Just ty -> pure ty
        Nothing -> throwError $ "Undefined variable:" ++ v
