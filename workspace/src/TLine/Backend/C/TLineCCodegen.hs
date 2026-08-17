module TLine.Backend.C.TLineCCodegen (compileTLine) where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map

import TLine.Frontend.Syntax.TLineSyntax

-- ---------------------------------------------------------------------------
-- Monad
-- ---------------------------------------------------------------------------
--
-- CgSt acumula:
--   cgLines  — linhas de código C geradas até agora
--   cgEnv    — ambiente de tipos das variáveis declaradas (usado para
--              decidir o formato de print/read e se precisa de strcpy)
--   cgIndent — nível de indentação corrente (em múltiplos de 4 espaços)

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

-- Emite uma linha com o recuo corrente.
emit :: String -> CgM ()
emit line = modify $ \s ->
  s { cgLines = cgLines s ++ [replicate (cgIndent s * 4) ' ' ++ line] }

blank :: CgM ()
blank = modify $ \s -> s { cgLines = cgLines s ++ [""] }

-- Executa m com um nível extra de indentação.
indented :: CgM () -> CgM ()
indented m = do
  modify $ \s -> s { cgIndent = cgIndent s + 1 }
  m
  modify $ \s -> s { cgIndent = cgIndent s - 1 }

setVar :: Var -> Ty -> CgM ()
setVar v t = modify $ \s -> s { cgEnv = Map.insert v t (cgEnv s) }

-- Retorna o tipo de uma variável; padrão TInt se não estiver no ambiente
-- (não deve ocorrer em programas bem tipados).
getVarTy :: Var -> CgM Ty
getVarTy v = Map.findWithDefault TInt v <$> gets cgEnv

-- ---------------------------------------------------------------------------
-- Auxiliares de tipo
-- ---------------------------------------------------------------------------

-- Representação C de tipos de valor.
cTy :: Ty -> String
cTy TInt    = "long"
cTy TBool   = "int"
cTy TString = "char *"

-- Declaração de variável local.
-- Strings usam buffer estático para suportar leitura via fgets.
localDecl :: Var -> Ty -> String
localDecl v TString = "char " ++ v ++ "[4096]"
localDecl v t       = cTy t ++ " " ++ v

-- Escapa caracteres especiais em literais de string para C.
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
-- Recebe o ambiente de tipos das variáveis para permitir a inferência de
-- tipo de e em SPrint e SRead.
-- ---------------------------------------------------------------------------

genExp :: Map Var Ty -> Exp -> String
genExp _   (EInt n)     = show n ++ "L"
genExp _   (EBool True) = "1"
genExp _   (EBool False)= "0"
genExp _   (EString s)  = "\"" ++ escapeC s ++ "\""
genExp _   (EVar v)     = v
genExp env (e1 :+: e2)  = parens (genExp env e1 ++ " + "  ++ genExp env e2)
genExp env (e1 :*: e2)  = parens (genExp env e1 ++ " * "  ++ genExp env e2)
genExp env (e1 :-: e2)  = parens (genExp env e1 ++ " - "  ++ genExp env e2)
genExp env (e1 :/: e2)  = parens (genExp env e1 ++ " / "  ++ genExp env e2)
genExp env (e1 :<: e2)  = parens (genExp env e1 ++ " < "  ++ genExp env e2)
genExp env (e1 :=: e2)  = parens (genExp env e1 ++ " == " ++ genExp env e2)
genExp env (Not e)      = "(!" ++ genExp env e ++ ")"

-- Inferência de tipo mínima para direcionar o formato de printf/scanf.
-- Em programas bem tipados, o verificador já garantiu consistência.
inferTy :: Map Var Ty -> Exp -> Ty
inferTy _   (EInt _)    = TInt
inferTy _   (EBool _)   = TBool
inferTy _   (EString _) = TString
inferTy env (EVar v)    = Map.findWithDefault TInt v env
inferTy _   (_ :+: _)  = TInt
inferTy _   (_ :*: _)  = TInt
inferTy _   (_ :-: _)  = TInt
inferTy _   (_ :/: _)  = TInt
inferTy _   (_ :<: _)  = TBool
inferTy _   (_ :=: _)  = TBool
inferTy _   (Not _)    = TBool

-- ---------------------------------------------------------------------------
-- Geração de declarações
-- ---------------------------------------------------------------------------

genStmt :: Stmt -> CgM ()

-- var v : T = e;
-- Strings: declara buffer e inicializa com strcpy.
-- Demais tipos: declara com inicializador direto.
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

-- v := e;
-- Strings: copia com strcpy; demais: atribuição direta.
genStmt (SAssign v e) = do
  env <- gets cgEnv
  ty  <- getVarTy v
  let rhs = genExp env e
  case ty of
    TString -> emit ("strcpy(" ++ v ++ ", " ++ rhs ++ ");")
    _       -> emit (v ++ " = " ++ rhs ++ ";")

-- print e;
-- Formato de printf escolhido pelo tipo inferido de e.
genStmt (SPrint e) = do
  env <- gets cgEnv
  let ce = genExp env e
  case inferTy env e of
    TInt    -> emit ("printf(\"%ld\\n\", (long)(" ++ ce ++ "));")
    TBool   -> emit ("printf(\"%s\\n\", (" ++ ce ++ ") ? \"true\" : \"false\");")
    TString -> emit ("printf(\"%s\\n\", " ++ ce ++ ");")

-- read prompt v;
-- Imprime o prompt e lê da stdin conforme o tipo de v.
-- Strings: usa fgets e remove o '\n' final.
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

-- ---------------------------------------------------------------------------
-- Ponto de entrada
-- ---------------------------------------------------------------------------

compileTLine :: TLine -> Either String String
compileTLine (TLine stmts) = runCg $ do
  emit "#include <stdio.h>"
  emit "#include <stdlib.h>"
  emit "#include <string.h>"
  blank
  emit "int main(void) {"
  indented $ do
    mapM_ genStmt stmts
    emit "return 0;"
  emit "}"
