module TImp.Backend.IR.TImpCodegen (compileTImp) where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.List (elemIndex)
import Data.Map (Map)
import qualified Data.Map as Map

import qualified IR.Frontend.Syntax.IRSyntax as IR
import TImp.Frontend.Syntax.TImpSyntax

-- Word size in bytes (64-bit targets).
wordSize :: Int
wordSize = 8

-- Code generation state

data CgState = CgState
  { nextLabel  :: Int
  , nextTemp   :: Int
  , stmtAcc    :: [IR.Stmt]
  , recFields  :: Map Name [Field]  -- record type → ordered field names
  , varTypes   :: Map Var Ty        -- tracked for field offset computation
  }

type CgM a = StateT CgState (ExceptT String Identity) a

initState :: Map Name [Field] -> CgState
initState rf = CgState 0 0 [] rf Map.empty

runCgM :: Map Name [Field] -> CgM () -> Either String [IR.Stmt]
runCgM rf m = runIdentity (runExceptT (fmap stmtAcc (execStateT m (initState rf))))

freshLabel :: String -> CgM IR.Label
freshLabel prefix = do
  n <- gets nextLabel
  modify (\s -> s { nextLabel = n + 1 })
  pure (prefix ++ "_" ++ show n)

freshTemp :: CgM IR.Temp
freshTemp = do
  n <- gets nextTemp
  modify (\s -> s { nextTemp = n + 1 })
  pure ("_t" ++ show n)

emit :: IR.Stmt -> CgM ()
emit s = modify (\st -> st { stmtAcc = stmtAcc st ++ [s] })

trackVar :: Var -> Ty -> CgM ()
trackVar v t = modify (\s -> s { varTypes = Map.insert v t (varTypes s) })

fieldIndex :: Name -> Field -> CgM Int
fieldIndex rname f = do
  rf <- gets recFields
  case Map.lookup rname rf of
    Nothing  -> throwError ("Unknown record type: " ++ rname)
    Just flds ->
      case elemIndex f flds of
        Nothing -> throwError ("Record " ++ rname ++ " has no field " ++ f)
        Just i  -> pure i

-- Entry point

compileTImp :: TImp -> Either String IR.Program
compileTImp (TImp decls stmts) = do
  let rf = Map.fromList
            [ (n, [f | FieldDecl f _ <- fields])
            | DRecord (RecordDecl n fields) <- decls ]
  -- Compile each function declaration
  funcDefs <- mapM (compileFuncDecl rf) [fd | DFunc fd <- decls]
  -- Compile top-level statements into an implicit main function
  mainStmts <- runCgM rf (mapM_ codegenStmt stmts)
  let mainDef = IR.FuncDef "main" [] (foldStmts mainStmts)
  pure (funcDefs ++ [mainDef])

compileFuncDecl :: Map Name [Field] -> FuncDecl -> Either String IR.FuncDef
compileFuncDecl rf (FuncDecl name params _ body) = do
  let paramNames = [v | Param v _ <- params]
      paramTypes = [(v, t) | Param v t <- params]
  stmts <- runCgM rf $ do
    -- Pre-populate variable type context with parameters
    mapM_ (uncurry trackVar) paramTypes
    mapM_ codegenStmt body
  pure (IR.FuncDef name paramNames (foldStmts stmts))

foldStmts :: [IR.Stmt] -> IR.Stmt
foldStmts []     = IR.EXP (IR.CONST 0)
foldStmts [s]    = s
foldStmts (s:ss) = IR.SEQ s (foldStmts ss)

-- Statement code generation

codegenStmt :: Stmt -> CgM ()
codegenStmt (SDecl v t e) = do
  ir <- codegenExp e
  emit (IR.MOVE (IR.TEMP v) ir)
  trackVar v t
codegenStmt (SAssign v e) = do
  ir <- codegenExp e
  emit (IR.MOVE (IR.TEMP v) ir)
codegenStmt (SFieldAssign v f e) = do
  vts <- gets varTypes
  case Map.lookup v vts of
    Nothing -> throwError ("Unknown variable type for " ++ v)
    Just (TRecord rname) -> do
      i   <- fieldIndex rname f
      rhs <- codegenExp e
      let addr = IR.BINOP IR.BAdd (IR.TEMP v) (IR.CONST (i * wordSize))
      emit (IR.MOVE (IR.MEM addr) rhs)
    Just t -> throwError (v ++ " is not a record (type: " ++ show t ++ ")")
codegenStmt (SWhile e body) = do
  lh <- freshLabel "while_head"
  lb <- freshLabel "while_body"
  lf <- freshLabel "while_exit"
  emit (IR.LABEL lh)
  cond <- codegenExp e
  emit (IR.CJUMP cond lb lf)
  emit (IR.LABEL lb)
  mapM_ codegenStmt body
  emit (IR.JUMP (IR.NAME lh))
  emit (IR.LABEL lf)
codegenStmt (SIf e b1 b2) = do
  lt <- freshLabel "if_true"
  lf <- freshLabel "if_false"
  le <- freshLabel "if_end"
  cond <- codegenExp e
  emit (IR.CJUMP cond lt lf)
  emit (IR.LABEL lt)
  mapM_ codegenStmt b1
  emit (IR.JUMP (IR.NAME le))
  emit (IR.LABEL lf)
  mapM_ codegenStmt b2
  emit (IR.LABEL le)
codegenStmt (SRead _ v) =
  emit (IR.MOVE (IR.TEMP v) (IR.CALL (IR.NAME "read_int") []))
codegenStmt (SPrint e) = do
  ir <- codegenExp e
  emit (IR.EXP (IR.CALL (IR.NAME "print") [ir]))
codegenStmt (SReturn Nothing) =
  emit (IR.RETURN [])
codegenStmt (SReturn (Just e)) = do
  ir <- codegenExp e
  emit (IR.RETURN [ir])
codegenStmt (SCall fname args) = do
  argIRs <- mapM codegenExp args
  emit (IR.EXP (IR.CALL (IR.NAME fname) argIRs))

-- Expression code generation

codegenExp :: Exp -> CgM IR.Expr
codegenExp (EInt n)      = pure (IR.CONST n)
codegenExp (EBool True)  = pure (IR.CONST 1)
codegenExp (EBool False) = pure (IR.CONST 0)
codegenExp (EString _)   = pure (IR.CONST 0)   -- strings not representable in integer IR
codegenExp (EVar v)      = pure (IR.TEMP v)
codegenExp (EField (EVar v) f) = do
  vts <- gets varTypes
  case Map.lookup v vts of
    Nothing -> throwError ("Unknown variable type for " ++ v)
    Just (TRecord rname) -> do
      i <- fieldIndex rname f
      let addr = IR.BINOP IR.BAdd (IR.TEMP v) (IR.CONST (i * wordSize))
      pure (IR.MEM addr)
    Just t -> throwError (v ++ " has non-record type " ++ show t)
codegenExp (EField _ _) =
  throwError "Field access on non-variable expression is not supported in IR codegen"
codegenExp (ECall fname args) = do
  argIRs <- mapM codegenExp args
  pure (IR.CALL (IR.NAME fname) argIRs)
codegenExp (ENew rname initFields) = do
  rf <- gets recFields
  case Map.lookup rname rf of
    Nothing   -> throwError ("Unknown record type: " ++ rname)
    Just flds -> do
      let n = length flds
      t <- freshTemp
      -- Evaluate field expressions in the order declared (not provided)
      fieldVals <- mapM (lookupFieldVal initFields) flds
      let allocStmt = IR.MOVE (IR.TEMP t) (IR.CALL (IR.NAME "alloc") [IR.CONST n])
          fieldStmts = [ IR.MOVE (IR.MEM (IR.BINOP IR.BAdd (IR.TEMP t) (IR.CONST (i * wordSize)))) v
                       | (i, v) <- zip [0..] fieldVals ]
          allStmts = allocStmt : fieldStmts
      pure (IR.ESEQ (foldStmts allStmts) (IR.TEMP t))
  where
    lookupFieldVal pairs f =
      case lookup f pairs of
        Nothing -> throwError ("Missing field " ++ f ++ " in new " ++ rname)
        Just e  -> codegenExp e

codegenExp (e1 :+: e2)  = IR.BINOP IR.BAdd <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :*: e2)  = IR.BINOP IR.BMul <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :-: e2)  = IR.BINOP IR.BSub <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :/: e2)  = IR.BINOP IR.BDiv <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :<: e2)  = IR.BINOP IR.BLt  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :>: e2)  = IR.BINOP IR.BGt  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :=: e2)  = IR.BINOP IR.BEq  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :!=: e2) = IR.BINOP IR.BNe  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :<=: e2) = IR.BINOP IR.BLe  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :>=: e2) = IR.BINOP IR.BGe  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :&&: e2) = IR.BINOP IR.BAnd <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :||: e2) = IR.BINOP IR.BOr  <$> codegenExp e1 <*> codegenExp e2
codegenExp (Not e)      = IR.BINOP IR.BEq (IR.CONST 0) <$> codegenExp e
