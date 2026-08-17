module TImp.Frontend.TypeCheck.TImpTypeCheck
  ( typeCheck
  , TcResult (..)
  ) where

import Control.Monad
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.Reader
import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map

import TImp.Frontend.Syntax.TImpSyntax

-- Type checking result

data TcResult = TcResult
  { tcVarCtx    :: [(Var, Ty)] 
  , tcRecordCtx :: [(Name, [(Field, Ty)])]
  , tcFuncCtx   :: [(Name, ([Ty], RetTy))]
  } deriving (Show)

-- Type checking monad

data TcEnv = TcEnv
  { recordEnv  :: Map Name [(Field, Ty)]
  , funcEnv    :: Map Name ([Ty], RetTy)
  , returnType :: Maybe RetTy
  }

type VarCtx = Map Var Ty

type TcM a = ReaderT TcEnv (StateT VarCtx (ExceptT String Identity)) a

runTcM :: TcEnv -> TcM a -> Either String VarCtx
runTcM env m = runIdentity (runExceptT (execStateT (runReaderT m env) Map.empty))

-- Entry point

typeCheck :: TImp -> Either String TcResult
typeCheck (TImp decls stmts) = do
  -- Build record and function environments from declarations
  recEnv  <- buildRecordEnv  decls
  funcEnv' <- buildFuncEnv recEnv decls
  let env = TcEnv recEnv funcEnv' Nothing
  -- Type-check all function bodies
  mapM_ (tcFuncDecl env) [fd | DFunc fd <- decls]
  -- Type-check top-level statements
  finalCtx <- runTcM env (tcBlock stmts)
  pure TcResult
    { tcVarCtx    = Map.toList finalCtx
    , tcRecordCtx = Map.toList recEnv
    , tcFuncCtx   = Map.toList funcEnv'
    }

-- Environment builders

buildRecordEnv :: [Decl] -> Either String (Map Name [(Field, Ty)])
buildRecordEnv decls = foldM addRecord Map.empty [r | DRecord r <- decls]
  where
    addRecord env (RecordDecl name fields) = do
      when (Map.member name env) $
        Left ("Duplicate record definition: " ++ name)
      let fieldPairs = [(f, t) | FieldDecl f t <- fields]
      pure (Map.insert name fieldPairs env)

buildFuncEnv :: Map Name [(Field, Ty)]
             -> [Decl]
             -> Either String (Map Name ([Ty], RetTy))
buildFuncEnv _recEnv decls = foldM addFunc Map.empty [fd | DFunc fd <- decls]
  where
    addFunc env (FuncDecl name params rt _) = do
      when (Map.member name env) $
        Left ("Duplicate function definition: " ++ name)
      let paramTypes = [t | Param _ t <- params]
      pure (Map.insert name (paramTypes, rt) env)

-- Function declaration type checking

tcFuncDecl :: TcEnv -> FuncDecl -> Either String ()
tcFuncDecl baseEnv (FuncDecl name params retTy body) = do
  let paramPairs = [(v, t) | Param v t <- params]
      initCtx    = Map.fromList paramPairs
      env        = baseEnv { returnType = Just retTy }
  case runIdentity (runExceptT (execStateT (runReaderT (tcBlock body) env) initCtx)) of
    Left err -> Left ("In function " ++ name ++ ": " ++ err)
    Right _  -> Right ()

-- Block and statement type checking

tcBlock :: [Stmt] -> TcM ()
tcBlock stmts = withLocalCtx (mapM_ tcStmt stmts)

tcStmt :: Stmt -> TcM ()

tcStmt (SDecl v t e) = do
  t' <- tcExp e
  unless (t == t') $
    throwError ("Type error in declaration of " ++ v
                ++ ": declared " ++ showTy t
                ++ " but expression has type " ++ showTy t')
  addVar v t

tcStmt (SAssign v e) = do
  t  <- lookupVar v
  t' <- tcExp e
  unless (t == t') $
    throwError ("Type error in assignment to " ++ v
                ++ ": variable has type " ++ showTy t
                ++ " but expression has type " ++ showTy t')

tcStmt (SFieldAssign v f e) = do
  vTy <- lookupVar v
  case vTy of
    TRecord rname -> do
      fieldTy <- lookupField rname f
      t' <- tcExp e
      unless (fieldTy == t') $
        throwError ("Type error in field assignment " ++ v ++ "." ++ f
                    ++ ": field has type " ++ showTy fieldTy
                    ++ " but expression has type " ++ showTy t')
    _ -> throwError (v ++ " is not a record (type: " ++ showTy vTy ++ ")")

tcStmt (SWhile e body) = do
  t <- tcExp e
  unless (t == TBool) $
    throwError ("while condition must be Bool, got " ++ showTy t)
  tcBlock body

tcStmt (SIf e b1 b2) = do
  t <- tcExp e
  unless (t == TBool) $
    throwError ("if condition must be Bool, got " ++ showTy t)
  tcBlock b1
  tcBlock b2

tcStmt (SRead e v) = do
  t <- tcExp e
  unless (t == TString) $
    throwError ("read prompt must be String, got " ++ showTy t)
  tv <- lookupVar v
  unless (tv == TInt) $
    throwError ("read target must be Int, got " ++ showTy tv)

tcStmt (SPrint e) = do
  _ <- tcExp e
  pure ()

tcStmt (SReturn Nothing) = do
  mrt <- asks returnType
  case mrt of
    Nothing       -> throwError "return outside a function"
    Just RTVoid   -> pure ()
    Just (RTTy t) -> throwError ("return with no value in function returning " ++ showTy t)

tcStmt (SReturn (Just e)) = do
  mrt <- asks returnType
  t'  <- tcExp e
  case mrt of
    Nothing        -> throwError "return outside a function"
    Just RTVoid    -> throwError "return with value in void function"
    Just (RTTy t)  ->
      unless (t == t') $
        throwError ("return type mismatch: expected " ++ showTy t
                    ++ " but got " ++ showTy t')

tcStmt (SCall fname args) = do
  fenv <- asks funcEnv
  case Map.lookup fname fenv of
    Nothing         -> throwError ("Undefined function: " ++ fname)
    Just (pts, rt)  -> do
      unless (rt == RTVoid) $
        throwError ("Non-void call used as statement: " ++ fname
                    ++ " (use assignment to capture the return value)")
      argTys <- mapM tcExp args
      unless (argTys == pts) $
        throwError ("Argument type mismatch in call to " ++ fname)

-- Expression type checking

tcExp :: Exp -> TcM Ty
tcExp (EInt _)    = pure TInt
tcExp (EBool _)   = pure TBool
tcExp (EString _) = pure TString
tcExp (EVar v)    = lookupVar v

tcExp (EField e f) = do
  t <- tcExp e
  case t of
    TRecord rname -> lookupField rname f
    _ -> throwError ("Field access on non-record type " ++ showTy t)

tcExp (ECall fname args) = do
  fenv <- asks funcEnv
  case Map.lookup fname fenv of
    Nothing        -> throwError ("Undefined function: " ++ fname)
    Just (pts, rt) -> do
      argTys <- mapM tcExp args
      unless (argTys == pts) $
        throwError ("Argument type mismatch in call to " ++ fname
                    ++ ": expected " ++ show (map showTy pts)
                    ++ " but got "   ++ show (map showTy argTys))
      case rt of
        RTVoid    -> throwError ("Void function " ++ fname ++ " used as expression")
        RTTy ty   -> pure ty

tcExp (ENew rname fields) = do
  renv <- asks recordEnv
  case Map.lookup rname renv of
    Nothing      -> throwError ("Undefined record type: " ++ rname)
    Just declFlds -> do
      -- Check that every provided field exists and has the right type.
      -- Missing fields are allowed (partial initialisation); the interpreter
      -- will raise a runtime error if an uninitialised field is accessed.
      mapM_ (checkField declFlds) fields
      let provided = map fst fields
          declared = map fst declFlds
      unless (all (`elem` declared) provided) $
        throwError ("Unknown field in new " ++ rname)
      pure (TRecord rname)
  where
    checkField declFlds (f, e) = do
      case lookup f declFlds of
        Nothing -> throwError ("Record " ++ rname ++ " has no field " ++ f)
        Just ft -> do
          t <- tcExp e
          unless (t == ft) $
            throwError ("Field " ++ f ++ " of " ++ rname
                        ++ " expects " ++ showTy ft
                        ++ " but got " ++ showTy t)

tcExp (e1 :+: e2)  = checkArith e1 e2 >> pure TInt
tcExp (e1 :*: e2)  = checkArith e1 e2 >> pure TInt
tcExp (e1 :-: e2)  = checkArith e1 e2 >> pure TInt
tcExp (e1 :/: e2)  = checkArith e1 e2 >> pure TInt

tcExp (e1 :<: e2)  = checkArith e1 e2 >> pure TBool
tcExp (e1 :>: e2)  = checkArith e1 e2 >> pure TBool
tcExp (e1 :<=: e2) = checkArith e1 e2 >> pure TBool
tcExp (e1 :>=: e2) = checkArith e1 e2 >> pure TBool
tcExp (e1 :=: e2)  = checkArith e1 e2 >> pure TBool
tcExp (e1 :!=: e2) = checkArith e1 e2 >> pure TBool

tcExp (Not e) = do
  t <- tcExp e
  unless (t == TBool) $
    throwError ("not expects Bool, got " ++ showTy t)
  pure TBool

tcExp (e1 :&&: e2) = checkBool e1 e2 >> pure TBool
tcExp (e1 :||: e2) = checkBool e1 e2 >> pure TBool

-- Helpers

checkArith :: Exp -> Exp -> TcM ()
checkArith e1 e2 = do
  t1 <- tcExp e1
  t2 <- tcExp e2
  unless (t1 == TInt) $ throwError ("Expected Int, got " ++ showTy t1)
  unless (t2 == TInt) $ throwError ("Expected Int, got " ++ showTy t2)

checkBool :: Exp -> Exp -> TcM ()
checkBool e1 e2 = do
  t1 <- tcExp e1
  t2 <- tcExp e2
  unless (t1 == TBool) $ throwError ("Expected Bool, got " ++ showTy t1)
  unless (t2 == TBool) $ throwError ("Expected Bool, got " ++ showTy t2)

lookupField :: Name -> Field -> TcM Ty
lookupField rname f = do
  renv <- asks recordEnv
  case Map.lookup rname renv of
    Nothing   -> throwError ("Unknown record type: " ++ rname)
    Just flds -> case lookup f flds of
      Nothing -> throwError ("Record " ++ rname ++ " has no field " ++ f)
      Just t  -> pure t

withLocalCtx :: TcM a -> TcM a
withLocalCtx m = do
  ctx <- get
  r   <- m
  put ctx
  pure r

addVar :: Var -> Ty -> TcM ()
addVar v t = modify (Map.insert v t)

lookupVar :: Var -> TcM Ty
lookupVar v = do
  mt <- gets (Map.lookup v)
  case mt of
    Just ty -> pure ty
    Nothing -> throwError ("Undefined variable: " ++ v)

showTy :: Ty -> String
showTy TInt        = "int"
showTy TBool       = "bool"
showTy TString     = "string"
showTy (TRecord n) = n
