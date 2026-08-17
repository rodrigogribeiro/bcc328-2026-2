---
title: "Análise Sintática LL(1)"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar os conceitos de conjuntos first e follow.

- Apresentar o algoritmo LL(1): primeiro baseado em tabela.

# O Algoritmo LL(1)

## O Nome LL(1)

- **L** (primeiro): lê a entrada da **esquerda para a direita**
  (_Left-to-right_)
- **L** (segundo): produz uma **derivação mais à esquerda** (_Leftmost
  derivation_)
- **1**: usa apenas **1 símbolo de lookahead** para decidir qual produção
  aplicar

## A Ideia Central

- Substitui a **recursão** por um **algoritmo dirigido por tabela**
- Tabela de parsing $M[A, a]$: dado não-terminal $A$ e token $a$, qual produção
  aplicar?

## A Ideia Central

- O analisador mantém uma **pilha** de símbolos (o que ainda falta reconhecer)
- Cada passo: consulta $M[\text{topo da pilha}, \text{token atual}]$

## O Algoritmo LL(1)

**Inicialização**: pilha $\leftarrow [S, \$]$, onde $S$ é o símbolo inicial

**Repita**:

- Seja $X$ o topo da pilha e $a$ o token corrente
- Se $X = \$$ e $a = \$$: **aceitar**

## O Algoritmo LL(1)

- Se $X$ é terminal $t$: se $t = a$, desempilha e avança; senão **erro**
- Se $X$ é não-terminal $A$: consulta $M[A, a]$
  - Se $M[A, a] = A \to \alpha$: substitui $A$ na pilha por $\alpha$ (da direita
    para esquerda)
  - Se $M[A, a] = vazio$ erro: **erro sintático**

# Exemplo: Análise de `n + n`

## Gramática de Expressões (LL(1))

$$\begin{array}{lcl}
E  &\to& T\; E' \\
E' &\to& +\; T\; E' \mid \lambda \\
T  &\to& F\; T' \\
T' &\to& *\; F\; T' \mid \lambda \\
F  &\to& (\; E\; ) \mid \mathbf{n}
\end{array}$$

## Trace Completo da Análise de `n + n`

| Pilha           | Entrada       | Ação                            |
| --------------- | ------------- | ------------------------------- |
| $E\;\$$         | $n\;+\;n\;\$$ | $M[E,n]$: aplicar $E \to T\;E'$ |
| $T\;E'\;\$$     | $n\;+\;n\;\$$ | $M[T,n]$: aplicar $T \to F\;T'$ |
| $F\;T'\;E'\;\$$ | $n\;+\;n\;\$$ | $M[F,n]$: aplicar $F \to n$     |

## Trace Completo da Análise de `n + n`

| Pilha           | Entrada       | Ação                                 |
| --------------- | ------------- | ------------------------------------ |
| $n\;T'\;E'\;\$$ | $n\;+\;n\;\$$ | Casar: consumir $n$                  |
| $T'\;E'\;\$$    | $+\;n\;\$$    | $M[T',+]$: aplicar $T' \to \lambda$  |
| $E'\;\$$        | $+\;n\;\$$    | $M[E',+]$: aplicar $E' \to +\;T\;E'$ |

## Trace Completo da Análise de `n + n`

| Pilha           | Entrada    | Ação                            |
| --------------- | ---------- | ------------------------------- |
| $+\;T\;E'\;\$$  | $+\;n\;\$$ | Casar: consumir $+$             |
| $T\;E'\;\$$     | $n\;\$$    | $M[T,n]$: aplicar $T \to F\;T'$ |
| $F\;T'\;E'\;\$$ | $n\;\$$    | $M[F,n]$: aplicar $F \to n$     |

## Trace Completo da Análise de `n + n`

| Pilha           | Entrada | Ação                                 |
| --------------- | ------- | ------------------------------------ |
| $n\;T'\;E'\;\$$ | $n\;\$$ | Casar: consumir $n$                  |
| $T'\;E'\;\$$    | $\$$    | $M[T',\$]$: aplicar $T' \to \lambda$ |
| $E'\;\$$        | $\$$    | $M[E',\$]$: aplicar $E' \to \lambda$ |
| $\$$            | $\$$    | **Aceitar**                          |

# Construção da Tabela LL(1)

## Conceito: Anulável

Um não-terminal $A$ é **anulável** se $A \Rightarrow^* \lambda$.

Uma sequência $X_1\, X_2\, \cdots\, X_n$ é anulável se **todos** os $X_i$ são
anuláveis.

## Conceito: Anulável

Casos base:

- Todo terminal não é anulável
- $A$ anulável se tem produção $A \to \lambda$
- Calculado iterativamente até ponto fixo

## Conjunto FIRST

$$\mathrm{FIRST}(\alpha) = \{a \in \Sigma \mid \alpha \Rightarrow^* a\,\beta\}$$

Incluir $\lambda$ em $\mathrm{FIRST}(\alpha)$ se $\alpha$ é anulável.

## Conjunto FIRST

**Regras para $\mathrm{FIRST}(X_1\, X_2\, \cdots\, X_n)$:**

1. Sequência vazia: $\mathrm{FIRST}(\lambda) = \{\lambda\}$
2. $X_1$ é terminal $a$: $\mathrm{FIRST}(X_1\cdots) = \{a\}$
3. $X_1$ é não-terminal:
   - Incluir $\mathrm{FIRST}(X_1) \setminus \{\lambda\}$
   - Se $\lambda \in \mathrm{FIRST}(X_1)$: incluir também
     $\mathrm{FIRST}(X_2\cdots X_n)$

## Conjunto FOLLOW

$$\mathrm{FOLLOW}(A) = \{a \in \Sigma \cup \{\$\} \mid S \Rightarrow^* \alpha\,A\,a\,\beta\}$$

## Conjunto FOLLOW

**Regras:**

1. $\$ \in \mathrm{FOLLOW}(S)$ (símbolo inicial)
2. Para cada produção $B \to \alpha\,A\,\beta$:
   - Adicionar $\mathrm{FIRST}(\beta) \setminus \{\lambda\}$ a
     $\mathrm{FOLLOW}(A)$
   - Se $\lambda \in \mathrm{FIRST}(\beta)$: adicionar $\mathrm{FOLLOW}(B)$ a
     $\mathrm{FOLLOW}(A)$

Calculado iterativamente até ponto fixo.

## Construção da Tabela

Para cada produção $A \to \alpha$:

1. Para cada $a \in \mathrm{FIRST}(\alpha) \setminus \{\lambda\}$:
   - Definir $M[A, a] = A \to \alpha$

## Construção da Tabela

2. Se $\lambda \in \mathrm{FIRST}(\alpha)$:
   - Para cada $b \in \mathrm{FOLLOW}(A)$:
     - Definir $M[A, b] = A \to \alpha$

Entradas não preenchidas indicam **erro**.

## Construção da Tabela

**Conflito** = uma entrada recebe mais de uma produção

- gramática não é LL(1)!

# Exemplo Completo: Tabela LL(1)

## Gramática de Expressões (LL(1))

$$\begin{array}{lcl}
E  &\to& T\; E' \\
E' &\to& +\; T\; E' \mid \lambda \\
T  &\to& F\; T' \\
T' &\to& *\; F\; T' \mid \lambda \\
F  &\to& (\; E\; ) \mid \mathbf{n}
\end{array}$$

## Conjuntos FIRST

| Não-terminal | FIRST            |
| ------------ | ---------------- |
| $E$          | $\{(, n\}$       |
| $E'$         | $\{+, \lambda\}$ |
| $T$          | $\{(, n\}$       |
| $T'$         | $\{*, \lambda\}$ |
| $F$          | $\{(, n\}$       |

## Conjuntos FOLLOW

| Não-terminal | FOLLOW            |
| ------------ | ----------------- |
| $E$          | $\{\$, )\}$       |
| $E'$         | $\{\$, )\}$       |
| $T$          | $\{+, \$, )\}$    |
| $T'$         | $\{+, \$, )\}$    |
| $F$          | $\{*, +, \$, )\}$ |

## Tabela de Parsing LL(1)

|      | $n$     | $+$        | $*$        | $($       | $)$       | $\$$      |
| ---- | ------- | ---------- | ---------- | --------- | --------- | --------- |
| $E$  | $T\;E'$ | —          | —          | $T\;E'$   | —         | —         |
| $E'$ | —       | $+\;T\;E'$ | —          | —         | $\lambda$ | $\lambda$ |
| $T$  | $F\;T'$ | —          | —          | $F\;T'$   | —         | —         |
| $T'$ | —       | $\lambda$  | $*\;F\;T'$ | —         | $\lambda$ | $\lambda$ |
| $F$  | $n$     | —          | —          | $(\;E\;)$ | —         | —         |

Cada entrada tem no máximo uma produção — a gramática é LL(1).

# Conflitos na Tabela LL(1)

## Conflito FIRST/FIRST

Quando duas alternativas de um mesmo não-terminal começam com o mesmo terminal:

```
S → if E then S else S
  | if E then S
  | other
```

## Conflito FIRST/FIRST

$\mathrm{FIRST}(\mathbf{if}\;E\;\mathbf{then}\;S\;\mathbf{else}\;S) = \{\mathbf{if}\}$
$\mathrm{FIRST}(\mathbf{if}\;E\;\mathbf{then}\;S) = \{\mathbf{if}\}$

$M[S, \mathbf{if}]$ recebe **duas produções**: **conflito FIRST/FIRST**!

## Conflito FIRST/FOLLOW

Quando uma produção pode derivar $\lambda$ e os conjuntos FIRST e FOLLOW não são
disjuntos:

```
S → A a
A → a | λ
```

## Conflito FIRST/FOLLOW

- $\mathrm{FIRST}(A) = \{a, \lambda\}$
- $\mathrm{FOLLOW}(A) = \{a\}$

Para $M[A, a]$: tanto $A \to a$ (pois $a \in \mathrm{FIRST}(A)$) quanto
$A \to \lambda$ (pois $a \in \mathrm{FOLLOW}(A)$): **conflito FIRST/FOLLOW**!

# Implementação em Haskell

## Tipos Principais

```haskell
data Symbol = Terminal String | NonTerminal String

type Production = [Symbol]
type Grammar    = Map String [Production]

type ParseTable = Map (String, String) ParseAction

data ParseAction
  = Derive Production
  | Accept
  | Error
```

## Cálculo de FIRST por Ponto Fixo

```haskell
computeFirstSets :: Grammar -> FirstSet
computeFirstSets g = fixedPoint step initial
  where
    initial = Map.fromList [(nt, []) | nt <- nonTerminals g]
    step cur = Map.mapWithKey update cur
      where
        update nt _ = unions $ map (firstForSequence g cur)
                                   (fromMaybe [] (Map.lookup nt g))
```

- `fixedPoint step initial`: aplica `step` repetidamente até convergência
- Cada iteração pode expandir os conjuntos FIRST

## `firstForSequence`: Implementação das Regras

```haskell
firstForSequence :: Grammar -> FirstSet -> [Symbol] -> [String]
firstForSequence _ _ [] = ["λ"]
firstForSequence g fs (sym:syms)
    | isTerminal sym =
        if isLambda sym
        then firstForSequence g fs syms
        else [symbolString sym]
    | otherwise =
        let nt         = symbolString sym
            firstOfSym = fromMaybe [] (Map.lookup nt fs)
            withoutLam = firstOfSym \\ ["λ"]
        in if "λ" `elem` firstOfSym
           then withoutLam `union` firstForSequence g fs syms
           else withoutLam
```

## O Parser LL(1)

```haskell
parse :: Grammar -> ParseTable -> [String] -> ParseResult
parse grammar table tokens = go initialStack (tokens ++ ["$"]) []
  where
    startSym     = head (nonTerminals grammar)
    initialStack = [NonTerminal startSym, Terminal "$"]
```

## Parser LL(1)

```haskell
go (Terminal "$" : _) ("$" : _) acc = ParseOk (reverse acc)

go (Terminal t : stack') (a : inp') acc
    | t == a    = go stack' inp' acc
    | otherwise = ParseError ("expected '" ++ t ++ "'")

go (NonTerminal nt : stack') inp@(a : _) acc =
    case Map.lookup (nt, a) table of
        Just (Derive prod) ->
            go (filter (not . isLambda) prod ++ stack') inp (prod : acc)
        _ -> ParseError ("no rule for (" ++ nt ++ ", " ++ a ++ ")")
```

# Conclusão

## Conclusão

- Apresentamos os conceitos de FIRST, FOLLOW e anulável.

- Apresentamos a construção da tabela LL(1) e seu algoritmo de parsing.

## Conclusão

- Não suporta **recursão à esquerda** (requer transformação)
- Exige **fatoração à esquerda** (prefixos comuns causam conflitos)
- Algumas gramáticas são inerentemente não-LL(1)
