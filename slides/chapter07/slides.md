---
title: "Parsing Expression Grammars (PEGs)"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar o formalismo de PEGs para descrição de analisadores sintáticos.

- Apresentar uma implementação tipada em Haskell com verificação estática de
  boa-formação.

- Ilustrar parsing sensível a indentação.

# Motivação

## Motivação

- Combinadores de parsing são poderosos, mas GLCs podem ser ambíguas.
  - Como lidar com recursão à esquerda?
- Algumas linguagens são difíceis de especificar sem ambiguidade.

## Motivação

- **PEGs**: formalismo com escolha determinística
- Sem ambiguidade por definição: único resultado para cada entrada
- Correspondem diretamente a parsers descendentes recursivos

## GLC vs. PEG: Diferença Fundamental

| Aspecto              | GLC                  | PEG                |
| -------------------- | -------------------- | ------------------ |
| Escolha              | Não-determinística   | **Ordenada**       |
| Ambiguidade          | Possível             | Impossível         |
| Recursão à esquerda  | Suporta naturalmente | Não suporta (loop) |
| Predicados lookahead | Não tem              | Sim ($!e$, $\&e$)  |

# Operadores de PEG

## Operadores de PEG

| Expressão     | Nome                | Semântica                               |
| ------------- | ------------------- | --------------------------------------- |
| $\varepsilon$ | vazio               | Sempre tem sucesso sem consumir         |
| $a$           | terminal            | Consome e casa com símbolo $a$          |
| $A$           | não-terminal        | Invoca a regra de nome $A$              |
| $e_1\; e_2$   | sequência           | $e_1$ depois $e_2$ sobre o restante     |
| $e_1 / e_2$   | escolha ordenada    | Tenta $e_1$; se falhar, tenta $e_2$     |
| $e^*$         | repetição gulosa    | Zero ou mais ocorrências de $e$         |
| $e^+$         | repetição positiva  | Uma ou mais ocorrências de $e$          |
| $e\;?$        | opcional            | Zero ou uma ocorrência de $e$           |
| $!e$          | predicado negativo  | Sucesso se $e$ falha; não consome       |
| $\&e$         | predicado positivo  | Sucesso se $e$ tem sucesso; não consome |

## Escolha Ordenada

```
Se e1 tem SUCESSO:
  → Retorna o resultado de e1 imediatamente
  → e2 NUNCA é tentada

Se e1 FALHA:
  → e2 é tentada sobre a MESMA entrada original
  → Retorna o resultado de e2 (sucesso ou falha)
```

- Elimina ambiguidade: o primeiro match sempre vence

## Terminação e Boa-Formação

Uma PEG é **bem formada** (e portanto termina) se:

1. **Não há recursão à esquerda** direta ou indireta
2. **Toda repetição $e^*$** é tal que $e$ consume ao menos um símbolo

# Implementação Tipada

## Por que tipos?

- A verificação de boa-formação pode ser feita **em tempo de compilação**
- GADTs permitem indexar expressões pelo seu **tipo de PEG** $(η, F)$
  - $η$ = anulabilidade
  - $F$ = conjunto cabeça (não-terminais que podem aparecer à esquerda)
- Gramáticas com recursão à esquerda são **rejeitadas pelo compilador**

## O Tipo de PEG

```haskell
data Ty = MkTy Bool [Symbol]
--              ^    ^
--              η    F (head set)

type family Nullable (t :: Ty) :: Bool
type family First    (t :: Ty) :: [Symbol]
```

## Ambiente de Tipagem

```haskell
data EnvEntry = EnvEntry Ty Type
type Env = [(Symbol, EnvEntry)]
```

Exemplo:

```haskell
type ArithEnv =
  '[ '("expr", 'EnvEntry ('MkTy 'False '["term","factor"]) Exp)
   , '("term", 'EnvEntry ('MkTy 'False '["factor"])        Exp)
   , ...
   ]
```

## O GADT PExp

```haskell
data PExp (env :: Env) (ty :: Ty) (a :: Type) where
  Pure    :: a -> PExp env ('MkTy 'True '[]) a
  Term    :: Char -> PExp env ('MkTy 'False '[]) Char
  Star    :: PExp env ('MkTy 'False f) a
          -> PExp env ('MkTy 'True  f) [a]
  Seq     :: PExp env t1 (a -> b) -> PExp env t2 a
          -> PExp env (SeqTy t1 t2) b
  Choice  :: PExp env t1 a -> PExp env t2 a
          -> PExp env (ChoiceTy t1 t2) a
```

- `Star` exige `'MkTy 'False f` no corpo: o tipo garante que o corpo **não é anulável**
- A condição **Acyclic** rejeita recursão à esquerda em tempo de compilação

## Gramáticas

```haskell
data Grammar (env :: Env) (startTy :: Ty) (startA :: Type) where
  Grammar :: Acyclic env   -- aciclicidade verificada em compilação
          => Rules env env -- condição de ponto fixo
          -> PExp env startTy startA
          -> Grammar env startTy startA
```

## Executando uma Gramática

```haskell
data Result a = OK a String String | Fail

parse :: Grammar env ty a -> String -> Result a
```

- `OK valor consumido restante`
- `Fail` se a expressão inicial não casou

# O Quasi-Quoter

## Sintaxe de Ford

Em vez de construir `PExp` diretamente, use o quasi-quoter:

```haskell
import PEG.QQ (pegRules, pegExpr)
```

## Regras com Rótulos

```haskell
[pegRules|
  expr <- t:term ts:(o:[+-] u:term)* { foldl addOp t ts }
  term <- f:factor fs:(o:[*/] g:factor)*
            { foldl (\acc (op,r) -> addOp acc (op,r)) f fs }
  factor <- n:number / '(' e:expr ')' / '-' f:factor { Neg f }
  number <- ds:[0-9]+ { Lit (read ds :: Int) }
|]
```

## Semântica dos Rótulos

- `x:e` — liga o valor de `e` à variável `x`
- Sequência sem rótulos → produz `()`
- Sequência com um rótulo → produz o valor desse rótulo
- Sequência com vários rótulos → produz tupla
- `{ expr }` — ação semântica com os rótulos em escopo

# Exemplo: Expressões

## Parser de Expressões Aritméticas

```haskell
data Exp = Lit Int | Neg Exp
         | Add Exp Exp | Sub Exp Exp
         | Mul Exp Exp | Div Exp Exp

arith :: Grammar ArithEnv _ Exp
arith =
  Grammar
    [pegRules|
       expr   <- t:term ts:(o:[+-] u:term)*
                   { foldl addOp t ts }
       term   <- f:factor fs:(o:[*/] g:factor)*
                   { foldl (\acc (op,r)->addOp acc (op,r)) f fs }
       factor <- n:number / '(' e:expr ')' / '-' f:factor { Neg f }
       number <- ds:[0-9]+ { Lit (read ds :: Int) }
    |]
    (nt @"expr")
```

## Resultados

```haskell
ghci> parse arith "1+2*3"
OK (Add (Lit 1) (Mul (Lit 2) (Lit 3))) ...

ghci> parse arith "10-2-3"
OK (Sub (Sub (Lit 10) (Lit 2)) (Lit 3)) ...
-- associatividade à esquerda via foldl
```

# Parsing Sensível a Indentação

## Três Novos Operadores

Extensão de Nestra (2017): três operadores que **preservam o tipo de PEG**:

| Operador   | Sintaxe | Significado                              |
| ---------- | ------- | ---------------------------------------- |
| $e^\rho$   | `e^R`   | Bloco com baseline em relação $R$        |
| $e_\sigma$ | `e_R`   | Modo de token: terminais em relação $R$  |
| $\|e\|$    | `\|e\|` | Primeiro token alinhado ao baseline      |

## Relações de Indentação

| Relação | Significado                    |
| ------- | ------------------------------ |
| `>`     | Estritamente mais indentado    |
| `>=`    | Indentado ou alinhado          |
| `=`     | Mesmo baseline                 |
| `~`     | Irrestrito (use em whitespace) |
| `+n`    | Exatamente $n$ colunas         |

## Regra do Whitespace

**Whitespace deve ser consumido sob `~`:**

```haskell
ws <- [ \t\r\n]*_~
```

- Uma quebra de linha tem uma coluna como qualquer caractere
- Consumi-la sob modo restritivo fixaria o baseline indevidamente

**Alinhamento vai em torno do item, não do espaço:**

```
ws |stmt|   -- CORRETO
|ws stmt|   -- ERRADO: o espaço seria alinhado
```

# Exemplo: Layout Haskell

## Blocos do-style

```haskell
data DoStmt = Atom String | Nested [DoStmt]

[pegRules|
  doexp  <- "do" b:(i:istmts / j:stmts)
  istmts <- ss:(ws st:|s:stmt|)+^>
  stmts  <- r:(ws '{' ws s:stmt ss:(ws ';' ws t:stmt)*
               ws '}' { s : ss })^~
  stmt   <- d:doexp { Nested d } / n:name { Atom n }
  name   <- cs:[a-z]+
  ws     <- [ \t\r\n]*_~
|]
```

## Resultados

```haskell
ghci> parseWith layoutOpts doExp "do a\n   b\n   c\n"
OK [Atom "a", Atom "b", Atom "c"] ...

ghci> parseWith layoutOpts doExp "do { a; b; c }\n"
OK [Atom "a", Atom "b", Atom "c"] ...

ghci> parseWith layoutOpts doExp "do a\n   do x\n      y\n   b\n"
OK [Atom "a", Nested [Atom "x", Atom "y"], Atom "b"] ...
```

- Indentação e colchetes explícitos **são equivalentes**
- **Aninhamento arbitrário** funciona

# Conclusão

## Conclusão

- PEGs usam **escolha ordenada** $e_1 / e_2$ — não-ambíguas por definição

- A implementação tipada usa GADTs para verificar em **tempo de compilação**:
  - Anulabilidade dos corpos de repetição
  - Aciclicidade do ambiente (sem recursão à esquerda)

- O quasi-quoter `pegRules` permite escrever gramáticas na sintaxe de Ford
  com rótulos e ações semânticas

- A extensão de Nestra adiciona `^`, `_`, `|e|` para parsing sensível a
  indentação, sem alterar o tipo de PEG do operando
