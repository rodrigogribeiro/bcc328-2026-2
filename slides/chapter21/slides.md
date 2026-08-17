---
title: "O λ-cálculo"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a sintaxe e as semânticas big-step e small-step call-by-value do
  $\lambda$-cálculo não tipado.

## Objetivos

- Estender o $\lambda$-cálculo com booleanos e um sistema de tipos simples
  (STLC+Bool) e demonstrar as propriedades de progresso e preservação.

## Objetivos

- Apresentar a closure conversion como a técnica de compilação de funções de
  primeira classe para linguagens de baixo nível.

# Introdução

## $\lambda$-cálculo

- Formulado por Alonzo Church nos anos 1930
- A linguagem de programação mais simples que captura a essência da computação
  por funções
- **Turing-completo**: qualquer função computável pode ser expressa nele
- Base de toda linguagem funcional moderna: Haskell, ML, Lisp

## $\lambda$-cálculo

Dois sistemas neste capítulo:

1. **$\lambda$-cálculo não tipado**: sintaxe, big-step e small-step CBV
2. **STLC+Bool**: tipos simples, progresso e preservação

# O $\lambda$-cálculo Não Tipado

## Sintaxe

$$\begin{array}{rcll}
t & ::= & x & \text{variável} \\
  & \mid & \lambda x.\, t & \text{abstração (função anônima)} \\
  & \mid & t\, t & \text{aplicação (chamada de função)}
\end{array}$$

## Sintaxe

Convenções de precedência:

- **Aplicação** associa à esquerda: $t_1\, t_2\, t_3 = (t_1\, t_2)\, t_3$
- **Corpo da abstração** estende o máximo à direita:
  $\lambda x.\, t_1\, t_2 = \lambda x.\,(t_1\, t_2)$
- **Múltiplos parâmetros**: $\lambda x\, y.\, t = \lambda x.\,\lambda y.\, t$

## Valores

**Valores**:

$$v ::= \lambda x.\, t$$

- Só abstrações são valores
  - Variáveis e aplicações precisam ser reduzidas.

## Variáveis livres

- **Variável livre**: $x$ fora do escopo de $\lambda x$
  - $\mathrm{FV}(\lambda x.\, x\, y) = \{y\}$
  - Um termo sem variáveis livres é **fechado**.

## Semântica Big-Step

- A relação $t \Downarrow v$: "o termo $t$ avalia ao valor $v$"

$$\frac{}{\lambda x.\, t\; \Downarrow\; \lambda x.\, t} \quad\text{(B-Lam)}$$

$$\frac{t_1 \Downarrow \lambda x.\, t \qquad t_2 \Downarrow v_2 \qquad t[x \mapsto v_2] \Downarrow v}{t_1\, t_2\; \Downarrow\; v} \quad\text{(B-App)}$$

## Substituição

- $t[x \mapsto v]$: substituição de $x$ por $v$ em $t$:

$$\begin{array}{l}
x[x \mapsto v] = v \\
y[x \mapsto v] = y \quad (y \neq x) \\
(\lambda x.\, t)[x \mapsto v] = \lambda x.\, t \\
(\lambda y.\, t)[x \mapsto v] = \lambda y.\,(t[x \mapsto v]) \quad (y \neq x,\; y \notin \mathrm{fv}(v)) \\
(t_1\, t_2)[x \mapsto v] = (t_1[x \mapsto v])\,(t_2[x \mapsto v])
\end{array}$$

## Semântica Small-Step

- **Regra de computação**:

$$\frac{}{(\lambda x.\, t_1)\, v_2 \to t_1[x \mapsto v_2]} \quad\text{(E-Beta)}$$

## Semântica Small-Step

- **Regras de congruência**:

$$\begin{array}{c}
   \dfrac{t_1 \to t_1'}{t_1\, t_2 \to t_1'\, t_2} \\ \\
   \dfrac{t_2 \to t_2'}{v_1\, t_2 \to v_1\, t_2'}
\end{array}$$

# $\lambda$-cálculo tipado simples

## Sintaxe Estendida

- **Tipos:**

$$T ::= \mathbf{Bool} \mid T \to T$$

## Sintaxe Estendida

- **Termos** (abstrações carregam anotação de tipo):

$$t ::= x \mid \lambda x {:} T.\, t \mid t\, t \mid \mathbf{true} \mid \mathbf{false} \mid \mathbf{if}\, t\, \mathbf{then}\, t\, \mathbf{else}\, t$$

## Sintaxe Estendida

- **Valores:**

$$v ::= \lambda x {:} T.\, t \mid \mathbf{true} \mid \mathbf{false}$$

## Sistema de Tipos

$$\begin{array}{c}
  \dfrac{}{\Gamma \vdash \mathbf{true} : \mathbf{Bool}} \\ \\
  \dfrac{}{\Gamma \vdash \mathbf{false} : \mathbf{Bool}}
\end{array}$$

## Sistema de Tipos

$$
\begin{array}{c}
   \dfrac{x : T \in \Gamma}{\Gamma \vdash x : T} \\ \\
   \dfrac{\Gamma,\, x : T_1 \vdash t : T_2}
         {\Gamma \vdash \lambda x {:} T_1.\, t : T_1 \to T_2}
\end{array}$$

## Sistema de Tipos

$$\begin{array}{c}
   \dfrac{\Gamma \vdash t_1 : T_1 \to T_2 \quad \Gamma \vdash t_2 : T_1}
         {\Gamma \vdash t_1\, t_2 : T_2}\\ \\
\dfrac{\begin{array}{c}\Gamma \vdash t_1 : \mathbf{Bool} \\
          \Gamma \vdash t_2 : T \\ \Gamma \vdash t_3 : T
       \end{array}}{\Gamma \vdash \mathbf{if}\ t_1\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 : T}
\end{array}
$$

## Propriedades

- **Lema das Formas Canônicas**: se $v$ é valor com $\vdash v : T$:

- $T = \mathbf{Bool} \Rightarrow v \in \{\mathbf{true}, \mathbf{false}\}$
- $T = T_1 \to T_2 \Rightarrow v = \lambda x {:} T_1.\, t$

## Propriedades

- **Teorema (Progresso)**: se $\vdash t : T$ então $t$ é valor ou
  $\exists t'.\; t \to t'$.

  - Termos bem tipados **nunca ficam presos**
  - Prova: indução estrutural sobre $\vdash t : T$; usa Formas Canônicas nos
    subcasos de valor

## Propriedades

- **Teorema (Preservação)**: se $\Gamma \vdash t : T$ e $t \to t'$ então
  $\Gamma \vdash t' : T$.
  - O tipo é **invariante pela redução**
  - Prova: indução sobre $t \to t'$; usa o **Lema da Substituição**

# Closure Conversion

## Motivação

- $\lambda$-cálculo: funções são **valores de primeira classe**
- Linguagens de baixo nível (C, IRT):
  - Funções são procedimentos com endereço estático: sem variáveis livres

## Motivação

- **Closure conversion**: resolve esse gap separando cada abstração em:
  - **Código promovido** (_lifted_): função de nível superior, sem variáveis
    livres
  - **Registro de closure**: tag do código + valores das variáveis capturadas

## Variáveis Livres

$$\begin{array}{rcl}
\mathrm{FV}(x) &=& \{x\} \\[4pt]
\mathrm{FV}(\lambda x.\, t) &=& \mathrm{FV}(t) \setminus \{x\} \\[4pt]
\mathrm{FV}(t_1\, t_2) &=& \mathrm{FV}(t_1) \cup \mathrm{FV}(t_2)
\end{array}$$

## Variáveis Livres

- $t$ é **fechado** quando $\mathrm{FV}(t) = \emptyset$
- Exemplo:
  - $\mathrm{FV}(\lambda x.\,\lambda y.\, x) = \emptyset$
  - $\mathrm{FV}(\lambda y.\, x) = \{x\}$
- O termo de entrada da closure conversion deve ser fechado

## Termos Anotados

- Cada abstração recebe
  - Um **identificador único** $k$
  - Lista $\overline{y}$ das variáveis que captura:

$$\hat{t} \;::=\; \hat{x}
  \;\mid\; \hat{t}\; \hat{t}
  \;\mid\; \lambda^k\, x\,[\overline{y}]\,.\;\hat{t}
  \qquad\text{onde }\overline{y} = \mathrm{FV}(\hat{t}) \setminus \{x\}$$

## Termos Anotados

- Função $\mathit{ann}$ percorre em **pós-ordem**:

$$\begin{array}{rcl}
\mathit{ann}(x) &=& \hat{x} \\[2pt]
\mathit{ann}(t_1\, t_2) &=& \mathit{ann}(t_1)\;\mathit{ann}(t_2) \\[2pt]
\mathit{ann}(\lambda x.\, t) &=& \lambda^k\, x\,[\overline{y}]\,.\;\hat{t}
  \quad (k \text{ novo},\; \hat{t} = \mathit{ann}(t))
\end{array}$$

## Tipo Closure

- Seja $N$ = num. máx. de variáveis capturadas no programa.

$$\mathbf{record}\;\mathtt{Closure}\;\left\{
  \begin{array}{c}
     \mathtt{tag} : \mathbf{int};\\
      \mathtt{f}_0 : \mathtt{T}_0;\\
      \ldots;\\
      \mathtt{f}_{N-1} : \mathtt{T}_{n-1}\\
   \end{array}\right\}$$

## Tipo Closure

- `tag`: identifica qual lambda a closure representa (o identificador $k$)
- `f_i`: valor da $i$-ésima variável capturada
- Campos não usados por uma closure particular **não são inicializados**

## A Tradução $\lbrack\cdot\rbrack_\sigma$

Converte termos anotados em TImp, dado
$\sigma : \mathit{Var} \rightharpoonup \mathit{Exp}$:

$$\lbrack \hat{x} \rbrack_\sigma = \begin{cases} \sigma(x) & x \in \mathrm{dom}(\sigma) \\ x & \text{caso contrário} \end{cases}$$

## A Tradução $\lbrack\cdot\rbrack_\sigma$

$$\lbrack \hat{t}_1\; \hat{t}_2 \rbrack_\sigma = \mathtt{apply}\bigl(\lbrack \hat{t}_1 \rbrack_\sigma,\; \lbrack \hat{t}_2 \rbrack_\sigma\bigr)$$

## A Tradução $\lbrack\cdot\rbrack_\sigma$

$$\begin{array}{l}
   \lbrack \lambda^k\, x\,[y_1,\ldots,y_j]\,.\;\hat{t} \rbrack_\sigma =\\
   \:\:\:\:\:\mathbf{new}\;\mathtt{Closure}\;\{\mathtt{tag}=k,\;\mathtt{f}_0=\sigma(y_1),\;\ldots\}
\end{array}$$

- O corpo $\hat{t}$ **não** é compilado aqui: ele é compilado nas funções
  promovidas.

## Funções Promovidas

- Para cada $\lambda^k\, x\,[y_1,\ldots,y_j]\,.\;\hat{t}$ coletado do programa,
  gera-se:

$$\mathbf{fn}\ \mathtt{lam}\_k\ (\mathtt{\_env},\ \mathtt{\_arg})\{\ \mathbf{return}\ \lbrack \hat{t} \rbrack_{\sigma_k}\ \}$$

## Funções Promovidas

- O **ambiente de substituição** $\sigma_k$ é:

$$\sigma_k = [y_1 \mapsto \mathtt{\_env.f}_0,\ \ldots,\ y_j \mapsto \mathtt{\_env.f}_{j-1},\ x \mapsto \mathtt{\_arg}]$$

- Variáveis capturadas são recuperadas dos campos de `_env`
- O parâmetro formal $x$ é associado a `_arg`

## Despacho Dinâmico

- Como `tag` determina qual função promovida chamar, gera-se uma função `apply`:

```
fn apply(_f: Closure, _arg: Closure) : Closure {
  if _f.tag = k₁ then { return lam_k₁(_f, _arg) }
  else if _f.tag = k₂ then { return lam_k₂(_f, _arg) }
  ...
  else { return new Closure { tag = -1 } }  -- inalcançável
}
```

- O ramo `else` final é inalcançável para programas bem formados.

## Exemplo

- Combinador K aplicado à identidade:

$$(\lambda f.\,\lambda x.\, f)\;(\lambda y.\, y)$$

- Resultado esperado pela semântica: $\lambda x.\, f$ com $f = \lambda y.\, y$

## Exemplo

| Abstração                              | $\mathrm{FV}$ capturado | tag |
| -------------------------------------- | ----------------------- | --- |
| $\lambda y.\, y$                       | $\emptyset$             | 0   |
| $\lambda x.\, f$                       | $\{f\}$                 | 1   |
| $\lambda f.\,(\lambda^1 x\,[f]\ldots)$ | $\emptyset$             | 2   |

## Exemplo

- Termo anotado:

$$\bigl(\lambda^2 f\,[]\,.\;\lambda^1 x\,[f]\,.\;\hat{f}\bigr)\;\bigl(\lambda^0 y\,[]\,.\;\hat{y}\bigr)$$

## Exemplo

- $N = 1$ (máximo 1 variável capturada) $\Rightarrow$
  `record Closure { tag: int; f0: Closure; }`

## Exemplo

Com $\sigma_0 = [y \mapsto \mathtt{\_arg}]$,
$\sigma_1 = [f \mapsto \mathtt{\_env.f_0},\, x \mapsto \mathtt{\_arg}]$,
$\sigma_2 = [f \mapsto \mathtt{\_arg}]$:

## Exemplo

```
fn lam_0(_env: Closure, _arg: Closure) : Closure {
  return _arg; -- [[ŷ]]_σ₀ = _arg
}
fn lam_1(_env: Closure, _arg: Closure) : Closure {
  return _env.f0; -- [[f̂]]_σ₁ = _env.f0
}
fn lam_2(_env: Closure, _arg: Closure) : Closure {
  return new Closure { tag=1, f0=_arg }; 
  -- [[λ¹x[f].f̂]]_σ₂
}
```

## Exemplo

- Função `apply` gerada para os tags 0, 1, 2:

```
fn apply(_f: Closure, _arg: Closure) : Closure {
  if _f.tag = 0 then { return lam_0(_f, _arg) }
  else if _f.tag = 1 then { return lam_1(_f, _arg) }
  else if _f.tag = 2 then { return lam_2(_f, _arg) }
  else { return new Closure { tag = -1 } }  -- inalcançável
}
```

## Exemplo

A aplicação de nível superior
$\lbrack(\lambda^2 f[]\ldots)(\lambda^0 y[]\ldots)\rbrack_\emptyset$:

```
var _res : Closure =
  apply(new Closure {tag=2}, new Closure {tag=0});
print _res;
```

## Exemplo

$$\mathtt{apply}(\{tag=2\},\ \{tag=0\})$$

$$\downarrow\ tag=2 \Rightarrow \mathtt{lam\_2}(\{tag=2\},\ \{tag=0\})$$

$$= \mathbf{new}\ \mathtt{Closure}\ \{tag=1,\ f_0=\{tag=0\}\}$$

Resultado impresso:

```
Closure { tag = 1; f0 = Closure { tag = 0; }; }
```

$\equiv$ closure para $\lambda x.\, f$ com $f$ capturado como $\lambda y.\, y$

# Implementação em Haskell

## Sintaxe e Ambientes

```haskell
type Name = String

data Term
  = Var Name
  | Lam Name Term
  | App Term Term
```

## Sintaxe e Ambientes

- Valores como **closures**: pares (abstração, ambiente léxico):
  - Realiza escopo léxico sem substituição textual
  - Evita necessidade de $\alpha$-conversão

```haskell
data Value = VClosure Name Term Env
type Env = Map Name Value
```

## Interpretador

```haskell
eval :: Env -> Term -> EvalM Value
eval env (Lam x body) =
  return (VClosure x body env)          -- (B-Lam)
eval env (Var x) =
  case Map.lookup x env of
    Just v  -> return v
    Nothing -> throwError $ "Unbound variable: " ++ x
eval env (App t1 t2) = do
    tick                                -- limite de passos
    v1 <- eval env t1                   -- avalia função
    v2 <- eval env t2                   -- avalia argumento
    case v1 of
      VClosure x body closEnv ->
        eval (Map.insert x v2 closEnv) body
```

# Closure Conversion em Haskell

## Termos Anotados

```haskell
type LamId = Int

data Ann
  = AVar Name
  | ALam LamId Name [Name] Ann  -- k, x, [y1,...,yj], corpo
  | AApp Ann Ann
```

- `ALam k x fvs body` corresponde a $\lambda^k\,x\,[\overline{y}].\,\hat{t}$
- `fvs` é a lista $\overline{y}$ já calculada (sem percorrer o corpo de novo)

## Anotação

```haskell
type AnnM = State Int

annotate :: Term -> AnnM Ann
annotate (Var x)   = return (AVar x)
annotate (App f a) = AApp <$> annotate f <*> annotate a
annotate (Lam x t) = do
  body <- annotate t
  k    <- freshId         -- ID único crescente (pós-ordem)
  let fvs = Set.toList (Set.delete x (freeVarsAnn body))
  return (ALam k x fvs body)
```

## Anotação

```haskell
freeVarsAnn :: Ann -> Set Name
freeVarsAnn (AVar x) = Set.singleton x
freeVarsAnn (AApp f a) = freeVarsAnn f `Set.union` freeVarsAnn a
freeVarsAnn (ALam _ _ fvs _) = Set.fromList fvs
```

## A Tradução $\lbrack\cdot\rbrack_\sigma$

```haskell
type Subst = [(Name, Exp)]

compileExprS :: Subst -> Ann -> Exp
compileExprS s (AVar x) =
  case lookup x s of { Just e -> e; Nothing -> EVar x }
compileExprS s (AApp f a) =
  ECall "apply" [compileExprS s f, compileExprS s a]
compileExprS s (ALam k _ fvs _) =
  ENew "Closure" $
    ("tag", EInt k) :
    [("f" ++ show i, compileExprS s (AVar v)) | (i,v) <- zip [0..] fvs]
```

- `ALam`: cria o registro de closure com `tag=k` e os campos `f_i` capturados
- O corpo `body` **não** é compilado aqui

## Funções Promovidas

```haskell
genLiftedFunc :: (LamId, Name, [Name], Ann) -> FuncDecl
genLiftedFunc (k, x, fvs, body) =
  FuncDecl ("lam_" ++ show k)
    [Param "_env" (TRecord "Closure"),
     Param "_arg" (TRecord "Closure")]
    (RTTy (TRecord "Closure"))
    [SReturn (Just (compileExprS subst body))]
  where
    subst = [(v, EField (EVar "_env") ("f" ++ show i))
             | (i, v) <- zip [0..] fvs]
            ++ [(x, EVar "_arg")]
```

- `subst` implementa $\sigma_k$: variáveis capturadas → `_env.f_i`, parâmetro →
  `_arg`

## Despacho Dinâmico

```haskell
genApplyFunc :: [LamId] -> FuncDecl
genApplyFunc lids =
  FuncDecl "apply"
    [Param "_f" (TRecord "Closure"),
     Param "_arg" (TRecord "Closure")]
    (RTTy (TRecord "Closure"))
    [buildDispatch lids]
  where
    buildDispatch [] =
      SReturn (Just (ENew "Closure" [("tag", EInt (-1))]))
    buildDispatch (k:ks) =
      SIf (EField (EVar "_f") "tag" :=: EInt k)
          [SReturn (Just (ECall ("lam_" ++ show k) [EVar "_f", EVar "_arg"]))]
          [buildDispatch ks]
```

## Ponto de Entrada

```haskell
lambdaToTImp :: Term -> TImp
lambdaToTImp term = TImp decls mainBlock
  where
    ann     = evalState (annotate term) 0
    lambdas = collectLambdas ann
    maxFVs  = maximum (0 : [length fvs | (_,_,fvs,_) <- lambdas])
    lids    = [k | (k,_,_,_) <- lambdas]
    decls   = DRecord (genClosureRecord maxFVs)
              : map (DFunc . genLiftedFunc) lambdas
             ++ [DFunc (genApplyFunc lids)]
    mainBlock =
      [ SDecl "_res" (TRecord "Closure") (compileExprS [] ann)
      , SPrint (EVar "_res") ]
```

# Conclusão

## Conclusão

- Apresentamos a sintaxe, semântica e sistema de tipos para o $\lambda$-cálculo.
- Apresentamos o closure conversion para compilar linguagens funcionais.
  - Lambdas compilam para funções promovidas + registros de closure.
