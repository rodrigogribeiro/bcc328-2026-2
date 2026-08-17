module TWhile.Backend.IR.TWhileCodegen (compileTWhile) where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State

import qualified IR.Frontend.Syntax.IRSyntax as IR
import TWhile.Frontend.Syntax.TWhileSyntax

-- Code generation monad

data CgState = CgState
  { nextLabel :: Int
  , stmtAcc   :: [IR.Stmt]
  }

type CgM a = StateT CgState (ExceptT String Identity) a

initState :: CgState
initState = CgState 0 []

runCgM :: CgM () -> Either String [IR.Stmt]
runCgM m = runIdentity (runExceptT (fmap stmtAcc (execStateT m initState)))

-- Generate a fresh label with the given prefix.
freshLabel :: String -> CgM IR.Label
freshLabel prefix = do
  n <- gets nextLabel
  modify (\s -> s { nextLabel = n + 1 })
  return (prefix ++ "_" ++ show n)

emit :: IR.Stmt -> CgM ()
emit s = modify (\st -> st { stmtAcc = stmtAcc st ++ [s] })

-- Top-level entry point

-- Compile a TWhile program into a single-function IR program.
--
-- Strings are not representable in the integer IR; string literals compile
-- to CONST(0) and read prompts are silently dropped.
compileTWhile :: TWhile -> Either String IR.Program
compileTWhile (TWhile stmts) =
  case runCgM (mapM_ codegenStmt stmts) of
    Left err -> Left err
    Right ss -> Right [IR.FuncDef "main" [] (foldStmts ss)]

-- Fold a flat list of statements into a right-associative SEQ tree.
foldStmts :: [IR.Stmt] -> IR.Stmt
foldStmts []     = IR.EXP (IR.CONST 0)  -- empty program: no-op
foldStmts [s]    = s
foldStmts (s:ss) = IR.SEQ s (foldStmts ss)

-- Statement code generation

codegenStmt :: Stmt -> CgM ()
codegenStmt (SDecl v _ e) = do
  ir <- codegenExp e
  emit (IR.MOVE (IR.TEMP v) ir)
codegenStmt (SAssign v e) = do
  ir <- codegenExp e
  emit (IR.MOVE (IR.TEMP v) ir)
codegenStmt (SPrint e) = do
  ir <- codegenExp e
  emit (IR.EXP (IR.CALL (IR.NAME "print") [ir]))
codegenStmt (SRead _ v) =
  -- The prompt expression is a TString and cannot be represented in the
  -- integer IR; it is discarded.  The value is obtained from the built-in
  -- 'read_int' function.
  emit (IR.MOVE (IR.TEMP v) (IR.CALL (IR.NAME "read_int") []))
-- while (cond) body  →
--
--   LABEL lh
--   CJUMP(cond, lb, lf)
--   LABEL lb
--   <body>
--   JUMP(NAME lh)
--   LABEL lf
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
-- if (cond) b1 else b2  →
--
--   CJUMP(cond, lt, lf)
--   LABEL lt
--   <b1>
--   JUMP(NAME le)
--   LABEL lf
--   <b2>
--   LABEL le
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

-- Expression code generation

codegenExp :: Exp -> CgM IR.Expr
codegenExp (EInt n)      = return (IR.CONST n)
codegenExp (EBool True)  = return (IR.CONST 1)
codegenExp (EBool False) = return (IR.CONST 0)
codegenExp (EString _)   = return (IR.CONST 0)  -- strings not supported in IR
codegenExp (EVar v)      = return (IR.TEMP v)

codegenExp (e1 :+: e2)  = IR.BINOP IR.BAdd <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :*: e2)  = IR.BINOP IR.BMul <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :-: e2)  = IR.BINOP IR.BSub <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :/: e2)  = IR.BINOP IR.BDiv <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :<: e2)  = IR.BINOP IR.BLt  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :=: e2)  = IR.BINOP IR.BEq  <$> codegenExp e1 <*> codegenExp e2

-- Boolean connectives: since booleans are 0/1, bitwise AND/OR coincide with
-- logical AND/OR for values in {0,1}.
codegenExp (e1 :&&: e2) = IR.BINOP IR.BAnd <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :||: e2) = IR.BINOP IR.BOr  <$> codegenExp e1 <*> codegenExp e2

-- NOT x: (x == 0) gives 1 when x=0 (false) and 0 when x=1 (true).
codegenExp (Not e)      = IR.BINOP IR.BEq (IR.CONST 0) <$> codegenExp e
