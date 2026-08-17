---
title: "Análise Sintática LR(1) e LALR(1)"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a motivação para os algoritmos LR(1) e LALR.

- Apresentar o algoritmo LR(1).

- Apresentar o algoritmo LALR como uma otimização de LR(1).

# Motivação: Além do SLR

## Limitações

- **LR(0)**: insere reduce em todos os terminais
  - Muitos conflitos
- **SLR**: usa o follow(A)
  - Ainda impreciso

## Limitações

**Exemplo problemático** com recursão à direita:

$$\begin{array}{lcl}
E &\to& T + E \mid T \\
T &\to& n \mid (E)
\end{array}$$

## Limitações

Estado após reconhecer $T$ no estado inicial:

$$\begin{array}{l}
E \to T . + E \\
E \to T .
\end{array}$$

## O Conflito Shift-Reduce

- Item $E \to T .$ está completo
  - LR(0) insere reduce $E \to T$ em **todos** os terminais.
- Item $E \to T . + E$ exige **shift** em `+`
  - Resultado: **conflito shift-reduce** em `+`

## O Conflito Shift-Reduce

- A raiz do problema
  - Quando o próximo token é `+`, ainda pode vir $+E$, então ...
  - **Não** devemos reduzir.
  - Quando é `$` ou `)`, devemos reduzir.

## O Conflito de Shift-Reduce

- Para tomar essa decisão, precisamos analisar o próximo token de entrada.
  - Lookahead.

- Um único token de lookahead local resolve o conflito
  - Essa é a ideia do **LR(1)**.

# O Algoritmo LR(1)

## Itens LR(1)

Um item LR(1) $[A \to \beta . \gamma, a]$ carrega:

- $A \to \beta\gamma$: produção sendo reconhecida
- $.$ (ponto): o que já foi analisado
- $a$: **lookahead** — terminal que pode aparecer **imediatamente após** $A$
  neste contexto específico

## Redução

- Quando o item está completo ($\gamma = \lambda$):
  - reduzir $A \to \beta$ **somente** na coluna $a$.

## Redução

- Lookahead é **calculado localmente** para cada item, não globalmente como no
  SLR.

## Fechamento LR(1)

- Para item $[A \to \alpha . B \beta, a]$, adicionar $[B \to . \gamma, b]$ para
  toda produção $B \to \gamma$ e todo $b \in \mathrm{FIRST}(\beta\, a)$.

## Fechamento LR(1)

- Se $\beta$ não é anulável: $b \in \mathrm{FIRST}(\beta)$
- Se $\beta$ é anulável ou vazio: $b$ inclui também o lookahead $a$

## Construção dos Estados LR(1)

- Estado inicial: fechamento de $\{[S' \to . S, \$]\}$

- O lookahead é transferido **sem alteração** — Ele depende do contexto em que o
  item foi criado.

## Tabela LR(1)

- **Shift**: $[A \to \alpha . a \beta, b]$ com $a$ terminal →
  `action[I, a] = Shift j`

## Tabela LR(1)

- **Reduce**: $[A \to \alpha ., a]$ completo → `action[I, a] = Reduce(A → α)`
  **apenas na coluna $a$**

## Tabela LR(1)

- **Accept**: $[S' \to S ., \$]$ → `action[I, $] = Accept`

## Tabela LR(1)

- Cada reduce aparece **apenas na coluna do lookahead do item** — não em todas.

# Exemplo

## Gramática

$$\begin{array}{lcl}
E &\to& E + T \mid T \\
T &\to& T * F \mid F \\
F &\to& (E) \mid n
\end{array}$$

## Estado 0

- Fechamento de $\{[S' \to . E, \$]\}$:

$$\begin{array}{ll}
S' \to . E & \$ \\
E \to . E + T & \$, + \\
E \to . T & \$, + \\
T \to . T * F & \$, +, * \\
T \to . F & \$, +, * \\
F \to . (E) & \$, +, *, ) \\
F \to . n & \$, +, *, )
\end{array}$$

## Estado 1

— $\text{goto}(I_0, E)$:

$$\begin{array}{ll}
S' \to E . & \$ \\
E \to E . + T & \$, +
\end{array}$$

## Estado 2

— $\text{goto}(I_0, T)$:

$$\begin{array}{ll}
E \to T . & \$, + \\
T \to T . * F & \$, +, *
\end{array}$$

## Estado 3

— $\text{goto}(I_0, F)$:

$$\begin{array}{ll}
T \to F . & \$, +, *
\end{array}$$

## Tabela LR(1)

| Estado | $n$ | $+$   | $*$   | $($ | $)$   | $\$$  | $E$ | $T$ | $F$ |
| ------ | --- | ----- | ----- | --- | ----- | ----- | --- | --- | --- |
| 0      | s5  |       |       | s4  |       |       | 1   | 2   | 3   |
| 1      |     | s6    |       |     |       | acc   |     |     |     |
| 2      |     | r E→T | s7    |     |       | r E→T |     |     |     |
| 3      |     | r T→F | r T→F |     |       | r T→F |     |     |     |
| 4      | s5  |       |       | s4  |       |       | 8   | 9   | 3   |
| 5      |     | r F→n | r F→n |     | r F→n | r F→n |     |     |     |

## Tabela LR(1)

Cada ação de reduce aparece **apenas nas colunas do lookahead do item** — não em
todas.

# O Algoritmo LALR(1)

## Motivação

- LR(1) gera estados distintos para o mesmo conjunto de itens LR(0) quando os
  lookaheads diferem.

## Motivação

- **Exemplo:** os estados 3 e 10 da gramática de expressões têm o mesmo núcleo
  $T \to F .$:
  - Estado 3 (fora de parênteses): lookaheads $\{\$, +, *\}$
  - Estado 10 (dentro de parênteses): lookaheads $\{\$, +, *, )\}$

## Motivação

- Para gramáticas reais, o número de estados LR(1) pode ser uma **ordem de
  grandeza maior** que LR(0).

## A Ideia LALR

- **Observação**: dois estados com o mesmo **núcleo** têm a mesma estrutura de
  shifts e gotos.

## A Ideia LALR

- **Solução**: fundir todos os estados LR(1) com o mesmo núcleo, **unindo** seus
  lookaheads.

- **Resultado**: $|\text{estados LALR}| = |\text{estados LR(0)}|$ mas lookaheads
  mais precisos que SLR.

## Algoritmo LALR

- Dois passos:

1. Construir todos os estados LR(1)
2. Fundir estados com o mesmo núcleo, realizando a união de seus lookaheads.

## Problemas

- A fusão pode introduzir conflitos **reduce-reduce**:

- Se dois estados tinham lookaheads disjuntos, a união pode fazer dois itens
  completos reivindicar a mesma coluna.

## Problemas

- Quando isso ocorre: gramática é LR(1) mas **não LALR(1)**
- Conflitos **shift-reduce** nunca são introduzidos pela fusão (shifts dependem
  do núcleo, não do lookahead)

## Problemas

- Na prática: a imensa maioria das gramáticas de linguagens de programação é
  LALR(1).

# Exemplo: Tabela LALR(1)

## Identificação dos Pares com o Mesmo Núcleo

| Núcleo                           | Estados LR(1) | Lookaheads unidos |
| -------------------------------- | ------------- | ----------------- |
| $T \to F .$                      | 3 e 10        | $\{\$, +, *, )\}$ |
| $E \to E + . T$, ...             | 6 e 14        | $\{\$, +, )\}$    |
| $T \to T * . F$, ...             | 7 e 15        | $\{\$, +, *, )\}$ |
| $E \to E + T .$, $T \to T . * F$ | 11 e 16       | $\{\$, +, )\}$    |
| $T \to T * F .$                  | 12 e 17       | $\{\$, +, *, )\}$ |

Denominamos: **A** = 3+10, **B** = 6+14, **C** = 7+15, **D** = 11+16, **E** =
12+17.

## Tabela LALR(1) para Expressões

| Estado | $n$ | $+$     | $*$     | $($ | $)$     | $\$$    | $E$ | $T$ | $F$ |
| ------ | --- | ------- | ------- | --- | ------- | ------- | --- | --- | --- |
| 0      | s5  |         |         | s4  |         |         | 1   | 2   | A   |
| 1      |     | sB      |         |     |         | acc     |     |     |     |
| 2      |     | r E→T   | sC      |     |         | r E→T   |     |     |     |
| A      |     | r T→F   | r T→F   |     | r T→F   | r T→F   |     |     |     |
| 4      | s5  |         |         | s4  |         |         | 8   | 9   | A   |
| 5      |     | r F→n   | r F→n   |     | r F→n   | r F→n   |     |     |     |
| B      | s5  |         |         | s4  |         |         |     | D   | A   |
| C      | s5  |         |         | s4  |         |         |     |     | E   |
| 8      |     | sB      |         |     | s13     |         |     |     |     |
| D      |     | r E→E+T | sC      |     | r E→E+T | r E→E+T |     |     |     |
| E      |     | r T→T*F | r T→T*F |     | r T→T*F | r T→T*F |     |     |     |

# Conclusão

## Conclusão

- Neste capítulo apresentamos os algoritmos LR(1) e LALR.

- O gerador de analisadores sintáticos Happy utiliza o algoritmo LALR.
