---
title: "Verificação de Tipos"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Mostrar a correspondência direta entre regras de inferência e equações de
  código Haskell.

- Implementar verificadores de tipos para linguagens com crescente complexidade:
  TExp, TLine, TWhile e TImp.

# Introdução

## Introdução

- O sistema de tipos define **o que** é um programa bem tipado via regras de
  inferência
- O **verificador de tipos** implementa essa especificação como código

## Introdução

- Correspondência direta: cada regra de inferência vira uma equação Haskell
- A estrutura da mônada de verificação espelha os ambientes semânticos

# Verificação para TExp

## A Linguagem TExp

Tipos e termos:

```haskell
data Ty   = TBool | TNat

data Term
  = TTrue  | TFalse
  | TIf Term Term Term
  | TZero
  | TSucc Term | TPred Term | TIsZero Term
```

## A Linguagem TExp

- Dois tipos: $\mathbf{Bool}$ e $\mathbf{Nat}$
- **Sem variáveis** → sem contexto externo necessário
- Mônada: `TcM = ExceptT String Identity`

## Da Regra à Equação

Regra de inferência:

$$\frac{\vdash t_1 : \mathbf{Bool} \quad \vdash t_2 : T \quad \vdash t_3 : T}{\vdash \mathbf{if}\ t_1\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 : T} \quad\text{(T-If)}$$

## Da Regra à Equação

Equação Haskell:

```haskell
tcTerm (TIf t1 t2 t3) = do
    ty1 <- tcTerm t1
    unless (ty1 == TBool) $
        throwError "condition must have type Bool"
    ty2 <- tcTerm t2
    ty3 <- tcTerm t3
    unless (ty2 == ty3) $
        throwError "both branches must have the same type"
    pure ty2
```

## Typechecking

```haskell
tcTerm :: Term -> TcM Ty
tcTerm TTrue  = pure TBool                  -- (T-True)
tcTerm TFalse = pure TBool                  -- (T-False)
tcTerm TZero  = pure TNat                   -- (T-Zero)
```

## Typechecking

```haskell
tcTerm (TSucc t1) = do                      -- (T-Succ)
    ty <- tcTerm t1
    unless (ty == TNat) $ throwError "..."
    pure TNat
tcTerm (TIsZero t1) = do                    -- (T-IsZero)
    ty <- tcTerm t1
    unless (ty == TNat) $ throwError "..."
    pure TBool
-- ... TIf, TPred análogos
```

# Verificação para TLine

## A Linguagem TLine

```haskell
data Ty = TInt | TBool | TString

data Stmt
  = SDecl   Var Ty Exp   -- var x : T = e ;
  | SAssign Var Exp      -- x := e ;
  | SRead   Exp Var      -- read prompt x ;
  | SPrint  Exp          -- print e ;
```

## Linguagem TLine

- Principal novidade: **variáveis** precisam de contexto
- Contexto $\Gamma : \mathit{Var} \rightharpoonup \mathit{Ty}$
- Mônada: `StateT Ctx (ExceptT String Identity)`

## Linguagem TLine

- Regras para comandos: $\Gamma \vdash s \dashv \Gamma'$

$$\frac{\Gamma \vdash e : T}{\Gamma \vdash \mathbf{var}\ x : T = e \dashv \Gamma[x \mapsto T]} \quad\text{(T-Decl)}$$

## Linguagem TLine

$$\frac{x \in \mathrm{dom}(\Gamma) \quad \Gamma \vdash e : \Gamma(x)}{\Gamma \vdash x \mathbin{:=} e \dashv \Gamma} \quad\text{(T-Assign)}$$

- Declaração **estende** o contexto: $\Gamma' = \Gamma[x \mapsto T]$
- Atribuição **preserva** o contexto: $\Gamma' = \Gamma$

## Typechecking

```haskell
tcStmt :: Stmt -> TcM ()
tcStmt (SDecl v t e) = do          -- (T-Decl)
    t' <- tcExp e
    unless (t == t') $ throwError "Type error"
    addNewVar v t                   -- Gamma[x -> T]
```

## Typechecking

```haskell
tcStmt (SAssign v e) = do
    t  <- lookupVar v
    t' <- tcExp e
    unless (t == t') $ throwError "Type error"
```

## Typechecking

```haskell
tcStmt (SRead e v) = do 
    t <- tcExp e
    unless (t == TString) $ throwError "Type error"
    t' <- lookupVar v
    unless (t' == TInt) $ throwError "Type error"
tcStmt (SPrint e) = tcExp e >> pure ()
```

# Verificação para TWhile

## Escopo

- TWhile adiciona condicionais e repetição com **escopo local**:

```haskell
data Stmt
  = -- ... tudo de TLine ...
  | SIf    Exp Block Block
  | SWhile Exp Block

type Block = [Stmt]
```

## Escopo

- Variáveis declaradas dentro de `if`/`while` **não escapam** para fora
- Regras formalizam isso: contexto de saída = contexto de entrada

## Escopo

$$\frac{\Gamma \vdash e : \mathbf{Bool} \quad \Gamma \vdash B_1 \dashv \Gamma_1 \quad \Gamma \vdash B_2 \dashv \Gamma_2}{\Gamma \vdash \mathbf{if}\ e\ \mathbf{then}\ B_1\ \mathbf{else}\ B_2 \dashv \Gamma} \quad\text{(T-If)}$$

## Escopo

$$\frac{\Gamma \vdash e : \mathbf{Bool} \quad \Gamma \vdash B \dashv \Gamma'}{\Gamma \vdash \mathbf{while}\ e\ \mathbf{do}\ B \dashv \Gamma} \quad\text{(T-While)}$$

## Implementando Escopo

```haskell
withLocalCtx :: TcM a -> TcM a
withLocalCtx m = do
    ctx <- get
    r   <- m
    put ctx
    pure r
```

## Implementando Escopo

```haskell
tcBlock :: [Stmt] -> TcM ()
tcBlock ss = withLocalCtx (mapM_ tcStmt ss)

tcStmt (SIf e b1 b2) = do 
    t <- tcExp e
    unless (t == TBool) $ throwError "Type error"
    tcBlock b1
    tcBlock b2
```

# Sistema de Tipos para TImp

## Ambientes

- TImp estende TWhile com funções e registros
  - $$\Delta$$
    : ambiente de campos de registros
  - $$\Phi$$
    : ambiente de funções

## Relações

- Expressões: $\Gamma;\Delta;\Phi \vdash e : \tau$
- Comandos: $\Gamma;\Delta;\Phi;\rho_\mathit{ret} \vdash s \dashv \Gamma'$

## Registros

- **Acesso a campo (T-Field):**

$$\frac{\Gamma;\Delta;\Phi \vdash e : R \quad \Delta(R)(f) = \tau}{\Gamma;\Delta;\Phi \vdash e.f : \tau}$$

## Registros

- **Construção de registro (T-New):**

$$\frac{R \in \mathrm{dom}(\Delta) \quad \Delta(R) = \overline{(f_i:\tau_i)} \quad \Gamma;\Delta;\Phi \vdash e_i : \tau_i}{\Gamma;\Delta;\Phi \vdash \mathbf{new}\ R\{\overline{f_i=e_i}\} : R}$$

## Funções

- **Chamada como expressão (T-CallExpr):**

$$\frac{\Phi(f) = ([\tau_1,\ldots,\tau_n],\;\tau) \quad \Gamma;\Delta;\Phi \vdash e_i : \tau_i}{\Gamma;\Delta;\Phi \vdash f(e_1,\ldots,e_n) : \tau}$$

## Funções

- **Declaração de função (T-FuncDecl):**

$$\frac{[x_1\!\mapsto\!\tau_1,\ldots,x_n\!\mapsto\!\tau_n];\Delta;\Phi;\rho \vdash B \dashv \_}{\Delta;\Phi \vdash \mathbf{fn}\ f(\overline{x_i:\tau_i}):\rho\ \{B\}\ \checkmark}$$

# Verificação para TImp

## A Mônada

- TImp adiciona funções e registros — Informação **imutável** vai em `ReaderT`:

```haskell
data TcEnv = TcEnv
  { recordEnv  :: Map Name [(Field, Ty)]  -- Delta
  , funcEnv    :: Map Name ([Ty], RetTy)  -- Phi
  , returnType :: Maybe RetTy             -- rho_ret
  }
```

## A Mônada

```haskell
type VarCtx = Map Var Ty

type TcM a = ReaderT TcEnv
               (StateT VarCtx
                 (ExceptT String Identity)) a
```

## Registros

```haskell
tcExp (EField e f) = do
  t <- tcExp e
  case t of
    TRecord rname -> lookupField rname f
    _ -> throwError "Field access on non-record type"
```

## Funções

```haskell
tcExp (ECall fname args) = do
  fenv <- asks funcEnv
  case Map.lookup fname fenv of
    Nothing -> throwError ("Undefined function: " ++ fname)
    Just (pts, rt) -> do
      argTys <- mapM tcExp args
      unless (argTys == pts) $ throwError "Argument type mismatch"
      case rt of
        RTVoid  -> throwError "Void function used as expression"
        RTTy ty -> pure ty
```

## Função

```haskell
tcFuncDecl :: TcEnv -> FuncDecl -> Either String ()
tcFuncDecl baseEnv (FuncDecl name params retTy body) = do
  let paramPairs = [(v, t) | Param v t <- params]
      initCtx    = Map.fromList paramPairs
      env        = baseEnv { returnType = Just retTy }
  case runIdentity (runExceptT
         (execStateT (runReaderT (tcBlock body) env) initCtx)) of
    Left err -> Left ("In function " ++ name ++ ": " ++ err)
    Right _  -> Right ()
```

## Função

- Contexto inicial = parâmetros formais
- `returnType` fixado via `local` para verificar `return`
- Variáveis externas à função são **invisíveis**

# Conclusão

## Conclusão

- O verificador de tipos é uma **transcrição sistemática** do sistema de tipos
- Cada regra de inferência corresponde a uma equação Haskell
