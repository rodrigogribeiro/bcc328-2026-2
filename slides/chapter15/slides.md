---
title: "Introdução aos Sistemas de Tipos"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar sistemas de tipos como a especificação da análise semântica.

- Discutir propriedades importantes de sistemas de tipos.

# Tipos em Linguagens de Programação

## O que é um Tipo?

- Um **tipo** classifica valores e define:
  - Quais operações são aplicáveis
  - Como os valores são representados na memória
  - Que conjunto de valores o tipo compreende

## Sistema de Tipo

- O **sistema de tipos** associa tipos a expressões e verifica a coerência
  dessas associações
- Erros de tipo: somar um booleano a um inteiro, aplicar `pred true`
- Expressões com erros de tipo são **sintaticamente válidas**, mas
  **semanticamente sem significado**

## Tipagem Estática

**Tipagem estática** (_static typing_): verificação em **tempo de compilação**

- O compilador rejeita o programa se houver erro de tipo
- Exemplos: Haskell, Java, C, Rust

## Tipagem Dinâmica

- **Tipagem dinâmica** (_dynamic typing_): verificação em **tempo de execução**
  - Erros detectados apenas quando a operação inválida é executada
  - Exemplos: Python, JavaScript, Ruby, Lisp

## Tipagem Forte

- **Tipagem forte** (_strong typing_): não permite conversões implícitas entre
  tipos incompatíveis
  - Operações entre tipos diferentes resultam em erro
  - Exemplos: Haskell, Python

## Tipagem Fraca

- **Tipagem fraca** (_weak typing_): realiza conversões implícitas entre tipos
  - Comportamentos frequentemente surpreendentes
  - C: converte implicitamente entre inteiros e ponteiros
  - JavaScript: `1 + "1"` resulta em `"11"`

## Fraca vs Forte

- Estas classificações são **independentes**.
  - Python é dinamicamente tipado e fortemente tipado; C é estaticamente tipado
    e fracamente tipado.

# A Linguagem de Expressões Tipadas

## Sintaxe

$$\begin{array}{lcll}
t & ::= & \mathbf{true} \mid \mathbf{false} & \text{(booleanos)} \\
  & \mid & \mathbf{if}\ t_1\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 & \text{(condicional)} \\
  & \mid & \mathbf{0} & \text{(zero)} \\
  & \mid & \mathbf{succ}\ t \mid \mathbf{pred}\ t & \text{(sucessor, predecessor)} \\
  & \mid & \mathbf{iszero}\ t & \text{(teste de zero)}
\end{array}$$

## Tipos

**Tipos:** $$T ::= \mathbf{Bool} \mid \mathbf{Nat}$$

## Valores

- **Valores** (termos que não podem ser reduzidos):
  - $nv$ são os **valores numéricos**: $\mathbf{0}$,
    $\mathbf{succ}\ \mathbf{0}$, $\mathbf{succ}\ (\mathbf{succ}\ \mathbf{0})$,
    ...
  - Valores booleanos: $\mathbf{true}$ e $\mathbf{false}$

$$\begin{array}{lcl}
v  & ::= & \mathbf{true} \mid \mathbf{false} \mid nv \\
nv & ::= & \mathbf{0} \mid \mathbf{succ}\ nv
\end{array}$$

# O Sistema de Tipos

## Relação de Tipagem

- Notação $\vdash t : T$
  - o termo $t$ tem tipo $T$.

- A relação é definida por regras de inferência.

## Booleanos

$$
\begin{array}{c}
\frac{}{\vdash \mathbf{true} : \mathbf{Bool}} \quad\text{(T-True)}\\
\frac{}{\vdash \mathbf{false} : \mathbf{Bool}} \quad\text{(T-False)}
\end{array}
$$

## Condicionais

$$\frac{
  \vdash t_1 : \mathbf{Bool} \quad
  \vdash t_2 : T \quad
  \vdash t_3 : T
}{
  \vdash \mathbf{if}\ t_1\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 : T
} \quad\text{(T-If)}$$

A regra (T-If) exige que os dois ramos tenham o **mesmo tipo** $T$.

## Naturais

$$
\begin{array}{c}
   \frac{}{\vdash \mathbf{0} : \mathbf{Nat}} \quad\text{(T-Zero)}\\
   \frac{\vdash t_1 : \mathbf{Nat}}{\vdash \mathbf{succ}\ t_1 : \mathbf{Nat}} \quad\text{(T-Succ)}\\
\end{array}
$$

## Naturais

$$
\begin{array}{c}
\frac{\vdash t_1 : \mathbf{Nat}}{\vdash \mathbf{pred}\ t_1 : \mathbf{Nat}} \quad\text{(T-Pred)}\\
\frac{\vdash t_1 : \mathbf{Nat}}{\vdash \mathbf{iszero}\ t_1 : \mathbf{Bool}} \quad\text{(T-IsZero)}
\end{array}$$

## Exemplo

$\vdash \mathbf{iszero}\ (\mathbf{succ}\ \mathbf{0}) : \mathbf{Bool}$

$$\dfrac{
  \dfrac{
    \dfrac{}{\vdash \mathbf{0} : \mathbf{Nat}}
  }{\vdash \mathbf{succ}\ \mathbf{0} : \mathbf{Nat}}
}{\vdash \mathbf{iszero}\ (\mathbf{succ}\ \mathbf{0}) : \mathbf{Bool}}$$

## Exemplo

- $\mathbf{succ}\ \mathbf{true}$ **não é tipável**:
  - A regra (T-Succ) exige que o argumento tenha tipo $\mathbf{Nat}$
  - Mas $\mathbf{true}$ tem tipo $\mathbf{Bool}$
  - Não existe derivação válida — o tipo checker **rejeita** o programa

## Exemplo

- Outros exemplos de termos não tipáveis:
  - $\mathbf{pred}\ \mathbf{false}$: (T-Pred) exige $\mathbf{Nat}$, argumento é
    $\mathbf{Bool}$
  - $\mathbf{if}\ \mathbf{0}\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3$: (T-If)
    exige $\mathbf{Bool}$ na condição

## Unicidade de Tipos

- **Lema (Unicidade):** Se $\vdash t : T$ e $\vdash t : T'$, então $T = T'$.

- A tipagem é **determinística**: o verificador sempre produz um resultado
  único.

# Semântica Small-Step

## Formas Presas

- Os termos irredutíveis são **valores** $v$ ou **formas presas** (_stuck
  terms_):
  - Termos que não são valores e para os quais nenhuma regra se aplica
  - Representam **erros em tempo de execução**

## Formas Presas

- Exemplos de formas presas:

  - $\mathbf{succ}\ \mathbf{true}$: $\mathbf{true}$ não é $nv$, e nenhuma regra
    reduz isso
  - $\mathbf{pred}\ \mathbf{false}$: idem
  - $\mathbf{if}\ \mathbf{0}\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3$:
    $\mathbf{0}$ é valor numérico, não booleano

## Formas Presas

- **O papel do sistema de tipos**: garantir que termos bem tipados **nunca** se
  tornem formas presas.

## Regras de Redução

$$\frac{t_1 \to t_1'}{\mathbf{if}\ t_1\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 \to \mathbf{if}\ t_1'\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3}
\quad\text{(E-If)}$$

## Regras de Redução

$$\frac{}{\mathbf{if}\ \mathbf{true}\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 \to t_2}
\quad\text{(E-IfTrue)}$$

## Regras de Redução

$$\frac{}{\mathbf{if}\ \mathbf{false}\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3 \to t_3}
\quad\text{(E-IfFalse)}$$

## Regras de Redução

$$\frac{t_1 \to t_1'}{\mathbf{succ}\ t_1 \to \mathbf{succ}\ t_1'}
\quad\text{(E-Succ)}$$

## Regras de Redução

$$
\frac{t_1 \to t_1'}{\mathbf{pred}\ t_1 \to \mathbf{pred}\ t_1'}
\quad\text{(E-Pred)}$$

## Regras de Redução

$$\frac{}{\mathbf{pred}\ \mathbf{0} \to \mathbf{0}}
\quad\text{(E-PredZero)}
$$

## Regras de Redução

$$
\frac{}{\mathbf{pred}\ (\mathbf{succ}\ nv_1) \to nv_1}
\quad\text{(E-PredSucc)}$$

## Regras de Redução

$$\frac{t_1 \to t_1'}{\mathbf{iszero}\ t_1 \to \mathbf{iszero}\ t_1'}
\quad\text{(E-IsZero)}
$$

## Regras de Redução

$$
\frac{}{\mathbf{iszero}\ \mathbf{0} \to \mathbf{true}}
\quad\text{(E-IsZeroZero)}$$

## Regras de Redução

$$\frac{}{\mathbf{iszero}\ (\mathbf{succ}\ nv_1) \to \mathbf{false}}
\quad\text{(E-IsZeroSucc)}$$

## Exemplo

$$\mathbf{if}\ (\mathbf{iszero}\ \mathbf{0})\ \mathbf{then}\ (\mathbf{succ}\ \mathbf{0})\ \mathbf{else}\ \mathbf{0}$$

## Exemplo

$$\xrightarrow{\text{E-If, E-IsZeroZero}}
\mathbf{if}\ \mathbf{true}\ \mathbf{then}\ (\mathbf{succ}\ \mathbf{0})\ \mathbf{else}\ \mathbf{0}$$

## Exemplo

$$\xrightarrow{\text{E-IfTrue}}
\mathbf{succ}\ \mathbf{0}$$

## Exemplo

Outro exemplo:
$\mathbf{pred}\ (\mathbf{succ}\ (\mathbf{succ}\ \mathbf{0})) \xrightarrow{\text{E-PredSucc}} \mathbf{succ}\ \mathbf{0}$

# Corretude do Sistema de Tipos

## Type Soundness

> **Teorema (Type Soundness):** Se $\vdash t : T$ e $t \to^* t'$, então $t'$ é
> um valor ou existe $t''$ tal que $t' \to t''$.

Em palavras: **programas bem tipados não ficam presos**.

## Type Soundness

A prova apoia-se em dois lemas fundamentais e independentes:

| Lema            | Enunciado                                   |
| --------------- | ------------------------------------------- |
| **Preservação** | O tipo se mantém após cada passo de redução |
| **Progresso**   | Um termo bem tipado é valor ou pode reduzir |

## Lema de Preservação

> **Lema (Preservation):** Se $\vdash t : T$ e $t \to t'$, então
> $\vdash t' : T$.

**Significado:** a tipagem é **invariante sob redução** — o tipo não se altera
durante a execução.

## Lema de Preservação

**Por que é importante?** Sem preservação, um termo poderia começar bem tipado
e, após reduções, tornar-se de tipo diferente — invalidando qualquer garantia do
verificador de tipos.

## Lema de Preservação

**Prova:** Por indução na derivação de $t \to t'$, analisando cada regra de
redução.

## Alguns Casos

_Caso_ (E-IfTrue):
$t = \mathbf{if}\ \mathbf{true}\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3$,
$t' = t_2$.

De (T-If): $\vdash t_2 : T$ e $\vdash t_3 : T$. Logo $\vdash t_2 : T$. ✓

## Alguns Casos

_Caso_ (E-If): $t_1 \to t_1'$,
$t' = \mathbf{if}\ t_1'\ \mathbf{then}\ t_2\ \mathbf{else}\ t_3$.

De (T-If): $\vdash t_1 : \mathbf{Bool}$. Por hip. de indução:
$\vdash t_1' : \mathbf{Bool}$. Aplicando (T-If): $\vdash t' : T$. ✓

## Alguns Casos

_Caso_ (E-Succ): $t_1 \to t_1'$, $t' = \mathbf{succ}\ t_1'$.

De (T-Succ): $\vdash t_1 : \mathbf{Nat}$. Por hip. de ind.:
$\vdash t_1' : \mathbf{Nat}$. Logo $\vdash \mathbf{succ}\ t_1' : \mathbf{Nat}$.
✓

## Alguns Casos

_Caso_ (E-IsZeroZero): $t' = \mathbf{true}$. Por (T-True):
$\vdash \mathbf{true} : \mathbf{Bool}$; tipo de $t$ via (T-IsZero) é
$\mathbf{Bool}$. ✓

## Lema de Progresso

> **Lema (Progress):** Se $\vdash t : T$, então $t$ é um valor ou existe $t'$
> tal que $t \to t'$.

**Significado:** termos bem tipados **nunca ficam presos** — sempre progridem.

## Lema de Progresso

**Por que é importante?** Sem progresso, o tipo seria preservado mas a execução
poderia travar. O progresso garante que nunca há um estado de erro
irrecuperável.

**Prova:** Por indução estrutural na derivação de $\vdash t : T$.

## Alguns Casos

_Casos_ (T-True), (T-False), (T-Zero): $t$ já é valor. ✓

## Alguns Casos

_Caso_ (T-If): $\vdash t_1 : \mathbf{Bool}$. Por hip. de ind. sobre $t_1$: ou
$t_1$ é valor, ou reduz.

- Se $t_1 \to t_1'$: aplica-se (E-If). ✓
- Se $t_1$ é valor de tipo $\mathbf{Bool}$: pelo lema de unicidade, $t_1$ não
  pode ser $nv$ (tipo $\mathbf{Nat}$). Logo
  $t_1 \in \{\mathbf{true}, \mathbf{false}\}$.
  - $t_1 = \mathbf{true}$: aplica-se (E-IfTrue). ✓
  - $t_1 = \mathbf{false}$: aplica-se (E-IfFalse). ✓

## Alguns Casos

_Caso_ (T-Succ): $\vdash t_1 : \mathbf{Nat}$. Por hip. de ind.: ou $t_1$ reduz,
ou é valor.

- $t_1 \to t_1'$: aplica-se (E-Succ). ✓
- $t_1$ é valor de tipo $\mathbf{Nat}$: pela unicidade, $t_1$ é $nv$. Logo
  $\mathbf{succ}\ nv$ é valor numérico. ✓

## Alguns Casos

_Caso_ (T-Pred): $\vdash t_1 : \mathbf{Nat}$. Por hip. de ind.: ou $t_1$ reduz,
ou é $nv$.

- $t_1 \to t_1'$: aplica-se (E-Pred). ✓ | $nv = \mathbf{0}$: (E-PredZero). ✓ |
  $nv = \mathbf{succ}\ nv_1$: (E-PredSucc). ✓

## Corretude

> **Prova do Teorema (Type Soundness):** Seja $\vdash t : T$ e $t \to^* t'$.
>
> Por **preservação** (aplicada repetidamente a cada passo da sequência
> $t \to^* t'$): $\vdash t' : T$.
>
> Por **progresso**: $t'$ é valor ou existe $t''$ com $t' \to t''$. ✓

# Sistema de Tipos para TLine

## TLine: Contexto e Relação de Tipagem

- TLine tem três tipos ($\mathbf{Int}$, $\mathbf{Bool}$, $\mathbf{String}$) e um
  **contexto de tipagem**:

$$\Gamma : \mathit{Var} \rightharpoonup \mathit{Ty}$$

## Regras de Tipos

- Regras para expressões: $\Gamma \vdash e : T$

$$\frac{}{\Gamma \vdash n : \mathbf{Int}} \quad\text{(T-Int)}$$

## Regras de Tipos

$$
\frac{x \in \mathrm{dom}(\Gamma)}{\Gamma \vdash x : \Gamma(x)} \quad\text{(T-Var)}$$

## Regras de Tipos

$$\frac{\Gamma \vdash e_1 : \mathbf{Int} \quad \Gamma \vdash e_2 : \mathbf{Int}}{\Gamma \vdash e_1 \oplus e_2 : \mathbf{Int}} \quad\text{(T-ArithOp)}
$$

## Regras de Tipos

$$
\frac{\Gamma \vdash e_1 : \mathbf{Int} \quad \Gamma \vdash e_2 : \mathbf{Int}}{\Gamma \vdash e_1 \otimes e_2 : \mathbf{Bool}} \quad\text{(T-CmpOp)}$$

## Regras de Tipos

- Regras para comandos: $\Gamma \vdash s \dashv \Gamma'$

$$\frac{\Gamma \vdash e : T}{\Gamma \vdash \mathbf{var}\ x : T = e \dashv \Gamma[x \mapsto T]} \quad\text{(T-Decl)}$$

## Regras de Tipos

$$\frac{x \in \mathrm{dom}(\Gamma) \quad \Gamma \vdash e : \Gamma(x)}{\Gamma \vdash x \mathbin{:=} e \dashv \Gamma} \quad\text{(T-Assign)}$$

## Regras de Tipos

$$\frac{\Gamma \vdash e_p : \mathbf{String} \quad x \in \mathrm{dom}(\Gamma) \quad \Gamma(x) = \mathbf{Int}}{\Gamma \vdash \mathbf{read}\ e_p\ x \dashv \Gamma} \quad\text{(T-Read)}$$

## Regras de Tipos

- **T-Decl** é a única regra que **estende** o contexto:
  $\Gamma' = \Gamma[x \mapsto T]$
- As demais **preservam** o contexto: $\Gamma' = \Gamma$

# Sistema de Tipos para TWhile

## Escopo

- TWhile adiciona `if` e `while` com **escopo léxico**: variáveis declaradas
  dentro de um bloco não escapam.

## Escopo

**Formalização**: o contexto de **saída** é sempre igual ao contexto de
**entrada** $\Gamma$:

$$\frac{\Gamma \vdash e : \mathbf{Bool} \quad \Gamma \vdash B_1 \dashv \Gamma_1 \quad \Gamma \vdash B_2 \dashv \Gamma_2}{\Gamma \vdash \mathbf{if}\ e\ \mathbf{then}\ B_1\ \mathbf{else}\ B_2 \dashv \Gamma} \quad\text{(T-If)}$$

## Escopo

$$\frac{\Gamma \vdash e : \mathbf{Bool} \quad \Gamma \vdash B \dashv \Gamma'}{\Gamma \vdash \mathbf{while}\ e\ \mathbf{do}\ B \dashv \Gamma} \quad\text{(T-While)}$$

- Os contextos $\Gamma_1$, $\Gamma_2$ e $\Gamma'$ são **descartados**: variáveis
  locais aos blocos não são visíveis fora deles.

# Sistema de Tipos para TImp

## Tipos e Ambientes

- TImp estende TWhile com funções e registros

$$\tau \;::=\; \mathbf{Int} \mid \mathbf{Bool} \mid \mathbf{String} \mid R \qquad \rho \;::=\; \mathbf{void} \mid \tau$$

## Tipos e Ambientes

- Relação de tipagem: $\Gamma;\Delta;\Phi \vdash e : \tau$ e
  $\Gamma;\Delta;\Phi;\rho_\mathit{ret} \vdash s \dashv \Gamma'$

## Regras para Registros

**Acesso a campo (T-Field):**
$$\frac{\Gamma;\Delta;\Phi \vdash e : R \quad \Delta(R)(f) = \tau}{\Gamma;\Delta;\Phi \vdash e.f : \tau}$$

## Regras para Registros

**Construção (T-New):**
$$\frac{R \in \mathrm{dom}(\Delta) \quad \Delta(R) = \overline{(f_i:\tau_i)} \quad \Gamma;\Delta;\Phi \vdash e_i : \tau_i}{\Gamma;\Delta;\Phi \vdash \mathbf{new}\ R\{\overline{f_i=e_i}\} : R}$$

## Regras para Registros

**Atribuição de campo (T-FieldAssign):**
$$\frac{\Gamma(x) = R \quad \Delta(R)(f) = \tau \quad \Gamma;\Delta;\Phi \vdash e : \tau}{\Gamma;\Delta;\Phi \vdash x.f := e \dashv \Gamma}$$

## Regras para Funções

**Chamada como expressão (T-CallExpr):**
$$\frac{\Phi(f) = ([\tau_1,\ldots,\tau_n],\;\tau) \quad \Gamma;\Delta;\Phi \vdash e_i : \tau_i}{\Gamma;\Delta;\Phi \vdash f(e_1,\ldots,e_n) : \tau}$$

## Regras para Funções

**Retorno com valor (T-RetVal):**
$$\frac{\rho_\mathit{ret} = \tau \quad \Gamma;\Delta;\Phi \vdash e : \tau}{\Gamma;\ldots;\rho_\mathit{ret} \vdash \mathbf{return}\ e \dashv \Gamma}$$

## Regras para Funções

**Declaração de função (T-FuncDecl):**
$$\frac{[x_1\!\mapsto\!\tau_1,\ldots,x_n\!\mapsto\!\tau_n];\Delta;\Phi;\rho \vdash B \dashv \_}{\Delta;\Phi \vdash \mathbf{fn}\ f(\overline{x_i:\tau_i}):\rho\ \{B\}\ \checkmark}$$

# Conclusão

## Conclusão

- **Tipos** classificam valores e restringem operações; tipagem pode ser
  estática ou dinâmica, forte ou fraca
- O **sistema de tipos** $\vdash t : T$ é definido por regras de inferência —
  cada construtor tem exatamente uma regra (unicidade de tipos)

## Conclusão

- **Formas presas**: termos sem valor e sem redução possível — representam erros
  em tempo de execução
- **Type Soundness** = Preservação + Progresso: programas bem tipados nunca
  ficam presos

## Conclusão

- **Preservação**: prova que o tipo não muda durante a execução (indução na
  redução $t \to t'$)
- **Progresso**: prova que a execução nunca trava (indução na tipagem
  $\vdash t : T$)
- Os dois lemas são **independentes** e **complementares** — cada um é
  necessário e insuficiente sozinho
