---
title: "Geração de Código X86-64 — Parte I: Arquitetura e Canonicalização"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a arquitetura X86-64 como alvo de compilação: registradores,
  convenção de chamada ABI e sintaxe AT&T.

- Definir a AST de instruções X86-64 usada pelo compilador.

- Formalizar a **canonicalização** da IRT: a eliminação de nós `ESEQ` que
  transforma expressões com efeitos colaterais em sequências de comandos
  puros, tornando a análise e a geração de código tratáveis.

# Introdução

## Por que Código Nativo?

Ao longo do curso geramos código para dois alvos de alto nível:

| Alvo | Vantagem | Desvantagem |
|---|---|---|
| Transpilação → C | Simples, portável | Depende do GCC/clang |
| IRT → WebAssembly | Portável, sandboxed | Runtime WASI obrigatório |

**Código nativo X86-64** elimina intermediários: o binário produzido
executa diretamente no sistema operacional, sem runtime adicional.

$$\text{TImp} \xrightarrow{\text{frontend}} \text{IRT} \xrightarrow{\text{canon}} \text{IRT}^\flat \xrightarrow{\text{vivacidade}} \text{IRT}^\flat \xrightarrow{\text{coloração}} \text{IRT}^\flat \xrightarrow{\text{seleção}} \text{X86-64}$$

## O Pipeline de Compilação Nativa

Cada fase do pipeline tem uma responsabilidade precisa:

1. **Canonicalização**: remove `ESEQ`, tornando a IRT linearizável
2. **Análise de vivacidade**: determina quais temporários estão vivos em cada ponto
3. **Grafo de interferência**: codifica quais temporários não podem compartilhar registrador
4. **Coloração de grafo**: atribui registradores (ou slots de pilha) aos temporários
5. **Seleção de instruções**: traduz cada nó da IRT para instruções X86-64

Este capítulo cobre os passos **1** (canonicalização) e a infra-estrutura X86-64.
Os passos 2–4 estão no capítulo 26 e o passo 5 no capítulo 27.

# Arquitetura X86-64

## Registradores de Propósito Geral

X86-64 possui 16 registradores de 64 bits:

| Registrador | Papel convencional |
|---|---|
| `%rax` | Resultado de função; dividendo/quociente |
| `%rbx` | Callee-saved (preservado pela função chamada) |
| `%rcx` | 4º argumento; contador de shift |
| `%rdx` | 3º argumento; resto da divisão |
| `%rsi` | 2º argumento |
| `%rdi` | 1º argumento |
| `%rbp` | Ponteiro de frame (base) |
| `%rsp` | Ponteiro de pilha |
| `%r8–%r9` | 5º e 6º argumento |
| `%r10–%r11` | Scratch temporário (caller-saved) |
| `%r12–%r15` | Callee-saved |

## Convenção de Chamada ABI (System V AMD64)

**Passagem de argumentos inteiros** (esquerda para direita):

$$\%\mathtt{rdi},\ \%\mathtt{rsi},\ \%\mathtt{rdx},\ \%\mathtt{rcx},\ \%\mathtt{r8},\ \%\mathtt{r9}$$

Argumentos adicionais vão na pilha.

**Retorno**: resultado inteiro em `%rax`.

**Alinhamento**: `%rsp` deve ser **múltiplo de 16** imediatamente antes de
qualquer instrução `callq`.

**Callee-saved** (a função chamada deve preservar):
$\%\mathtt{rbx},\ \%\mathtt{rbp},\ \%\mathtt{r12},\ \%\mathtt{r13},\ \%\mathtt{r14},\ \%\mathtt{r15}$

**Caller-saved** (podem ser destruídos por qualquer chamada):
$\%\mathtt{rax},\ \%\mathtt{rcx},\ \%\mathtt{rdx},\ \%\mathtt{rsi},\ \%\mathtt{rdi},\ \%\mathtt{r8}\text{–}\%\mathtt{r11}$

## Pool de Alocação e Registradores Scratch

Dividimos os registradores em dois grupos:

**Pool de alocação** (atribuídos a temporários pelo alocador):

$$\mathit{allocPool} = \{\%\mathtt{rbx},\ \%\mathtt{rcx},\ \%\mathtt{rsi},\ \%\mathtt{rdi},\ \%\mathtt{r8},\ \%\mathtt{r9},\ \%\mathtt{r12},\ \%\mathtt{r13},\ \%\mathtt{r14},\ \%\mathtt{r15}\}$$

**Registradores scratch** (reservados para o gerador de código):

| Nome | Registrador | Uso |
|---|---|---|
| $\mathit{acc}$ | `%rax` | Resultado de expressão, retorno |
| $\mathit{div}$ | `%rdx` | Resto da divisão (`idivq`) |
| $\mathit{mem}$ | `%r10` | Endereço de escrita em memória |
| $\mathit{bin}$ | `%r11` / pilha | Primeiro operando de BINOP |

## Sintaxe AT&T

O assembly gerado usa a sintaxe AT&T (padrão no Linux com `gas`/`clang`):

| Conceito | Sintaxe AT&T | Exemplo |
|---|---|---|
| Imediato | `$n` | `movq $42, %rax` |
| Registrador | `%reg` | `movq %rbx, %rax` |
| Memória | `n(%reg)` | `movq -8(%rbp), %rax` |
| RIP-relativo | `lbl(%rip)` | `leaq .fmt(%rip), %rdi` |
| Operandos | `src, dst` | `addq %r11, %rax` |

Sufixo `q` indica operação de 64 bits (*quadword*).

## AST de Instruções — Registradores e Condições

```haskell
data Reg
  = RAX | RBX | RCX | RDX | RSI | RDI
  | R8  | R9  | R10 | R11 | R12 | R13 | R14 | R15
  | RBP | RSP
  deriving (Eq, Ord, Show)

data Cc = E | NE | L | LE | G | GE   -- condition codes
  deriving (Eq, Show)
```

Constantes do alocador:

```haskell
allocPool  :: [Reg]
allocPool   = [RBX, RCX, RSI, RDI, R8, R9, R12, R13, R14, R15]

calleeSaved :: Set Reg
calleeSaved  = Set.fromList [RBX, R12, R13, R14, R15]

callerSaved :: Set Reg
callerSaved  = Set.fromList [RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11]

argRegs :: [Reg]
argRegs  = [RDI, RSI, RDX, RCX, R8, R9]
```

## AST de Instruções — Operandos e Instruções

```haskell
data Operand
  = Imm Int          -- $n
  | Reg Reg          -- %reg
  | AL               -- %al  (byte baixo de %rax)
  | Mem Int Reg      -- n(%reg)
  | RipRel String    -- lbl(%rip)

data Instr
  = Movq   Operand Operand | Movzbq Operand Operand
  | Leaq   Operand Operand
  | Addq   Operand Operand | Subq  Operand Operand
  | Imulq  Operand Operand | Idivq Operand
  | Negq   Operand         | Cqo
  | Andq   Operand Operand | Orq   Operand Operand
  | Xorq   Operand Operand
  | Salq   Operand Operand | Shrq  Operand Operand
  | Sarq   Operand Operand
  | Cmpq   Operand Operand | Testq Operand Operand
  | Setcc  Cc Operand      | Pushq Operand | Popq Operand
  | Callq  String  | Retq
  | Jmp    String  | Jcc Cc String
  | GlobLabel String | LocLabel String | Dir String
```

# Canonicalização da IRT

## O Problema dos Nós ESEQ

A IRT permite que comandos apareçam **dentro de expressões** via `ESEQ`:

```
ESEQ(s, e)   -- executa s, avalia e, retorna valor de e
```

Exemplo — fatorial iterativo inline em `main`:

```
EXP(CALL(NAME("print"),
  ESEQ(
    SEQ(MOVE(TEMP "result", CONST 1),
        SEQ(LABEL "loop", ...)),   -- laço completo!
    TEMP "result")))
```

O `ESEQ` contém um **laço inteiro** dentro de um argumento de chamada.
Isso impede a análise de vivacidade baseada no CFG linear.

## Por que ESEQ é Problemático

A análise de vivacidade opera sobre a **sequência linear** de comandos
produzida por `linearize`. Mas `linearize` só achata `SEQ` no topo:

```haskell
linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s           = [s]    -- ESEQ permanece opaco!
```

Resultado: um `EXP(CALL(..., ESEQ(laço, e)))` vira **um único nó** no CFG.
Os temporários definidos dentro do `ESEQ` **nunca aparecem** nas equações
de vivacidade e ficam sem alocação de registrador.

**Solução**: canonicalizar antes de qualquer análise.

## Canonicalização — Intuição

A canonicalização transforma `ESEQ(s, e)` em dois passos:

1. **Hoist**: extrai os comandos $s$ para o nível de comando superior
2. **Substitui**: substitui o `ESEQ` pela expressão pura $e$

Resultado: após a canonicalização, **nenhum** nó `ESEQ` subsiste em
nenhuma posição da árvore IRT.

$$\underbrace{\mathsf{EXP}(\mathsf{CALL}(f,\ \mathsf{ESEQ}(s,\ e)))}_{\text{antes}}
  \;\longmapsto\;
  \underbrace{\mathsf{SEQ}(s,\ \mathsf{EXP}(\mathsf{CALL}(f,\ e)))}_{\text{depois}}$$

## Formalização — Extração de Expressões

Definimos $\mathsf{pull}(e) = (\vec{s},\, e')$ onde $\vec{s}$ é a lista de
comandos extraídos e $e'$ é a expressão pura resultante:

$$\frac{}{\mathsf{pull}(n) = ([\,],\, n)} \quad\text{(Pull-Const)}
\qquad
\frac{}{\mathsf{pull}(t) = ([\,],\, t)} \quad\text{(Pull-Temp)}
\qquad
\frac{}{\mathsf{pull}(\ell) = ([\,],\, \ell)} \quad\text{(Pull-Name)}$$

$$\frac{\mathsf{pull}(e) = (\vec{s},\, e')}{\mathsf{pull}(\mathsf{ESEQ}(s,\, e)) = (\mathsf{canon}(s) \mathbin{+\!\!+} \vec{s},\; e')} \quad\text{(Pull-ESeq)}$$

$$\frac{\mathsf{pull}(e_1) = (\vec{s}_1,\, e_1') \quad \mathsf{pull}(e_2) = (\vec{s}_2,\, e_2')}{\mathsf{pull}(\mathsf{BINOP}(\oplus,\, e_1,\, e_2)) = (\vec{s}_1 \mathbin{+\!\!+} \vec{s}_2,\; \mathsf{BINOP}(\oplus,\, e_1',\, e_2'))} \quad\text{(Pull-Binop)}$$

$$\frac{\mathsf{pull}(e) = (\vec{s},\, e')}{\mathsf{pull}(\mathsf{MEM}(e)) = (\vec{s},\; \mathsf{MEM}(e'))} \quad\text{(Pull-Mem)}$$

## Formalização — Extração de Chamadas

$$\frac{\mathsf{pull}(f) = (\vec{s}_f,\, f') \quad \forall i.\; \mathsf{pull}(a_i) = (\vec{s}_i,\, a_i')}{\mathsf{pull}(\mathsf{CALL}(f,\, \vec{a})) = (\vec{s}_f \mathbin{+\!\!+} \vec{s}_1 \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \vec{s}_n,\; \mathsf{CALL}(f',\, \vec{a}'))} \quad\text{(Pull-Call)}$$

**Nota**: a ordem esquerda-para-direita garante que os efeitos colaterais
de cada subexpressão são hoistados na ordem de avaliação original.

## Formalização — Canonicalização de Comandos

$\mathsf{canon}(s)$ retorna uma lista plana de comandos `ESEQ`-livres:

$$\frac{}{\mathsf{canon}(\mathsf{LABEL}(l)) = [\mathsf{LABEL}(l)]} \quad\text{(Canon-Label)}$$

$$\frac{\mathsf{canon}(s_1) = \vec{c}_1 \quad \mathsf{canon}(s_2) = \vec{c}_2}{\mathsf{canon}(\mathsf{SEQ}(s_1,\, s_2)) = \vec{c}_1 \mathbin{+\!\!+} \vec{c}_2} \quad\text{(Canon-Seq)}$$

$$\frac{\mathsf{pull}(e) = (\vec{s},\, e')}{\mathsf{canon}(\mathsf{MOVE}(\mathsf{TEMP}(t),\, e)) = \vec{s} \mathbin{+\!\!+} [\mathsf{MOVE}(\mathsf{TEMP}(t),\, e')]} \quad\text{(Canon-Move)}$$

$$\frac{\mathsf{pull}(e) = (\vec{s},\, e')}{\mathsf{canon}(\mathsf{EXP}(e)) = \vec{s} \mathbin{+\!\!+} [\mathsf{EXP}(e')]} \quad\text{(Canon-Exp)}$$

$$\frac{\mathsf{pull}(e) = (\vec{s},\, e')}{\mathsf{canon}(\mathsf{CJUMP}(e,\, l_t,\, l_f)) = \vec{s} \mathbin{+\!\!+} [\mathsf{CJUMP}(e',\, l_t,\, l_f)]} \quad\text{(Canon-CJump)}$$

## Formalização — Comandos Restantes

$$\frac{\mathsf{pull}(e) = (\vec{s},\, e')}{\mathsf{canon}(\mathsf{JUMP}(e)) = \vec{s} \mathbin{+\!\!+} [\mathsf{JUMP}(e')]} \quad\text{(Canon-Jump)}$$

$$\frac{\forall i.\; \mathsf{pull}(e_i) = (\vec{s}_i,\, e_i')}{\mathsf{canon}(\mathsf{RETURN}(\vec{e})) = \vec{s}_1 \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \vec{s}_n \mathbin{+\!\!+} [\mathsf{RETURN}(\vec{e}')]} \quad\text{(Canon-Return)}$$

**Propriedade** (correção): para todo programa $p$, $\mathsf{canon}(p)$
produz um programa equivalente sem nenhum nó `ESEQ`.

**Propriedade** (completude): após $\mathsf{canon}$, `linearize` produz
uma sequência plana onde cada temporário aparece nas equações de vivacidade.

## Implementação em Haskell

```haskell
-- | Remove todos os nós ESEQ por hoisting.
canonicalize :: Stmt -> Stmt
canonicalize s = mkSeq (canonList s)
  where
    mkSeq []     = EXP (CONST 0)
    mkSeq [x]    = x
    mkSeq (x:xs) = SEQ x (mkSeq xs)

canonList :: Stmt -> [Stmt]
canonList (SEQ s1 s2)         = canonList s1 ++ canonList s2
canonList (MOVE (TEMP t) src) =
  let (ss, src') = pullESeqs src
  in ss ++ [MOVE (TEMP t) src']
canonList (EXP e) =
  let (ss, e') = pullESeqs e in ss ++ [EXP e']
canonList (CJUMP e lt lf) =
  let (ss, e') = pullESeqs e in ss ++ [CJUMP e' lt lf]
canonList (RETURN es) =
  let pairs = map pullESeqs es
  in concatMap fst pairs ++ [RETURN (map snd pairs)]
canonList s = [s]   -- LABEL
```

## Implementação — Extração de Expressões

```haskell
-- | pull(e) = (comandos hoistados, expressão pura)
pullESeqs :: Expr -> ([Stmt], Expr)
pullESeqs (ESEQ s e) =
  let (ss, e') = pullESeqs e
  in (canonList s ++ ss, e')
pullESeqs (BINOP op e1 e2) =
  let (ss1, e1') = pullESeqs e1
      (ss2, e2') = pullESeqs e2
  in (ss1 ++ ss2, BINOP op e1' e2')
pullESeqs (MEM e) =
  let (ss, e') = pullESeqs e in (ss, MEM e')
pullESeqs (CALL ef args) =
  let (ssf, ef') = pullESeqs ef
      pairs      = map pullESeqs args
  in (ssf ++ concatMap fst pairs, CALL ef' (map snd pairs))
pullESeqs e = ([], e)   -- CONST, TEMP, NAME
```

## Exemplo de Canonicalização

**Antes** — `ESEQ` com laço inteiro dentro de argumento:

```
EXP(CALL(NAME("print"),
  ESEQ(SEQ(MOVE(TEMP "result", CONST 1),
           SEQ(LABEL "L", ...loop..., JUMP "L")),
       TEMP "result")))
```

**Depois** — comandos hoistados ao nível superior:

```
SEQ(MOVE(TEMP "result", CONST 1),
SEQ(LABEL "L",
SEQ(...loop...,
SEQ(JUMP "L",
    EXP(CALL(NAME("print"), TEMP "result"))))))
```

O laço agora é uma sequência plana de comandos — tratável pelo CFG e
pela análise de vivacidade.

# Conclusão

## Sumário do Capítulo

- **X86-64** possui 16 registradores; dividimos em *pool de alocação*
  (10 registradores) e *scratch* (6 reservados ao gerador)

- **Convenção ABI**: 6 argumentos em registradores, resultado em `%rax`,
  `%rsp` alinhado a 16 bytes antes de `callq`

- **AST de instruções**: `Reg`, `Operand`, `Instr` — a representação
  Haskell das instruções X86-64 geradas

- **Canonicalização**: as regras $\mathsf{pull}(e)$ e $\mathsf{canon}(s)$
  eliminam todos os nós `ESEQ` da IRT, tornando possível a análise linear

- **Correção**: após a canonicalização, `linearize` produz uma sequência
  plana onde todos os temporários participam das equações de vivacidade

## Próximos Passos

- **Capítulo 26**: análise de vivacidade (equações de ponto fixo) e
  alocação de registradores por coloração de grafo

- **Capítulo 27**: seleção de instruções (regras formais $\Phi \vdash e \Rightarrow \vec{I}$)
  e o pipeline completo TImp → X86-64
