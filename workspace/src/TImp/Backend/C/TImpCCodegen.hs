module TImp.Backend.C.TImpCCodegen (compileTImp) where

import Control.Monad (unless)
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.List (find, intercalate)
import Data.Map (Map)
import qualified Data.Map as Map

import TImp.Frontend.Syntax.TImpSyntax

-- ---------------------------------------------------------------------------
-- Monad
-- ---------------------------------------------------------------------------
--
-- Além das linhas e do recuo, o estado carrega:
--   cgEnv    — tipos das variáveis locais/parâmetros correntes
--   cgRecEnv — declarações de campos de cada tipo registro
--              (necessário para ENew, EField e SFieldAssign)
--   cgFnEnv  — tipo de retorno de cada função
--              (necessário para inferTy em chamadas usadas no print)
--
-- Estratégia para records:
--   Cada tipo registro R é mapeado para um struct C e uma função auxiliar
--   `make_R(campo1, campo2, ...)` que aloca via malloc e inicializa os
--   campos.  Assim ENew compila para uma chamada de função pura, sem
--   precisar de statement-expressions (extensão GCC) nem temporários extras.
--
-- Representação de tipos em C:
--   TInt          → long
--   TBool         → int  (0 = false, 1 = true)
--   TString       → char * (parâmetros) / char v[4096] (variáveis locais)
--   TRecord "R"   → R *  (ponteiro — records são sempre alocados no heap)

data CgSt = CgSt
  { cgLines  :: [String]
  , cgIndent :: Int
  , cgEnv    :: Map Var Ty             -- tipos de variáveis locais
  , cgRecEnv :: Map Name [FieldDecl]   -- campos de cada record
  , cgFnEnv  :: Map Name RetTy         -- tipo de retorno de cada função
  }

type CgM a = StateT CgSt (ExceptT String Identity) a

runCg :: Map Name [FieldDecl] -> Map Name RetTy -> CgM () -> Either String String
runCg recEnv fnEnv m =
  case runIdentity (runExceptT (execStateT m initSt)) of
    Left err -> Left err
    Right st -> Right (unlines (cgLines st))
  where
    initSt = CgSt [] 0 Map.empty recEnv fnEnv

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
-- Representações C de tipos
-- ---------------------------------------------------------------------------

-- Tipo C de valor (usado em expressões e retornos).
cTy :: Ty -> String
cTy TInt        = "long"
cTy TBool       = "int"
cTy TString     = "char *"
cTy (TRecord r) = r ++ " *"

-- Tipo C de parâmetro formal.
-- Strings são sempre char *.
cParamTy :: Ty -> String
cParamTy = cTy  -- já retorna char * para TString e R* para TRecord

-- Declaração de variável local.
-- Strings locais usam buffer fixo; records são ponteiros inicializados.
localDecl :: Var -> Ty -> String
localDecl v TString     = "char " ++ v ++ "[4096]"
localDecl v (TRecord r) = r ++ " *" ++ v
localDecl v t           = cTy t ++ " " ++ v

-- Tipo de retorno de função.
cRetTy :: RetTy -> String
cRetTy RTVoid    = "void"
cRetTy (RTTy t)  = cTy t

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

commas :: [String] -> String
commas = intercalate ", "

-- ---------------------------------------------------------------------------
-- Geração de expressões (monádica)
--
-- genExp é monádica para poder consultar cgEnv e cgRecEnv sem precisar
-- passá-los explicitamente por toda a recursão.  Não emite linhas —
-- apenas retorna a string de expressão C.
-- ---------------------------------------------------------------------------

genExp :: Exp -> CgM String

genExp (EInt n)      = pure (show n ++ "L")
genExp (EBool True)  = pure "1"
genExp (EBool False) = pure "0"
genExp (EString s)   = pure ("\"" ++ escapeC s ++ "\"")
genExp (EVar v)      = pure v

-- Acesso a campo: e.f
-- O caso mais comum é EVar; o caso geral envolve expressão de tipo record.
genExp (EField (EVar v) f) = pure (v ++ "->" ++ f)
genExp (EField e f) = do
  ce <- genExp e
  pure (parens ce ++ "->" ++ f)

-- Chamada de função como expressão: f(args)
genExp (ECall fname args) = do
  cArgs <- mapM genExp args
  pure (fname ++ "(" ++ commas cArgs ++ ")")

-- Construção de record: new R { f1 = e1, ... }
-- Compila para make_R(v_f1, v_f2, ...) com campos na ordem da declaração.
-- Campos ausentes na lista de inicialização resultam em erro.
genExp (ENew rname initFields) = do
  recEnv <- gets cgRecEnv
  case Map.lookup rname recEnv of
    Nothing ->
      throwError ("Tipo record desconhecido: " ++ rname)
    Just flds -> do
      args <- mapM (lookupField initFields rname) flds
      cArgs <- mapM genExp args
      pure ("make_" ++ rname ++ "(" ++ commas cArgs ++ ")")
  where
    lookupField pairs rn (FieldDecl f _) =
      case lookup f pairs of
        Just e  -> pure e
        Nothing -> throwError
          ("Campo ausente '" ++ f ++ "' na construção de " ++ rn)

-- Operadores binários
genExp (e1 :+: e2)  = binop e1 " + "  e2
genExp (e1 :*: e2)  = binop e1 " * "  e2
genExp (e1 :-: e2)  = binop e1 " - "  e2
genExp (e1 :/: e2)  = binop e1 " / "  e2
genExp (e1 :<: e2)  = binop e1 " < "  e2
genExp (e1 :>: e2)  = binop e1 " > "  e2
genExp (e1 :=: e2)  = binop e1 " == " e2
genExp (e1 :!=: e2) = binop e1 " != " e2
genExp (e1 :<=: e2) = binop e1 " <= " e2
genExp (e1 :>=: e2) = binop e1 " >= " e2
genExp (e1 :&&: e2) = binop e1 " && " e2
genExp (e1 :||: e2) = binop e1 " || " e2
genExp (Not e)      = (\ce -> "(!" ++ ce ++ ")") <$> genExp e

binop :: Exp -> String -> Exp -> CgM String
binop e1 op e2 = do
  c1 <- genExp e1
  c2 <- genExp e2
  pure (parens (c1 ++ op ++ c2))

-- ---------------------------------------------------------------------------
-- Inferência de tipo para print/read (monádica)
--
-- Necessária para escolher o formato printf/scanf correto.
-- Para ECall, consulta cgFnEnv; para EField, consulta cgRecEnv.
-- ---------------------------------------------------------------------------

inferTy :: Exp -> CgM Ty
inferTy (EInt _)      = pure TInt
inferTy (EBool _)     = pure TBool
inferTy (EString _)   = pure TString
inferTy (EVar v)      = getVarTy v
inferTy (ENew rname _)= pure (TRecord rname)
inferTy (EField e f)  = do
  t <- inferTy e
  case t of
    TRecord rname -> fieldTy rname f
    _             -> pure TInt
inferTy (ECall fname _) = do
  fnEnv <- gets cgFnEnv
  case Map.lookup fname fnEnv of
    Just (RTTy t) -> pure t
    _             -> pure TInt
inferTy (_ :+: _)  = pure TInt
inferTy (_ :*: _)  = pure TInt
inferTy (_ :-: _)  = pure TInt
inferTy (_ :/: _)  = pure TInt
inferTy (_ :<: _)  = pure TBool
inferTy (_ :>: _)  = pure TBool
inferTy (_ :=: _)  = pure TBool
inferTy (_ :!=: _) = pure TBool
inferTy (_ :<=: _) = pure TBool
inferTy (_ :>=: _) = pure TBool
inferTy (_ :&&: _) = pure TBool
inferTy (_ :||: _) = pure TBool
inferTy (Not _)    = pure TBool

fieldTy :: Name -> Field -> CgM Ty
fieldTy rname f = do
  recEnv <- gets cgRecEnv
  case Map.lookup rname recEnv of
    Nothing   -> pure TInt
    Just flds ->
      case find (\(FieldDecl fname _) -> fname == f) flds of
        Just (FieldDecl _ t) -> pure t
        Nothing              -> pure TInt

-- ---------------------------------------------------------------------------
-- Geração de declarações (statements)
-- ---------------------------------------------------------------------------

genStmt :: Stmt -> CgM ()

-- var v : T = e;
genStmt (SDecl v t e) = do
  ce <- genExp e
  case t of
    TString -> do
      emit (localDecl v TString ++ ";")
      emit ("strcpy(" ++ v ++ ", " ++ ce ++ ");")
    _ ->
      emit (localDecl v t ++ " = " ++ ce ++ ";")
  setVar v t

-- v := e;
genStmt (SAssign v e) = do
  ty <- getVarTy v
  ce <- genExp e
  case ty of
    TString -> emit ("strcpy(" ++ v ++ ", " ++ ce ++ ");")
    _       -> emit (v ++ " = " ++ ce ++ ";")

-- v.f := e;
-- Records são ponteiros: v->f = ce;
genStmt (SFieldAssign v f e) = do
  ce <- genExp e
  emit (v ++ "->" ++ f ++ " = " ++ ce ++ ";")

-- while (cond) { body }
genStmt (SWhile e body) = do
  cond <- genExp e
  emit ("while (" ++ cond ++ ") {")
  withBlock $ indented (mapM_ genStmt body)
  emit "}"

-- if (cond) { b1 } else { b2 }
genStmt (SIf e b1 b2) = do
  cond <- genExp e
  emit ("if (" ++ cond ++ ") {")
  withBlock $ indented (mapM_ genStmt b1)
  emit "} else {"
  withBlock $ indented (mapM_ genStmt b2)
  emit "}"

-- print e;
genStmt (SPrint e) = do
  ce <- genExp e
  ty <- inferTy e
  case ty of
    TInt        -> emit ("printf(\"%ld\\n\", (long)(" ++ ce ++ "));")
    TBool       -> emit ("printf(\"%s\\n\", (" ++ ce ++ ") ? \"true\" : \"false\");")
    TString     -> emit ("printf(\"%s\\n\", " ++ ce ++ ");")
    TRecord _   -> emit ("printf(\"%p\\n\", (void *)(" ++ ce ++ "));")

-- read prompt v;
genStmt (SRead prompt v) = do
  cp <- genExp prompt
  emit ("printf(\"%s\", " ++ cp ++ ");")
  ty <- getVarTy v
  case ty of
    TInt    -> emit ("scanf(\"%ld\", &" ++ v ++ ");")
    TBool   -> emit ("scanf(\"%d\", &" ++ v ++ ");")
    TString -> do
      emit ("fgets(" ++ v ++ ", 4096, stdin);")
      emit (v ++ "[strcspn(" ++ v ++ ", \"\\n\")] = '\\0';")
    TRecord _ ->
      throwError ("Leitura de record não suportada")

-- return e; | return;
genStmt (SReturn Nothing)  = emit "return;"
genStmt (SReturn (Just e)) = do
  ce <- genExp e
  emit ("return " ++ ce ++ ";")

-- f(args);  (chamada de função como statement)
genStmt (SCall fname args) = do
  cArgs <- mapM genExp args
  emit (fname ++ "(" ++ commas cArgs ++ ");")

-- ---------------------------------------------------------------------------
-- Geração de declarações de record e funções auxiliares make_R
-- ---------------------------------------------------------------------------

-- Gera o typedef struct para um record:
--
--   typedef struct { T1 f1; T2 f2; } R;
genRecordTypedef :: RecordDecl -> CgM ()
genRecordTypedef (RecordDecl rname fields) = do
  emit ("typedef struct {")
  indented $ mapM_ emitField fields
  emit ("} " ++ rname ++ ";")
  blank
  where
    emitField (FieldDecl f t) = emit (cTy t ++ " " ++ f ++ ";")

-- Gera a função construtora make_R que aloca e inicializa um record:
--
--   R* make_R(T1 f1, T2 f2, ...) {
--       R* _r = (R*)malloc(sizeof(R));
--       _r->f1 = f1;
--       _r->f2 = f2;
--       return _r;
--   }
genMakeHelper :: RecordDecl -> CgM ()
genMakeHelper (RecordDecl rname fields) = do
  let params = commas [cTy t ++ " " ++ f | FieldDecl f t <- fields]
  emit (rname ++ "* make_" ++ rname ++ "(" ++ params ++ ") {")
  indented $ do
    emit (rname ++ "* _r = (" ++ rname ++ "*)malloc(sizeof(" ++ rname ++ "));")
    mapM_ (\(FieldDecl f _) -> emit ("_r->" ++ f ++ " = " ++ f ++ ";")) fields
    emit "return _r;"
  emit "}"
  blank

-- ---------------------------------------------------------------------------
-- Geração de funções de usuário
-- ---------------------------------------------------------------------------

-- Assinatura C de uma função (para forward declarations e definições).
funcSignature :: FuncDecl -> String
funcSignature (FuncDecl fname params retTy _) =
  cRetTy retTy ++ " " ++ fname ++ "(" ++ paramList ++ ")"
  where
    paramList
      | null params = "void"
      | otherwise   = commas [cParamTy t ++ " " ++ v | Param v t <- params]

-- Declaração avançada (forward declaration) para permitir chamadas mútuas.
genForwardDecl :: FuncDecl -> CgM ()
genForwardDecl fd = emit (funcSignature fd ++ ";")

-- Definição completa de uma função.
-- Parâmetros são registrados no cgEnv local da função.
genFuncDef :: FuncDecl -> CgM ()
genFuncDef fd@(FuncDecl _ params _ body) = do
  emit (funcSignature fd ++ " {")
  withBlock $ indented $ do
    -- Registra os tipos dos parâmetros no ambiente corrente.
    mapM_ (\(Param v t) -> setVar v t) params
    mapM_ genStmt body
  emit "}"
  blank

-- ---------------------------------------------------------------------------
-- Ponto de entrada
-- ---------------------------------------------------------------------------

compileTImp :: TImp -> Either String String
compileTImp (TImp decls body) = runCg recEnv fnEnv $ do
  -- Cabeçalhos
  emit "#include <stdio.h>"
  emit "#include <stdlib.h>"
  emit "#include <string.h>"
  blank
  -- Typedefs dos structs (devem vir antes das funções que os usam)
  mapM_ genRecordTypedef recDecls
  -- Funções auxiliares make_R
  mapM_ genMakeHelper recDecls
  -- Forward declarations de todas as funções do usuário
  -- (permite recursão mútua sem exigir ordem de declaração)
  unless (null funcDecls) $ do
    mapM_ genForwardDecl funcDecls
    blank
  -- Definições das funções do usuário
  mapM_ genFuncDef funcDecls
  -- Função main implícita com o bloco de topo do programa
  emit "int main(void) {"
  withBlock $ indented $ do
    mapM_ genStmt body
    emit "return 0;"
  emit "}"
  where
    recDecls  = [rd | DRecord rd <- decls]
    funcDecls = [fd | DFunc   fd <- decls]
    recEnv    = Map.fromList
      [ (rname, fields)
      | RecordDecl rname fields <- recDecls ]
    fnEnv     = Map.fromList
      [ (fname, retTy)
      | FuncDecl fname _ retTy _ <- funcDecls ]
