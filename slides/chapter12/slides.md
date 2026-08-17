---
title: "Semântica Operacional"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar os conceitos de semântica small e big step.

- Mostrar como implementar um interpretador a partir da especificação da
  semântica.

# Introdução à Semântica Formal

## Semântica Formal

- Após a análise léxica e sintática, sabemos se o programa está escrito corretamente.
- A semântica responde: **o que o programa faz?**

## Semântica Formal

- **Semântica operacional**: define o significado de um programa descrevendo
  como ele é _executado_
- Especificação se traduz diretamente em código (interpretadores e compiladores)

## Dois Estilos

- **Small-step** (_pequenos passos_):
  - Define cada passo elementar de redução
  - Relação $e \to e'$: "a expressão $e$ reduz em um passo para $e'$"
  - Útil para raciocinar sobre propriedades de execução

## Dois Estilos

- **Big-step** (_grandes passos_, ou semântica natural):
  - Define diretamente o valor final
  - Relação $e \Downarrow v$: "a expressão $e$ avalia para o valor $v$"
  - Mais direta para implementar interpretadores

## Expressões

$$\begin{array}{lcl}
e &::=& n \mid e_1 + e_2 \mid e_1 * e_2
\end{array}$$

Em Haskell:

```haskell
data Exp
  = EInt Int
  | Exp :+: Exp
  | Exp :*: Exp
```

# Semântica Small-Step

## Valores

- Um **valor** é uma expressão na forma final
  - Para expressões aritméticas, é um número inteiro $v ::= n$.

## Regras

- As regras de redução são apresentadas como sistemas de inferência:

$$\frac{\text{premissas}}{\text{conclusão}}$$

## Regras para Adição

- **Adição de valores** (axioma):

$$\frac{}{n_1 + n_2 \to n_1 \mathbin{\hat{+}} n_2} \quad \text{(Add)}$$

## Regras para Adição

- **Redução no lado esquerdo** (esquerda primeiro):

$$\frac{e_1 \to e_1'}{e_1 + e_2 \to e_1' + e_2} \quad \text{(AddL)}$$

## Regras para Adição

- **Redução no lado direito** (quando esquerdo já é valor):

$$\frac{e_2 \to e_2'}{n_1 + e_2 \to n_1 + e_2'} \quad \text{(AddR)}$$

## Regras para Adição

- A regra (AddR) só se aplica quando $n_1$ é um valor
  - Garante avaliação **da esquerda para a direita**.

## Multiplicação

$$\frac{}{n_1 * n_2 \to n_1 \mathbin{\hat{*}} n_2} \quad \text{(Mul)}$$

## Multiplicação

$$\frac{e_1 \to e_1'}{e_1 * e_2 \to e_1' * e_2} \quad \text{(MulL)}$$

## Multiplicação

$$\frac{e_2 \to e_2'}{n_1 * e_2 \to n_1 * e_2'} \quad \text{(MulR)}$$

## Sequências de Redução

- A execução completa é uma sequência de passos terminando em um valor:

$$e \to e_1 \to e_2 \to \cdots \to v$$

- Escrevemos $e \to^* v$ quando existe tal sequência (zero ou mais passos).

## Exemplo: Small-Step para $(2 + 3) * 4$

$$\begin{array}{ll}
(2 + 3) * 4 & \xrightarrow{\text{MulL (com Add)}} \\
5 * 4       & \xrightarrow{\text{Mul}} \\
20          &
\end{array}$$

## Exemplo: Small-Step para $1 + 2 * 3$

$$\begin{array}{ll}
1 + 2 * 3 & \xrightarrow{\text{AddR (com Mul)}} \\
1 + 6     & \xrightarrow{\text{Add}} \\
7         &
\end{array}$$

# Semântica Big-Step

## Regras Big-Step

- A relação $e \Downarrow v$ define diretamente o valor final.

## Regras Big-Step

- **Um número avalia para si mesmo:**

$$\frac{}{n \Downarrow n} \quad \text{(Num)}$$

## Regras Big-Step

- **Adição:**

$$\frac{e_1 \Downarrow n_1 \quad e_2 \Downarrow n_2}{e_1 + e_2 \Downarrow n_1 \mathbin{\hat{+}} n_2} \quad \text{(Add)}$$

## Regras Big-Step

- **Multiplicação:**

$$\frac{e_1 \Downarrow n_1 \quad e_2 \Downarrow n_2}{e_1 * e_2 \Downarrow n_1 \mathbin{\hat{*}} n_2} \quad \text{(Mul)}$$

## Exemplo: Derivação Big-Step para $(2 + 3) * 4$

$$\dfrac{
  \dfrac{
    \dfrac{}{2 \Downarrow 2} \quad \dfrac{}{3 \Downarrow 3}
  }{2 + 3 \Downarrow 5}
  \quad
  \dfrac{}{4 \Downarrow 4}
}{(2 + 3) * 4 \Downarrow 20}$$

## Exemplo: Derivação Big-Step para $1 + 2 * 3$

$$\dfrac{
  \dfrac{}{1 \Downarrow 1}
  \quad
  \dfrac{
    \dfrac{}{2 \Downarrow 2} \quad \dfrac{}{3 \Downarrow 3}
  }{2 * 3 \Downarrow 6}
}{1 + 2 * 3 \Downarrow 7}$$

# Implementação em Haskell

## Interpretador

- A semântica big-step se traduz em Haskell de forma quase literal:

```haskell
eval :: Exp -> Int
eval (EInt n)    = n
eval (e1 :+: e2) = eval e1 + eval e2
eval (e1 :*: e2) = eval e1 * eval e2
```

## Interpretador

- Correspondência com as regras:

- `eval (EInt n) = n` implementa a regra **(Num)**
- `eval (e1 :+: e2) = eval e1 + eval e2` implementa **(Add)**
- `eval (e1 :*: e2) = eval e1 * eval e2` implementa **(Mul)**

## Executando o Interpretador

```bash
cabal run exp -- --interp --file input.exp
```

Para a entrada `(2 + 3) * 4`, o interpretador produz `20`.

```haskell
-- O pipeline completo:
-- 1. Lexer: String → [Token]
-- 2. Parser: [Token] → Exp
-- 3. eval: Exp → Int
```

# Conclusão

## Conclusão

- Apresentamos dois estilos de semântica operacional
  - Big-step e small-step
- Mostramos como implementar um interpretador a partir de sua semântica
  big-step.
