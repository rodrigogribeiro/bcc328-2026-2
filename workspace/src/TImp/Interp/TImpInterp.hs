module TImp.Interp.TImpInterp (interpret) where

import Control.Monad
import Control.Monad.Except
import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (fromMaybe)

import TImp.Frontend.Syntax.TImpSyntax

-- Values (value semantics: records are values, not references)

data Value
  = VInt    Int
  | VBool   Bool
  | VString String
  | VRecord Name (Map Field Value)
  | VUnit
  deriving (Eq, Show)

-- Interpreter state and monad

data InterpState = InterpState
  { varEnv    :: Map Var Value
  , funcEnv   :: Map Name FuncDecl
  }

type InterpM a = StateT InterpState (ExceptT String IO) a

runInterp :: InterpState -> InterpM a -> IO (Either String a)
runInterp st m = runExceptT (evalStateT m st)

-- Entry point

interpret :: TImp -> IO (Either String ())
interpret (TImp decls stmts) = do
  let fenv  = Map.fromList [(n, fd) | DFunc (fd@(FuncDecl n _ _ _)) <- decls]
      initSt = InterpState Map.empty fenv
  runInterp initSt $ do
    _ <- execBlock stmts
    pure ()

-- Block and statement execution

execBlock :: [Stmt] -> InterpM (Maybe Value)
execBlock []     = pure Nothing
execBlock (s:ss) = do
  r <- execStmt s
  case r of
    Just _  -> pure r
    Nothing -> execBlock ss

execStmt :: Stmt -> InterpM (Maybe Value)

execStmt (SDecl v _ e) = do
  val <- evalExp e
  modify (\st -> st { varEnv = Map.insert v val (varEnv st) })
  pure Nothing

execStmt (SAssign v e) = do
  val <- evalExp e
  modify (\st -> st { varEnv = Map.insert v val (varEnv st) })
  pure Nothing

execStmt (SFieldAssign v f e) = do
  rval <- lookupVar v
  newVal <- evalExp e
  case rval of
    VRecord name fields ->
      let fields' = Map.insert f newVal fields
      in  modify (\st -> st { varEnv = Map.insert v (VRecord name fields') (varEnv st) })
    _ -> throwError (v ++ " is not a record")
  pure Nothing

execStmt (SWhile e body) = do
  cond <- evalExp e
  case cond of
    VBool True -> do
      r <- execBlock body
      case r of
        Just _  -> pure r      -- return propagates out of loop
        Nothing -> execStmt (SWhile e body)
    VBool False -> pure Nothing
    _ -> throwError "while condition is not a boolean"

execStmt (SIf e b1 b2) = do
  cond <- evalExp e
  case cond of
    VBool True  -> withLocalEnv (execBlock b1)
    VBool False -> withLocalEnv (execBlock b2)
    _           -> throwError "if condition is not a boolean"

execStmt (SRead _ v) = do
  line <- liftIO getLine
  case reads line of
    [(n, "")] -> do
      modify (\st -> st { varEnv = Map.insert v (VInt n) (varEnv st) })
      pure Nothing
    _ -> throwError ("read: not a valid integer: " ++ show line)

execStmt (SPrint e) = do
  val <- evalExp e
  liftIO (putStrLn (showValue val))
  pure Nothing

execStmt (SReturn Nothing) = pure (Just VUnit)

execStmt (SReturn (Just e)) = do
  val <- evalExp e
  pure (Just val)

execStmt (SCall fname args) = do
  argVals <- mapM evalExp args
  _ <- callFunc fname argVals
  pure Nothing

-- Expression evaluation

evalExp :: Exp -> InterpM Value

evalExp (EInt n)    = pure (VInt n)
evalExp (EBool b)   = pure (VBool b)
evalExp (EString s) = pure (VString s)
evalExp (EVar v)    = lookupVar v

evalExp (EField e f) = do
  v <- evalExp e
  case v of
    VRecord _ fields ->
      case Map.lookup f fields of
        Just val -> pure val
        Nothing  -> throwError ("Record has no field: " ++ f)
    _ -> throwError "Field access on non-record value"

evalExp (ECall fname args) = do
  argVals <- mapM evalExp args
  callFunc fname argVals

evalExp (ENew rname initFields) = do
  vals <- mapM (\(f, e) -> (,) f <$> evalExp e) initFields
  pure (VRecord rname (Map.fromList vals))

evalExp (e1 :+: e2)  = intBinOp (+) e1 e2
evalExp (e1 :*: e2)  = intBinOp (*) e1 e2
evalExp (e1 :-: e2)  = intBinOp (-) e1 e2
evalExp (e1 :/: e2)  = do
  v1 <- evalIntExp e1; v2 <- evalIntExp e2
  when (v2 == 0) $ throwError "Division by zero"
  pure (VInt (v1 `div` v2))

evalExp (e1 :<:  e2) = intCmpOp (<)  e1 e2
evalExp (e1 :>:  e2) = intCmpOp (>)  e1 e2
evalExp (e1 :=:  e2) = intCmpOp (==) e1 e2
evalExp (e1 :!=: e2) = intCmpOp (/=) e1 e2
evalExp (e1 :<=: e2) = intCmpOp (<=) e1 e2
evalExp (e1 :>=: e2) = intCmpOp (>=) e1 e2

evalExp (Not e) = do
  v <- evalExp e
  case v of
    VBool b -> pure (VBool (not b))
    _       -> throwError "not: expected Bool"

evalExp (e1 :&&: e2) = do
  v1 <- evalExp e1
  case v1 of
    VBool False -> pure (VBool False)   -- short-circuit
    VBool True  -> evalExp e2
    _           -> throwError "&&: expected Bool on left"

evalExp (e1 :||: e2) = do
  v1 <- evalExp e1
  case v1 of
    VBool True  -> pure (VBool True)    -- short-circuit
    VBool False -> evalExp e2
    _           -> throwError "||: expected Bool on left"

-- Function call

callFunc :: Name -> [Value] -> InterpM Value
callFunc fname argVals = do
  fenv <- gets funcEnv
  case Map.lookup fname fenv of
    Nothing -> throwError ("Undefined function: " ++ fname)
    Just (FuncDecl _ params _ body) -> do
      when (length params /= length argVals) $
        throwError ("Arity mismatch calling " ++ fname)
      let bindings = zip [v | Param v _ <- params] argVals
      withFreshEnv bindings $ do
        r <- execBlock body
        pure (fromMaybe VUnit r)

-- Environment helpers

lookupVar :: Var -> InterpM Value
lookupVar v = do
  mt <- gets (Map.lookup v . varEnv)
  case mt of
    Just val -> pure val
    Nothing  -> throwError ("Undefined variable: " ++ v)

withLocalEnv :: InterpM a -> InterpM a
withLocalEnv m = do
  saved <- gets varEnv
  r     <- m
  modify (\st -> st { varEnv = saved })
  pure r

withFreshEnv :: [(Var, Value)] -> InterpM a -> InterpM a
withFreshEnv bindings m = do
  saved <- gets varEnv
  modify (\st -> st { varEnv = Map.fromList bindings })
  r <- m
  modify (\st -> st { varEnv = saved })
  pure r

-- Arithmetic / comparison helpers

evalIntExp :: Exp -> InterpM Int
evalIntExp e = do
  v <- evalExp e
  case v of
    VInt n -> pure n
    _      -> throwError "Expected integer"

intBinOp :: (Int -> Int -> Int) -> Exp -> Exp -> InterpM Value
intBinOp op e1 e2 = VInt <$> (op <$> evalIntExp e1 <*> evalIntExp e2)

intCmpOp :: (Int -> Int -> Bool) -> Exp -> Exp -> InterpM Value
intCmpOp op e1 e2 = VBool <$> (op <$> evalIntExp e1 <*> evalIntExp e2)

-- Value pretty-printing

showValue :: Value -> String
showValue (VInt n)        = show n
showValue (VBool b)       = if b then "true" else "false"
showValue (VString s)     = s
showValue (VRecord n flds) =
  n ++ " { " ++ fields ++ " }"
  where fields = unwords [ f ++ " = " ++ showValue v ++ ";"
                          | (f, v) <- Map.toList flds ]
showValue VUnit           = "()"
