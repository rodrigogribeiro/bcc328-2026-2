module TWhile.Backend.C.TWhileCCodegen (compileTWhile) where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map

import TWhile.Frontend.Syntax.TWhileSyntax

-- ---------------------------------------------------------------------------
-- Monad
-- ---------------------------------------------------------------------------
--
-- Idêntico ao de TLine, acrescido de escopo léxico em blocos:
-- withBlock salva e restaura cgEnv antes/depois de cada bloco para que
-- variáveis declaradas dentro de while/if não "vazem" para o ambiente
-- externo durante a geração do restante do programa.
--
-- Nota: o código C gerado já provê escopo correto via `{ }` (C99).
-- O restore de cgEnv é necessário apenas para que inferTy/getVarTy
-- funcionem corretamente ao processar as declarações após o bloco.

data CgSt = CgSt
  { cgLines  :: [String]
  , cgEnv    :: Map Var Ty
  , cgIndent :: Int
  }

type CgM a = StateT CgSt (ExceptT String Identity) a

runCg :: CgM () -> Either String String
runCg m =
  case runIdentity (runExceptT (execStateT m initSt)) of
    Left err -> Left err
    Right st -> Right (unlines (cgLines st))
  where
    initSt = CgSt [] Map.empty 0

emit :: String -> CgM ()
emit line = modify $ \s ->
  s { cgLines = cgLines s ++ [replicate (cgIndent s * 4) ' ' ++ line] }

blank :: CgM ()
blank = modify $ \s -> s { cgLines = cgLines s ++ [""] }

indented :: CgM () -> CgM ()
indented m = do
  modify $ \s -> s { cgIndent = cgIndent s + 1 }
  m
  modify $ \s -> s { cgIndent = cgIndent s - 1 }

-- Executa m em um escopo aninhado: variáveis declaradas dentro não
-- são visíveis no ambiente após o bloco.
withBlock :: CgM () -> CgM ()
withBlock m = do
  saved <- gets cgEnv
  m
  modify $ \s -> s { cgEnv = saved }

setVar :: Var -> Ty -> CgM ()
setVar v t = modify $ \s -> s { cgEnv = Map.insert v t (cgEnv s) }

getVarTy :: Var -> CgM Ty
getVarTy v = Map.findWithDefault TInt v <$> gets cgEnv

-- ---------------------------------------------------------------------------
-- Auxiliares de tipo
-- ---------------------------------------------------------------------------

cTy :: Ty -> String
cTy TInt    = "long"
cTy TBool   = "int"
cTy TString = "char *"

localDecl :: Var -> Ty -> String
localDecl v TString = "char " ++ v ++ "[4096]"
localDecl v t       = cTy t ++ " " ++ v

escapeC :: String -> String
escapeC = concatMap esc
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc '\n' = "\\n"
    esc '\t' = "\\t"
    esc c    = [c]

parens :: String -> String
parens s = "(" ++ s ++ ")"

-- ---------------------------------------------------------------------------
-- Geração de expressões (pura)
--
-- Estende TLine com && e ||.
-- ---------------------------------------------------------------------------

genExp :: Map Var Ty -> Exp -> String
genExp _   (EInt n)      = show n ++ "L"
genExp _   (EBool True)  = "1"
genExp _   (EBool False) = "0"
genExp _   (EString s)   = "\"" ++ escapeC s ++ "\""
genExp _   (EVar v)      = v
genExp env (e1 :+: e2)   = parens (genExp env e1 ++ " + "  ++ genExp env e2)
genExp env (e1 :*: e2)   = parens (genExp env e1 ++ " * "  ++ genExp env e2)
genExp env (e1 :-: e2)   = parens (genExp env e1 ++ " - "  ++ genExp env e2)
genExp env (e1 :/: e2)   = parens (genExp env e1 ++ " / "  ++ genExp env e2)
genExp env (e1 :<: e2)   = parens (genExp env e1 ++ " < "  ++ genExp env e2)
genExp env (e1 :=: e2)   = parens (genExp env e1 ++ " == " ++ genExp env e2)
genExp env (e1 :&&: e2)  = parens (genExp env e1 ++ " && " ++ genExp env e2)
genExp env (e1 :||: e2)  = parens (genExp env e1 ++ " || " ++ genExp env e2)
genExp env (Not e)        = "(!" ++ genExp env e ++ ")"

inferTy :: Map Var Ty -> Exp -> Ty
inferTy _   (EInt _)     = TInt
inferTy _   (EBool _)    = TBool
inferTy _   (EString _)  = TString
inferTy env (EVar v)     = Map.findWithDefault TInt v env
inferTy _   (_ :+: _)   = TInt
inferTy _   (_ :*: _)   = TInt
inferTy _   (_ :-: _)   = TInt
inferTy _   (_ :/: _)   = TInt
inferTy _   (_ :<: _)   = TBool
inferTy _   (_ :=: _)   = TBool
inferTy _   (_ :&&: _)  = TBool
inferTy _   (_ :||: _)  = TBool
inferTy _   (Not _)     = TBool

-- ---------------------------------------------------------------------------
-- Geração de declarações
-- ---------------------------------------------------------------------------

genStmt :: Stmt -> CgM ()

genStmt (SDecl v t e) = do
  env <- gets cgEnv
  let rhs = genExp env e
  case t of
    TString -> do
      emit (localDecl v TString ++ ";")
      emit ("strcpy(" ++ v ++ ", " ++ rhs ++ ");")
    _ ->
      emit (localDecl v t ++ " = " ++ rhs ++ ";")
  setVar v t

genStmt (SAssign v e) = do
  env <- gets cgEnv
  ty  <- getVarTy v
  let rhs = genExp env e
  case ty of
    TString -> emit ("strcpy(" ++ v ++ ", " ++ rhs ++ ");")
    _       -> emit (v ++ " = " ++ rhs ++ ";")

genStmt (SPrint e) = do
  env <- gets cgEnv
  let ce = genExp env e
  case inferTy env e of
    TInt    -> emit ("printf(\"%ld\\n\", (long)(" ++ ce ++ "));")
    TBool   -> emit ("printf(\"%s\\n\", (" ++ ce ++ ") ? \"true\" : \"false\");")
    TString -> emit ("printf(\"%s\\n\", " ++ ce ++ ");")

genStmt (SRead prompt v) = do
  env <- gets cgEnv
  let ps = genExp env prompt
  emit ("printf(\"%s\", " ++ ps ++ ");")
  ty <- getVarTy v
  case ty of
    TInt    -> emit ("scanf(\"%ld\", &" ++ v ++ ");")
    TBool   -> emit ("scanf(\"%d\", &" ++ v ++ ");")
    TString -> do
      emit ("fgets(" ++ v ++ ", 4096, stdin);")
      emit (v ++ "[strcspn(" ++ v ++ ", \"\\n\")] = '\\0';")

-- while (cond) { body }
-- O corpo é gerado dentro de withBlock para restaurar o ambiente de tipos
-- após o bloco e evitar que variáveis internas poluam o ambiente externo.
genStmt (SWhile e body) = do
  env <- gets cgEnv
  emit ("while (" ++ genExp env e ++ ") {")
  withBlock $ indented (mapM_ genStmt body)
  emit "}"

-- if (cond) { b1 } else { b2 }
-- Cada ramo tem seu próprio escopo léxico.
genStmt (SIf e b1 b2) = do
  env <- gets cgEnv
  emit ("if (" ++ genExp env e ++ ") {")
  withBlock $ indented (mapM_ genStmt b1)
  emit "} else {"
  withBlock $ indented (mapM_ genStmt b2)
  emit "}"

-- ---------------------------------------------------------------------------
-- Ponto de entrada
-- ---------------------------------------------------------------------------

compileTWhile :: TWhile -> Either String String
compileTWhile (TWhile stmts) = runCg $ do
  emit "#include <stdio.h>"
  emit "#include <stdlib.h>"
  emit "#include <string.h>"
  blank
  emit "int main(void) {"
  indented $ do
    mapM_ genStmt stmts
    emit "return 0;"
  emit "}"
