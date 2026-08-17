---
title: "Semântica de Linguagens Imperativas"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Estender a semântica da linguagem com comandos condicionais e de repetição.

- Apresentar a linguagem _TImp_, com declarações de funções e tipos registro.

## Objetivos

- Definir a semântica big-step para as novas construções.

- Mostrar como a especificação formal guia a implementação do interpretador.

# A Linguagem While

## Motivação

- A linguagem _Line_ executa apenas sequências de comandos

## Motivação

- Programas reais precisam de estruturas de controlo:
  - **Condicional**: executar blocos diferentes dependendo de uma condição
  - **Repetição**: executar um bloco enquanto uma condição for verdadeira

## Sintaxe

$$\begin{array}{lcl}
\mathit{prog} &::=& s^* \\[4pt]
s &::=& x \mathbin{:=} e \mid \mathbf{read}\; x \mid \mathbf{print}\; e \\
  &\mid& \mathbf{if}\; e\; \mathbf{then}\; \{s^*\}\; \mathbf{else}\; \{s^*\} \\
  &\mid& \mathbf{while}\; e\; \mathbf{do}\; \{s^*\} \\[4pt]
e &::=& v \mid x \mid e_1 + e_2 \mid e_1 * e_2 \\
  &\mid& e_1 < e_2 \mid e_1 = e_2 \mid e_1 \mathbin{|} e_2 \mid \neg e \\[4pt]
v &::=& n \mid \mathbf{true} \mid \mathbf{false}
\end{array}$$

## Tipos em Haskell

```haskell
data Value = VInt Int | VBool Bool

data Exp
  = EValue Value | EVar Var
  | Exp :+: Exp  | Exp :*: Exp
  | Exp :<: Exp  | Exp :=: Exp
  | Exp :|: Exp  | ENot Exp

data Stmt
  = SAssign Var Exp | SRead Var | SPrint Exp
  | SIf    Exp Block Block
  | SWhile Exp Block

type Block = [Stmt]
```

# Semântica Small-Step

## Expressões

- Idêntico à linguagem Line.
  - Exceto por novos operadores, que funcionam de maneira similar.

## Condicional

- **Avaliação da condição:**
  $$\frac{(\sigma, e) \to (\sigma, e')}{\left(\begin{array}{ll}
             \sigma,&\; \mathbf{if}\; e\; \mathbf{then}\; B_1\\
                    & \mathbf{else}\; B_2\\
             \end{array}\right) \to \left(\begin{array}{ll}\sigma,& \mathbf{if}\; e'\; \mathbf{then}\; B_1\\
                & \mathbf{else}\; B_2\\
            \end{array}\right)}
$$

## Condicional

- **Ramo verdadeiro:**
  $$\frac{}{(\sigma,\; \mathbf{if}\; \mathbf{true}\; \mathbf{then}\; B_1\; \mathbf{else}\; B_2) \to (\sigma,\; B_1)}$$

## Condicional

- **Ramo falso:**

$$\frac{}{(\sigma,\; \mathbf{if}\; \mathbf{false}\; \mathbf{then}\; B_1\; \mathbf{else}\; B_2) \to (\sigma,\; B_2)}
$$

## While

- Caso em que há repetição.

$$\frac{}{(\sigma,\; \mathbf{while}\; e\; \mathbf{do}\; B) \to
(\sigma,\; \mathbf{if}\; e\; \mathbf{then}\; (B;\; \mathbf{while}\; e\; \mathbf{do}\; B))}
$$

## Exemplo

`while i < 3 do { i := i + 1 }`

$$(\sigma_0,\; \mathbf{while}\; i < 3\; \mathbf{do}\; \{i \mathbin{:=} i+1\})$$

## Exemplo

$$\xrightarrow{\text{While}}
(\sigma_0,\; \mathbf{if}\; i < 3\; \mathbf{then}\; \{i \mathbin{:=} i+1;\; \mathbf{while}\ldots\})$$

## Exemplo

$$\xrightarrow{\text{IfStep, Var, Lt}}
(\sigma_0,\; \mathbf{if}\; \mathbf{true}\; \mathbf{then}\; \{i \mathbin{:=} i+1;\; \mathbf{while}\ldots\})$$

## Exemplo

$$\xrightarrow{\text{IfTrue}}
(\sigma_0,\; i \mathbin{:=} i+1;\; \mathbf{while}\; i < 3\; \mathbf{do}\; \{i \mathbin{:=} i+1\})$$

## Exemplo

$$\xrightarrow{\text{Assign}}
([i \mapsto 1],\; \mathbf{while}\; i < 3\; \mathbf{do}\; \{i \mathbin{:=} i+1\})$$

# Semântica Big-Step

## Expressões

- Similar à semântica de Line.
  - Apenas introduz novos operadores

## Condicional

$$\frac{\sigma \vdash e \Downarrow \mathbf{true} \quad \sigma,\; B_1 \Downarrow \sigma'}
     {\sigma,\; \mathbf{if}\; e\; \mathbf{then}\; B_1\; \mathbf{else}\; B_2 \;\Downarrow\; \sigma'}
\quad\text{(IfTrue)}$$

## Condicional

$$\frac{\sigma \vdash e \Downarrow \mathbf{false} \quad \sigma,\; B_2 \Downarrow \sigma'}
     {\sigma,\; \mathbf{if}\; e\; \mathbf{then}\; B_1\; \mathbf{else}\; B_2 \;\Downarrow\; \sigma'}
\quad\text{(IfFalse)}$$

## While

- **Condição falsa (terminação):**

$$\frac{\sigma \vdash e \Downarrow \mathbf{false}}
     {\sigma,\; \mathbf{while}\; e\; \mathbf{do}\; B \;\Downarrow\; \sigma}
$$

## While

- **Condição verdadeira (iteração):**

$$\frac{\begin{array}{c}\sigma \vdash e \Downarrow \mathbf{true}\\ \sigma,\; B
\Downarrow \sigma'\\ \sigma',\; \mathbf{while}\; e\; \mathbf{do}\; B \Downarrow
\sigma'' \end{array}}{\sigma,\; \mathbf{while}\; e\; \mathbf{do}\; B
\;\Downarrow\; \sigma''}$$

## Derivação

$$\dfrac{
  \dfrac{
    \dfrac{}{\emptyset \vdash 2 \Downarrow 2}
    \quad
    \dfrac{}{\emptyset \vdash 3 \Downarrow 3}
  }{\emptyset \vdash 2 < 3 \Downarrow \mathbf{true}}
  \quad
  \dfrac{
    \dfrac{}{\emptyset \vdash 10 \Downarrow 10}
  }{\emptyset,\; x \mathbin{:=} 10 \;\Downarrow\; [x \mapsto 10]}
}{\emptyset,\; \mathbf{if}\; 2<3\; \mathbf{then}\; \{x \mathbin{:=} 10\}\; \mathbf{else}\; \{x \mathbin{:=} 20\} \;\Downarrow\; [x \mapsto 10]}$$

# Implementação em Haskell

## Condicional

```haskell
interpStmt (SIf e blk1 blk2) = do
    v <- interpExp e
    case v of
      VBool True  -> mapM_ interpStmt blk1
      VBool False -> mapM_ interpStmt blk2
      _ -> throwError $ unlines
        ["Expecting a boolean value, but found:", pretty e]
```

## Repetição

```haskell
interpStmt (SWhile e blk1) = do
    v <- interpExp e
    case v of
      VBool False -> pure ()
      VBool True  -> do
          mapM_ interpStmt blk1
          interpStmt (SWhile e blk1)
      _ -> throwError $ unlines
    ["Expecting a boolean value, but found:", pretty e]
```

# A Linguagem TImp

## Motivação

- _While_ cobre atribuição, controlo de fluxo e I/O
- Mas não permite:
  - Definir **abstrações reutilizáveis** (funções)
  - Agrupar **dados heterogêneos** (registros)

## Sintaxe Estendida

$$\begin{array}{lcl}
\mathit{prog}  &::=& \mathit{decl}^*\; s^* \\[4pt]
\mathit{decl}  &::=& \mathbf{record}\; R\; \{\, \overline{f_i \mathbin{:} \tau_i}\,\} \\
               &\mid& \mathbf{fn}\; f\,(\overline{x_i \mathbin{:} \tau_i}) \mathbin{:} \rho\; \{\, s^*\,\} \\[4pt]
\rho           &::=& \mathbf{void} \mid \tau \\[4pt]
\tau           &::=& \mathbf{int} \mid \mathbf{bool} \mid \mathbf{string} \mid R
\end{array}$$

## Novos Comandos e Expressões

$$\begin{array}{lcl}
s &::=& \cdots \mid \mathbf{var}\; x \mathbin{:} \tau \mathbin{=} e \\
  &\mid& x.f \mathbin{:=} e \mid \mathbf{return}\; e \mid \mathbf{return} \\
  &\mid& f(e_1,\ldots,e_n) \\[4pt]
e &::=& \cdots \mid e.f \mid \mathbf{new}\; R\,\{\,\overline{f_i \mathbin{=} e_i}\,\} \\
  &\mid& f(e_1,\ldots,e_n)
\end{array}$$

# Domínios Semânticos

## Valores Estendidos

O domínio de valores cresce com registros e o valor unitário:

$$v \;::=\; n \;\mid\; b \;\mid\; s \;\mid\;
  \mathbf{rec}(R,\, \{f_1 \mapsto v_1, \ldots, f_n \mapsto v_n\})
  \;\mid\; \mathbf{unit}$$

- Registros têm **semântica de valor**: toda atribuição e passagem de parâmetro
  copia o registro.

## Ambiente de Funções

Além de $\sigma$, a semântica usa um **ambiente de funções** global:

$$\Phi : \mathit{Name} \rightharpoonup (\overline{x_i},\; B)$$

- Construído uma vez a partir das declarações
- Permanece **imutável** durante a execução

## Resultado de Bloco

O comando `return` interrompe a execução normal. Modelamos isso com:

$$r \;::=\; \mathbf{normal} \;\mid\; {\uparrow}\, v$$

- $\mathbf{normal}$: terminação sem retorno
- ${\uparrow}\, v$: `return` executado, $v$ propagado ao chamador

As relações de avaliação tornam-se:

$$\sigma,\Phi \vdash s \Downarrow (\sigma', r) \qquad \sigma,\Phi \vdash B \Downarrow (\sigma', r)$$

# Semântica de Registros

## Construção de Registro

$$\frac{\sigma,\Phi \vdash e_1 \Downarrow v_1 \quad \cdots}
  {\sigma,\Phi \vdash \mathbf{new}\; R\,\{f_1\!=\!e_1,\ldots\}
  \Downarrow \mathbf{rec}(R,\,\{f_1 \mapsto v_1,\ldots\})}
$$

## Acesso a Campo

$$\frac{\sigma,\Phi \vdash e \Downarrow \mathbf{rec}(R,\mathit{flds})
  \quad f \in \mathrm{dom}(\mathit{flds})}
  {\sigma,\Phi \vdash e.f \Downarrow \mathit{flds}(f)}
\quad\text{(Field)}$$

## Atribuição de Campo

$$\frac{\sigma(x) = \mathbf{rec}(R,\mathit{flds})
  \quad \sigma,\Phi \vdash e \Downarrow v}
  {\sigma,\Phi \vdash x.f \mathbin{:=} e
    \Downarrow (\sigma[x \mapsto \mathbf{rec}(R,\,\mathit{flds}[f \mapsto v])],\;
  \mathbf{normal})}
\quad\text{(FieldAssign)}$$

- Atualiza apenas o campo $f$; copia modificada vai para $\sigma$.

# Semântica de Funções

## Propagação de Retorno

**Bloco vazio:** $$\frac{}
  {\sigma,\Phi \vdash \epsilon \Downarrow (\sigma,\; \mathbf{normal})}
\quad\text{(BlkNil)}$$

**Retorno antecipado:**
$$\frac{\sigma,\Phi \vdash s \Downarrow (\sigma',\; {\uparrow}\,v)}
  {\sigma,\Phi \vdash s\,;\,B \Downarrow (\sigma',\; {\uparrow}\,v)}
\quad\text{(BlkRet)}$$

## Continuação Normal

$$\frac{\sigma,\Phi \vdash s \Downarrow (\sigma',\; \mathbf{normal})
  \quad \sigma',\Phi \vdash B \Downarrow r}
  {\sigma,\Phi \vdash s\,;\,B \Downarrow r}
\quad\text{(BlkCons)}$$

## Comandos de Retorno

**Retorno com valor:** $$\frac{\sigma,\Phi \vdash e \Downarrow v}
  {\sigma,\Phi \vdash \mathbf{return}\; e \Downarrow (\sigma,\; {\uparrow}\,v)}
\quad\text{(RetVal)}$$

**Retorno void:** $$\frac{}
  {\sigma,\Phi \vdash \mathbf{return} \Downarrow (\sigma,\; {\uparrow}\,\mathbf{unit})}
\quad\text{(RetVoid)}$$

## Chamada como Expressão

$$\frac{\begin{array}{c}
  \Phi(f) = (\overline{x_i},\; B)\\
  \sigma,\Phi \vdash e_i \Downarrow v_i \;\;(\forall\, i)\\
  [x_1 \mapsto v_1,\ldots,x_n \mapsto v_n],\Phi \vdash B
  \Downarrow (\_,\; {\uparrow}\,v)
  \end{array}}
{\sigma,\Phi \vdash f(e_1,\ldots,e_n) \Downarrow v}
\quad\text{(CallExpr)}$$

- Corpo executado em um **novo ambiente** com apenas os parâmetros.

## Chamada como Comando

$$\frac{\begin{array}{c}
  \Phi(f) = (\overline{x_i},\; B)\\
  \sigma,\Phi \vdash e_i \Downarrow v_i \;\;(\forall\, i)\\
  [x_1 \mapsto v_1,\ldots,x_n \mapsto v_n],\Phi \vdash B \Downarrow (\_,\; \_)
\end{array}}
{\sigma,\Phi \vdash f(e_1,\ldots,e_n) \Downarrow (\sigma,\; \mathbf{normal})}
\quad\text{(CallStmt)}$$

- Ambiente de chamada devolvido **inalterado**.

# Implementação em Haskell

## Estado e Monada

```haskell
data Value
  = VInt Int | VBool Bool | VString String
  | VRecord Name (Map Field Value)
  | VUnit

data InterpState = InterpState
  { varEnv  :: Map Var Value    -- sigma
  , funcEnv :: Map Name FuncDecl  -- Phi
  }

type InterpM a = StateT InterpState (ExceptT String IO) a
```

## Execução de Bloco

```haskell
execBlock :: [Stmt] -> InterpM (Maybe Value)
execBlock []     = pure Nothing           -- BlkNil
execBlock (s:ss) = do
  r <- execStmt s
  case r of
    Just _  -> pure r                     -- BlkRet: propagate
    Nothing -> execBlock ss               -- BlkCons: continue
```

## Criação de Registro

```haskell
evalExp (ENew rname initFields) = do
  vals <- mapM (\(f, e) -> (f,) <$> evalExp e) initFields
  pure (VRecord rname (Map.fromList vals))
```

## Acesso e Atribuição de Campo

```haskell
evalExp (EField e f) = do
  v <- evalExp e
  case v of
    VRecord _ fields ->
      case Map.lookup f fields of
        Just val -> pure val
        Nothing  -> throwError ("Record has no field: " ++ f)
    _ -> throwError "Field access on non-record value"
```

## Atribuição de Campo

```haskell
execStmt (SFieldAssign v f e) = do
  rval <- lookupVar v
  newVal <- evalExp e
  case rval of
    VRecord name fields ->
      let fields' = Map.insert f newVal fields
      in  modify (\st -> st
            { varEnv = Map.insert v (VRecord name fields') (varEnv st) })
    _ -> throwError (v ++ " is not a record")
  pure Nothing
```

## Retorno e Chamada de Função

```haskell
execStmt (SReturn Nothing)  = pure (Just VUnit)   -- RetVoid
execStmt (SReturn (Just e)) = Just <$> evalExp e  -- RetVal

callFunc :: Name -> [Value] -> InterpM Value
callFunc fname argVals = do
  fenv <- gets funcEnv
  case Map.lookup fname fenv of
    Nothing -> throwError ("Undefined function: " ++ fname)
    Just (FuncDecl _ params _ body) -> do
      let bindings = zip [v | Param v _ <- params] argVals
      withFreshEnv bindings $ do
        r <- execBlock body
        pure (fromMaybe VUnit r)
```

## Ambiente Fresco

```haskell
withFreshEnv :: [(Var, Value)] -> InterpM a -> InterpM a
withFreshEnv bindings m = do
  saved <- gets varEnv
  modify (\st -> st { varEnv = Map.fromList bindings })
  r <- m
  modify (\st -> st { varEnv = saved })
  pure r
```

- Salva o ambiente corrente, inicializa apenas com os parâmetros, restaura ao
  terminar.

# Conclusão

## Conclusão

- **Condicional**: regras (IfTrue) e (IfFalse) selecionam o ramo pela condição.

- **While**: (WhileFalse) termina; (WhileTrue) executa o corpo e recomeça.

## Conclusão

- **Registros**: $\mathbf{rec}(R, \mathit{flds})$ com semântica de valor; regras
  (New), (Field), (FieldAssign).

## Conclusão

- **Funções**: resultado de bloco $r \in \{\mathbf{normal}, {\uparrow}\,v\}$
  modela `return`; (CallExpr) executa em ambiente fresco.

## Conclusão

- A especificação formal guia diretamente a implementação em Haskell.
