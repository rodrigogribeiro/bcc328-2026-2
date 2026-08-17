module TLine.Backend.IR.TLineCodegen (compileTLine) where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State

import qualified IR.Frontend.Syntax.IRSyntax as IR
import TLine.Frontend.Syntax.TLineSyntax

-- Code generation monad

newtype CgState = CgState
  { stmtAcc :: [IR.Stmt]
  }

type CgM a = StateT CgState (ExceptT String Identity) a

initState :: CgState
initState = CgState []

runCgM :: CgM () -> Either String [IR.Stmt]
runCgM m = runIdentity (runExceptT (fmap stmtAcc (execStateT m initState)))

emit :: IR.Stmt -> CgM ()
emit s = modify (\st -> st { stmtAcc = stmtAcc st ++ [s] })

-- Top-level entry point

-- Compile a TLine program into a single-function IR program.
--
-- Strings are not representable in the integer IR; string literals compile
-- to CONST(0) and read prompts are silently dropped.
compileTLine :: TLine -> Either String IR.Program
compileTLine (TLine stmts) =
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
  -- integer IR; it is discarded here.  The value is obtained from the
  -- built-in 'read_int' function.
  emit (IR.MOVE (IR.TEMP v) (IR.CALL (IR.NAME "read_int") []))

-- Expression code generation

codegenExp :: Exp -> CgM IR.Expr
codegenExp (EInt n)     = return (IR.CONST n)
codegenExp (EBool True) = return (IR.CONST 1)
codegenExp (EBool False)= return (IR.CONST 0)
codegenExp (EString _)  = return (IR.CONST 0)  -- strings not supported in IR
codegenExp (EVar v)     = return (IR.TEMP v)
codegenExp (e1 :+: e2) = IR.BINOP IR.BAdd <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :*: e2) = IR.BINOP IR.BMul <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :-: e2) = IR.BINOP IR.BSub <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :/: e2) = IR.BINOP IR.BDiv <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :<: e2) = IR.BINOP IR.BLt  <$> codegenExp e1 <*> codegenExp e2
codegenExp (e1 :=: e2) = IR.BINOP IR.BEq  <$> codegenExp e1 <*> codegenExp e2
-- NOT x: since booleans are encoded as 0 (false) / 1 (true), we use
-- (x == 0) which yields 1 when x=0 and 0 when x=1.
codegenExp (Not e) = IR.BINOP IR.BEq (IR.CONST 0) <$> codegenExp e
