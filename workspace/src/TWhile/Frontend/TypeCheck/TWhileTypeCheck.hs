module TWhile.Frontend.TypeCheck.TWhileTypeCheck where

import Control.Monad
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map

import TWhile.Frontend.Syntax.TWhileSyntax

-- top level type checking

typeCheck :: TWhile -> Either String [(Var, Ty)]
typeCheck p = either Left (Right . Map.toList) (runTcM (tcTWhile p))

-- type checking programs

tcTWhile :: TWhile -> TcM ()
tcTWhile (TWhile ss)
  = tcBlock ss

tcBlock :: [Stmt] -> TcM ()
tcBlock ss = withLocalCtx (mapM_ tcStmt ss)

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
tcStmt (SWhile e b)
  = do
      t <- tcExp e
      unless (t == TBool) $
        throwError "Type error"
      tcBlock b
tcStmt (SIf e b1 b2)
  = do
      t <- tcExp e
      unless (t == TBool) $
        throwError "Type error"
      tcBlock b1
      tcBlock b2

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
tcExp (e1 :&&: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TBool) $
        throwError "Type error: && expects Bool on the left"
      unless (ty2 == TBool) $
        throwError "Type error: && expects Bool on the right"
      pure TBool
tcExp (e1 :||: e2)
  = do
      ty1 <- tcExp e1
      ty2 <- tcExp e2
      unless (ty1 == TBool) $
        throwError "Type error: || expects Bool on the left"
      unless (ty2 == TBool) $
        throwError "Type error: || expects Bool on the right"
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

withLocalCtx :: TcM a -> TcM a
withLocalCtx m = do
  ctx <- get
  r <- m
  put ctx
  pure r

