---
title: "Semântica Operacional para Estado"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a semântica operacional para uma linguagem imperativa simples.

- Apresentar a implementação do interpretador desta linguagem.

# A Linguagem Line

## Motivação: Expressões Puras Não Bastam

- No capítulo anterior: expressões **puras** sem variáveis
- O valor de uma expressão dependia apenas da sua estrutura sintática

# A Linguagem Line

## Motivação: Expressões Puras Não Bastam

- Programas reais manipulam **estado**: valores armazenados em variáveis
- Precisamos estender a semântica com um componente de estado

## Sintaxe da Linguagem Line

$$\begin{array}{lcl}
\mathit{prog} &::=& s^* \\[4pt]
s &::=& x \mathbin{:=} e \\
  &\mid& \mathbf{read}\; x \\
  &\mid& \mathbf{print}\; e \\[4pt]
e &::=& n \mid x \mid e_1 + e_2 \mid e_1 * e_2
\end{array}$$

## Tipos em Haskell

```haskell
data Line = Line [Stmt]

data Stmt
  = SAssign Var Exp
  | SRead   Var
  | SPrint  Exp
```

## Tipos em Haskell

```haskell
data Exp
  = EInt Int
  | EVar Var
  | Exp :+: Exp
  | Exp :*: Exp

type Var = String
```

# Ambientes

## Definição de Ambiente

Um **ambiente** $\sigma : \mathit{Var} \rightharpoonup \mathbb{Z}$ é uma função
parcial que mapeia nomes de variáveis para inteiros.

Em Haskell: `type Env = Map String Int`

## Notação

- $\sigma(x)$: valor de $x$ em $\sigma$ (supondo $x \in \mathrm{dom}(\sigma)$)
- $\sigma[x \mapsto n]$: ambiente obtido atualizando $x$ com $n$
- $\emptyset$: ambiente vazio (sem variáveis definidas)

## Por que Precisamos de Ambientes?

- Expressões agora podem conter **variáveis**: `x * 4`
- O valor de `x` só é conhecido durante a execução

## Por que Precisamos de Ambientes?

- O ambiente $\sigma$ registra o estado da memória em cada instante
- Comandos de atribuição **modificam** o ambiente:
  $\sigma \to \sigma[x \mapsto n]$

## Por que Precisamos de Ambientes?

- Expressões apenas **consultam** o ambiente, sem modificá-lo

# Semântica Small-Step

## Expressões com Variáveis

- A configuração de uma expressão é um par $(\sigma, e)$; a redução é
  $(\sigma, e) \to (\sigma, e')$.

## Expressões com Variáveis

- **Variável:**

$$\frac{x \in \mathrm{dom}(\sigma)}{(\sigma,\, x) \to (\sigma,\, \sigma(x))} \quad\text{(Var)}$$

## Expressões com Variáveis

- Uma variável é substituída pelo seu valor corrente.
- Se $x \notin \mathrm{dom}(\sigma)$: **erro** de variável não inicializada.

## Regras para Expressões

$$\frac{(\sigma, e_1) \to (\sigma, e_1')}{(\sigma,\, e_1 + e_2) \to (\sigma,\, e_1' + e_2)} \quad\text{(AddL)}
$$

## Regras para Expressões

$$
\frac{(\sigma, e_2) \to (\sigma, e_2')}{(\sigma,\, n_1 + e_2) \to (\sigma,\, n_1 + e_2')} \quad\text{(AddR)}$$

## Regras para Expressões

$$\frac{}{(\sigma,\, n_1 + n_2) \to (\sigma,\, n_1 \mathbin{\hat{+}} n_2)} \quad\text{(Add)}$$

- Note que as expressões **não modificam** $\sigma$
  - São puras no sentido de que apenas consultam o ambiente.

## Regras para Comandos

A configuração de um comando é $(\sigma, s) \to (\sigma', s')$, onde $s'$ é o
resíduo após a redução.

## Regras para Comandos

- **Atribuição (avalia primeiro):**
  $$\frac{(\sigma, e) \to (\sigma, e')}{(\sigma,\; x \mathbin{:=} e) \to (\sigma,\; x \mathbin{:=} e')} \quad\text{(AssignStep)}$$

## Regras para Comandos

- **Atribuição (valor final):**
  $$\frac{}{(\sigma,\; x \mathbin{:=} n) \to (\sigma[x \mapsto n],\; \mathbf{skip})} \quad\text{(Assign)}$$

## Impressão

- **Impressão (avalia primeiro):**
  $$\frac{(\sigma, e) \to (\sigma, e')}{(\sigma,\; \mathbf{print}\; e) \to (\sigma,\; \mathbf{print}\; e')} \quad\text{(PrintStep)}$$

## Impressão

- **Impressão (valor final):**
  $$\frac{}{(\sigma,\; \mathbf{print}\; n) \to (\sigma,\; \mathbf{skip})} \quad\text{(Print) [emite } n\text{]}$$

## Sequência

- Skip à esquerda

$$\frac{}{(\sigma,\; \mathbf{skip};\, s^*) \to (\sigma,\; s^*)} \quad\text{(SeqSkip)}$$

## Sequência

- Caso geral:

$$\frac{(\sigma, s) \to (\sigma', s')}{(\sigma,\; s;\, s_1) \to (\sigma',\; s';\,s_1)} \quad\text{(Seq)}$$

## Exemplo

- Small-Step: `x := 2 + 3; print x * 4`
  - Partindo do ambiente vazio $\emptyset$:

$$(\emptyset,\; x \mathbin{:=} 2+3;\; \mathbf{print}\; x*4)$$

## Exemplo

- Small-Step: `x := 2 + 3; print x * 4`
  - Partindo do ambiente vazio $\emptyset$:

$$\xrightarrow{\text{Seq, Add}} (\emptyset,\; x \mathbin{:=} 5;\; \mathbf{print}\; x*4)$$

$$\xrightarrow{\text{Assign}} ([x \mapsto 5],\; \mathbf{skip};\; \mathbf{print}\; x*4)$$

## Exemplo

- Small-Step: `x := 2 + 3; print x * 4`
  - Partindo do ambiente vazio $\emptyset$:

$$\xrightarrow{\text{SeqSkip}} ([x \mapsto 5],\; \mathbf{print}\; x*4)$$

$$\xrightarrow{\text{PrintStep, Var}} ([x \mapsto 5],\; \mathbf{print}\; 5*4)$$

## Exemplo

- Small-Step: `x := 2 + 3; print x * 4`
  - Partindo do ambiente vazio $\emptyset$:

$$\xrightarrow{\text{PrintStep, Mul}} ([x \mapsto 5],\; \mathbf{print}\; 20)$$

$$\xrightarrow{\text{Print}} ([x \mapsto 5],\; \mathbf{skip}) \quad\text{[emite 20]}$$

# Semântica Big-Step

## Expressões

- Nova regra: variáveis.

$$\frac{x \in \mathrm{dom}(\sigma)}{\sigma \vdash x \Downarrow \sigma(x)} \quad\text{(Var)}$$

## Comandos

- A relação $\sigma, s \Downarrow \sigma'$ significa "executar $s$ no ambiente
  $\sigma$ produz $\sigma'$".

$$\frac{\sigma \vdash e \Downarrow n}
     {\sigma,\; x \mathbin{:=} e \;\Downarrow\; \sigma[x \mapsto n]}
\quad\text{(Assign)}
$$

## Comandos

$$
\frac{\sigma \vdash e \Downarrow n}
     {\sigma,\; \mathbf{print}\; e \;\Downarrow\; \sigma}
\quad\text{(Print) [emite } n\text{]}$$

## Comandos

$$\frac{}{\sigma,\; \mathbf{read}\; x \;\Downarrow\; \sigma[x \mapsto n]}
\quad\text{(Read) [} n\text{ lido da entrada]}$$

## Comandos

$$\frac{}{\sigma,\; \epsilon \;\Downarrow\; \sigma}
\quad\text{(SeqNil)}
$$

## Comandos

$$
\frac{\sigma,\; s \;\Downarrow\; \sigma' \quad \sigma',\; s^* \;\Downarrow\; \sigma''}
     {\sigma,\; s;\, s^* \;\Downarrow\; \sigma''}
\quad\text{(SeqCons)}$$

## Derivação: `x := 2 + 3`

$$\dfrac{
  \dfrac{
    \dfrac{}{\emptyset \vdash 2 \Downarrow 2}
    \quad
    \dfrac{}{\emptyset \vdash 3 \Downarrow 3}
  }{\emptyset \vdash 2 + 3 \Downarrow 5}
}{\emptyset,\; x \mathbin{:=} 2 + 3 \;\Downarrow\; [x \mapsto 5]}$$

## Derivação: `x := 2+3; print x*4`

- Resolução na lousa.

# Implementação em Haskell

## Mônada

- A semântica big-step dita que cada comando recebe e produz um ambiente.

```haskell
type Env    = Map String Int
type Interp a = ExceptT String (StateT Env IO) a
```

## Mônada

- A pilha de mônadas combina:
  - `StateT Env`: o ambiente $\sigma$ implícito — lido com `get`, modificado com
    `modify`
  - `ExceptT String`: tratamento de erros (variável não definida)
  - `IO`: efeitos de I/O para `read` e `print`

## Expressões

```haskell
interpExp :: Exp -> Interp Int
interpExp (EInt n)    = pure n
interpExp (EVar v)    = askVar v
interpExp (e1 :+: e2) = (+) <$> interpExp e1 <*> interpExp e2
interpExp (e1 :*: e2) = (*) <$> interpExp e1 <*> interpExp e2
```

## Variáveis

```haskell
askVar :: String -> Interp Int
askVar s = do
    env <- get
    case Map.lookup s env of
      Nothing  -> throwError $ unwords ["Undefined variable:", s]
      Just val -> pure val
```

## Comandos

```haskell
interpStmt :: Stmt -> Interp ()
interpStmt (SAssign v e) = do
    val <- interpExp e
    modify (Map.insert v val)
```

## Comandos

```haskell
interpStmt (SPrint e) = do
    val <- interpExp e
    liftIO $ print val
```

## Comandos

```haskell
interpStmt (SRead v) = do
    str <- liftIO getLine
    modify (Map.insert v (read str))

interpProgram :: Line -> Interp ()
interpProgram (Line ss) = mapM_ interpStmt ss
```

# Conclusão

## Conclusão

- Apresentamos a semântica operacional de uma linguagem imperativa simples.
  - Foco: representação do estado.
  - Small e big step
- Apresentamos a implementação em Haskell
