---
title: "Geração de Código X86-64 — Parte III: Seleção de Instruções e Pipeline Completo"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar as **regras formais de seleção de instruções** que mapeiam
  expressões e enunciados IRT para sequências de instruções X86-64.

- Detalhar como o gerador de código mantém o **alinhamento de 16 bytes** da
  pilha em chamadas de função aninhadas.

- Implementar o módulo `IRToX86` em Haskell e verificar o pipeline completo
  com o exemplo de `factorial.timp`.

- Comparar as três estratégias de geração de back-end implementadas:
  **C**, **WebAssembly** e **X86-64**.

# Regras Formais de Seleção

## Notação

Usaremos o julgamento:

$$\Phi \vdash e \Rightarrow \vec{I}$$

que significa: "sob o ambiente de coloração $\Phi$ (que mapeia cada temporário
a um registrador ou slot de memória), a expressão $e$ é compilada para a
sequência de instruções $\vec{I}$, cujo resultado fica em `%rax`."

Para enunciados:

$$\Phi \vdash s \Rightarrow \vec{I}$$

que significa: "o enunciado $s$ é compilado para $\vec{I}$, sem valor de retorno
no registrador acumulador."

## Expressões: Constante e Temporário

$$\frac{}{\Phi \vdash \texttt{CONST}(n) \Rightarrow \texttt{movq } \$n,\; \%\text{rax}}$$

$$\frac{\Phi(t) = r}{\Phi \vdash \texttt{TEMP}(t) \Rightarrow \texttt{movq } r,\; \%\text{rax}}
\qquad\text{(se } r \neq \%\text{rax)}$$

$$\frac{\Phi(t) = \%\text{rax}}{\Phi \vdash \texttt{TEMP}(t) \Rightarrow \varepsilon}
\qquad\text{(já no acumulador)}$$

$$\frac{\Phi(t) = \text{off}(\%\text{rbp})}{\Phi \vdash \texttt{TEMP}(t) \Rightarrow \texttt{movq } \text{off}(\%\text{rbp}),\; \%\text{rax}}$$

## Expressões: BINOP

O desafio do BINOP é que a compilação de $e_2$ pode sobrescrever `%rax`
antes de usarmos o resultado de $e_1$. A solução é **empilhar** $e_1$:

$$\frac{\Phi \vdash e_1 \Rightarrow \vec{I_1}
       \quad \Phi \vdash e_2 \Rightarrow \vec{I_2}
       \quad \vec{I_{\oplus}} = \llbracket \oplus \rrbracket}
      {\Phi \vdash \texttt{BINOP}(\oplus, e_1, e_2) \Rightarrow
       \vec{I_1};\;
       \texttt{pushq \%rax};\;
       \vec{I_2};\;
       \texttt{popq \%r11};\;
       \vec{I_{\oplus}}}$$

Onde `%r11` é `scratchBinop` e `%rax` é `scratchAcc`. Após o `popq`,
temos `%r11 = e_1` e `%rax = e_2`.

## Tradução dos Operadores Binários

| operador $\oplus$ | instruções $\vec{I_\oplus}$ (pré: `%r11 = e_1`, `%rax = e_2`) |
|-------------------|---------------------------------------------------------------|
| `BAdd`            | `addq %r11, %rax`                                             |
| `BMul`            | `imulq %r11, %rax`                                            |
| `BSub`            | `negq %rax; addq %r11, %rax`                                  |
| `BDiv`            | `movq %rax, %r10; movq %r11, %rax; cqo; idivq %r10`           |
| `BMod`            | (idem BDiv) `movq %rdx, %rax`                                 |
| `BAnd`            | `andq %r11, %rax`                                             |
| `BOr`             | `orq %r11, %rax`                                              |
| `BXor`            | `xorq %r11, %rax`                                             |
| `BEq`             | `cmpq %rax, %r11; sete %al; movzbq %al, %rax`                 |
| `BLt`             | `cmpq %rax, %r11; setl %al; movzbq %al, %rax`                 |

Comparações: `cmpq src, dst` calcula `dst − src`; logo
`cmpq %rax, %r11` = `%r11 − %rax` = $e_1 - e_2$. ✓

## Expressões: MEM e ESEQ

$$\frac{\Phi \vdash e \Rightarrow \vec{I}}
      {\Phi \vdash \texttt{MEM}(e) \Rightarrow \vec{I};\; \texttt{movq }0(\%\text{rax}),\; \%\text{rax}}$$

Carrega o valor armazenado no endereço apontado por `%rax`.

$$\frac{\Phi \vdash s \Rightarrow \vec{I_s}
       \quad \Phi \vdash e \Rightarrow \vec{I_e}}
      {\Phi \vdash \texttt{ESEQ}(s, e) \Rightarrow \vec{I_s};\; \vec{I_e}}$$

Na prática, o passo de canonicalização elimina todos os `ESEQ` antes da
geração de código. A regra acima é fornecida por completude.

## Expressões: CALL

Seja $\vec{r} = [r_1, \ldots, r_n]$ os registradores de argumento ABI
(`%rdi %rsi %rdx %rcx %r8 %r9`).

$$\frac{\{\Phi \vdash a_i \Rightarrow \vec{I_i}\}_{i=1}^n}
      {\Phi \vdash \texttt{CALL}(\texttt{NAME}(f),\, [a_1, \ldots, a_n]) \Rightarrow
       \mathit{save\_caller};\;
       \vec{I_1};\; \texttt{movq \%rax,} r_1;\;
       \cdots;\;
       \vec{I_n};\; \texttt{movq \%rax,} r_n;\;
       \texttt{xorq \%rax, \%rax};\;
       \texttt{callq } f;\;
       \mathit{restore\_caller}}$$

`save_caller` e `restore_caller` salvam/restauram registradores do pool de
alocação que são caller-saved e estão em uso (atribuídos a algum temporário
pelo coloridor).

## Enunciados: MOVE para Temporário

$$\frac{\Phi \vdash e \Rightarrow \vec{I} \quad \Phi(t) = r}
      {\Phi \vdash \texttt{MOVE}(\texttt{TEMP}(t),\, e) \Rightarrow
       \vec{I};\; \texttt{movq \%rax,} r}
\quad (r \neq \%\text{rax})$$

$$\frac{\Phi \vdash e \Rightarrow \vec{I} \quad \Phi(t) = \%\text{rax}}
      {\Phi \vdash \texttt{MOVE}(\texttt{TEMP}(t),\, e) \Rightarrow \vec{I}}$$

$$\frac{\Phi \vdash e \Rightarrow \vec{I} \quad \Phi(t) = \text{off}(\%\text{rbp})}
      {\Phi \vdash \texttt{MOVE}(\texttt{TEMP}(t),\, e) \Rightarrow
       \vec{I};\; \texttt{movq \%rax,}\; \text{off}(\%\text{rbp})}$$

## Enunciados: MOVE para Memória, LABEL, JUMP

$$\frac{\Phi \vdash \mathit{addr} \Rightarrow \vec{I_a}
       \quad \Phi \vdash \mathit{val} \Rightarrow \vec{I_v}}
      {\Phi \vdash \texttt{MOVE}(\texttt{MEM}(\mathit{addr}),\, \mathit{val}) \Rightarrow
       \vec{I_a};\; \texttt{movq \%rax, \%r10};\; \vec{I_v};\; \texttt{movq \%rax,}\; 0(\%\text{r10})}$$

$$\frac{}{\Phi \vdash \texttt{LABEL}(l) \Rightarrow l\texttt{:}}$$

$$\frac{}{\Phi \vdash \texttt{JUMP}(\texttt{NAME}(l)) \Rightarrow \texttt{jmp } l}$$

## Enunciados: CJUMP e RETURN

$$\frac{\Phi \vdash e \Rightarrow \vec{I}}
      {\Phi \vdash \texttt{CJUMP}(e,\, l_t,\, l_f) \Rightarrow
       \vec{I};\;
       \texttt{testq \%rax, \%rax};\;
       \texttt{jne } l_t;\;
       \texttt{jmp } l_f}$$

$$\frac{}{\Phi \vdash \texttt{RETURN}([]) \Rightarrow \mathit{epilogue}}$$

$$\frac{\Phi \vdash e \Rightarrow \vec{I}}
      {\Phi \vdash \texttt{RETURN}([e]) \Rightarrow \vec{I};\; \mathit{epilogue}}$$

O epílogo restaura os registradores callee-saved e o `%rbp` e executa `retq`.
O resultado fica em `%rax` (o registrador padrão de retorno da ABI).

# Alinhamento de Pilha em Chamadas

## O Problema

O ABI System V AMD64 exige que RSP seja **16-byte alinhado** no momento do
`callq`. A instrução `callq` em si empilha 8 bytes (o endereço de retorno),
então na entrada da função callee RSP é múltiplo de 8 mas não de 16.

**Fontes de desalinhamento**:

1. Registradores callee-saved empilhados no prólogo ($N \times 8$ bytes)
2. `subq $F, %rsp` do prólogo (slots de spill)
3. `pushq` de registradores caller-saved antes de `callq` aninhado
4. `pushq %rax` do BINOP para salvar $e_1$ durante a compilação de $e_2$

O gerador de código precisa rastrear o estado do alinhamento para inserir
um `subq $8, %rsp` de padding quando necessário.

## Monada de Geração de Código

```haskell
data MState = MState [Instr] Int
--                           ↑ extraDepth: bytes de pushq não-prologue
type X86M = State MState

emit :: Instr -> X86M ()
emit i = modify (\(MState is d) -> MState (i : is) d)

pushScratch :: Reg -> X86M ()
pushScratch r = do
  emit (Pushq (Reg r))
  modify (\(MState is d) -> MState is (d + 8))

popScratch :: Reg -> X86M ()
popScratch r = do
  emit (Popq (Reg r))
  modify (\(MState is d) -> MState is (d - 8))
```

`extraDepth` rastreia bytes acumulados por `pushScratch` (BINOPs e
caller-saved saves) mas **não** conta os pushes do prólogo (já incluídos
em `frameAdj`).

## Cálculo de Padding em CALL

```haskell
compileCall :: Env -> String -> [Expr] -> X86M ()
compileCall env f args = do
  extra <- getExtraDepth
  let saved  = envCSRegs env       -- caller-saved regs em uso
      nSaved = length saved
      needPad = (extra + 8 * nSaved) `mod` 16 /= 0
  mapM_ (emit . Pushq . Reg) saved
  when needPad $ emit (Subq (Imm 8) (Reg RSP))
  -- avalia cada argumento → %rax → registrador ABI
  mapM_ (uncurry loadArg) (zip args argRegs)
  emit (Xorq (Reg RAX) (Reg RAX))  -- %eax = 0 para funções variádicas
  emit (Callq f)
  when needPad $ emit (Addq (Imm 8) (Reg RSP))
  mapM_ (emit . Popq . Reg) (reverse saved)
```

O padding de 8 bytes é inserido **depois** dos saves de caller-saved para
não interferir com a ordem de restauração.

## Por que `extra + 8 * nSaved`?

Após o prólogo temos RSP = `%rbp − 8N − F`. O `frameAdj` garante que isso
é múltiplo de 16 **quando não há pushes extras**. Cada `pushScratch` no
BINOP acumula mais 8 bytes (`extraDepth`). Antes de cada `callq`, os
`nSaved` registers caller-saved são empilhados (mais `8 * nSaved` bytes).

O estado de RSP nesse ponto está deslocado em:

$$\Delta = \mathit{extra} + 8 \cdot n_{\mathit{saved}} \pmod{16}$$

Se $\Delta \neq 0$, adicionamos 8 bytes de padding para realinhar.

# Implementação: IRToX86

## Estrutura do Módulo

```haskell
data Env = Env
  { envCol    :: Coloring   -- temporário → registrador ou slot
  , envCSaved :: [Reg]      -- callee-saved usados (para o epílogo)
  , envFAdj   :: Int        -- valor F do subq no prólogo
  , envCSRegs :: [Reg]      -- caller-saved do pool em uso (salvos em CALLs)
  }

compileFunc :: FuncDef -> [Instr]
compileFunc fd =
  let body0             = canonicalize (funcBody fd)
      (col, spillBytes) = colorFunc (funcParams fd) body0
      csSaved           = calleeSavedInCol col
      fAdj              = frameAdj (length csSaved) spillBytes
      csRegs            = callerSavedInCol col
      env               = Env col csSaved fAdj csRegs
      stmts             = linearize body0
      body              = run (mapM_ (compileStmt env) stmts)
  in Dir "" :
     Dir (".globl " ++ funcName fd) :
     GlobLabel (funcName fd) :
     prologue csSaved fAdj ++
     loadParams (funcParams fd) col ++
     body ++
     epilogue env  -- caminho de fallthrough (código morto se toda saída tem RETURN)
```

## Prólogo e Epílogo

```haskell
prologue :: [Reg] -> Int -> [Instr]
prologue csSaved fAdj =
  [ Pushq (Reg RBP)
  , Movq  (Reg RSP) (Reg RBP)
  ]
  ++ map (Pushq . Reg) csSaved
  ++ [Subq (Imm fAdj) (Reg RSP) | fAdj > 0]

epilogue :: Env -> [Instr]
epilogue env =
  [Addq (Imm (envFAdj env)) (Reg RSP) | envFAdj env > 0]
  ++ map (Popq . Reg) (reverse (envCSaved env))
  ++ [Popq (Reg RBP), Retq]
```

Os registradores callee-saved são desempilhados em **ordem inversa** ao
empilhamento — a pilha é LIFO.

## Carregamento de Parâmetros

```haskell
loadParams :: [Temp] -> Coloring -> [Instr]
loadParams params col = concat $ zipWith load params argRegs
  where
    load t r = case Map.lookup t col of
      Just (InReg dr) | dr /= r -> [Movq (Reg r) (Reg dr)]
      Just (InReg _)             -> []     -- já no registrador correto
      Just (InMem off)           -> [Movq (Reg r) (Mem off RBP)]
      Nothing                    -> []     -- parâmetro não utilizado
```

O coloridor pode atribuir a um parâmetro `t` o mesmo registrador ABI `r`
que ele já ocupa — nesse caso nenhum `movq` é necessário.

## Expressões em Haskell

```haskell
compileExpr :: Env -> Expr -> X86M ()
compileExpr _   (CONST n)  = emit (Movq (Imm n) (Reg scratchAcc))
compileExpr env (TEMP t)   = loadTemp t (envCol env)
compileExpr env (BINOP op e1 e2) = do
  compileExpr env e1
  pushScratch scratchAcc          -- salva e1; sobrevive a qualquer callq em e2
  compileExpr env e2              -- %rax = e2
  popScratch  scratchBinop        -- %r11 = e1
  compileBinOp op
compileExpr env (MEM e) = do
  compileExpr env e
  emit (Movq (Mem 0 scratchAcc) (Reg scratchAcc))
compileExpr env (CALL (NAME f) args) = compileCall env f args
compileExpr env (ESEQ s e) = do
  compileStmt env s
  compileExpr env e
```

## Enunciados em Haskell

```haskell
compileStmt :: Env -> Stmt -> X86M ()
compileStmt env (MOVE (TEMP t) e) = do
  compileExpr env e
  storeTemp t (envCol env)
compileStmt env (MOVE (MEM addrE) valE) = do
  compileExpr env addrE
  emit (Movq (Reg scratchAcc) (Reg scratchMem))
  compileExpr env valE
  emit (Movq (Reg scratchAcc) (Mem 0 scratchMem))
compileStmt _   (LABEL l)           = emit (LocLabel l)
compileStmt _   (JUMP (NAME l))     = emit (Jmp l)
compileStmt env (CJUMP cond lt lf)  = do
  compileExpr env cond
  emit (Testq (Reg scratchAcc) (Reg scratchAcc))
  emit (Jcc NE lt)
  emit (Jmp lf)
compileStmt env (RETURN [])    = mapM_ emit (epilogue env)
compileStmt env (RETURN (e:_)) = do
  compileExpr env e
  mapM_ emit (epilogue env)
```

# Pipeline Completo

## Visão Geral do Pipeline TImp → X86-64

```
factorial.timp
     │  lexer + parser
     ▼
   TImpAST
     │  type-checker
     ▼
   TImpAST (anotado)
     │  compileTImp  (TImpCodegen)
     ▼
   [FuncDef]  (IRT)
     │  canonicalize
     ▼
   [FuncDef]  (IRT canônica)
     │  colorFunc  ───── liveness ──── buildIGraph ──── simplify / selectColors
     ▼
   Coloring + spillBytes
     │  compileFunc  (IRToX86)
     ▼
   X86Program
     │  pretty
     ▼
factorial.s  →  gcc → factorial  →  ./factorial
```

## Exemplo de Saída: `factorial`

Dado `factorial.timp`:

```pascal
function factorial(n : int) : int {
  if n == 0 then return 1
  else return n * factorial(n - 1)
}
function main() : void {
  print(factorial(read_int()))
}
```

O compilador gera (trecho de `factorial.s`):

```asm
factorial:
    pushq  %rbp
    movq   %rsp, %rbp
    pushq  %rbx
    subq   $8, %rsp
    movq   %rdi, %rbx        # n ← arg (%rdi)
    movq   %rbx, %rax
    pushq  %rax              # salva n para o BINOP MUL
    movq   $0, %rax
    popq   %r11              # %r11 = n
    cmpq   %rax, %r11        # n - 0
    sete   %al
    movzbq %al, %rax
    testq  %rax, %rax
    jne    .L_if_true_0
    jmp    .L_if_false_1
.L_if_true_0:
    movq   $1, %rax
    addq   $8, %rsp
    popq   %rbx
    popq   %rbp
    retq
.L_if_false_1:
    ...
    callq  factorial
    ...
    retq
```

## Como Executar

```bash
# Compilar para X86-64
cabal run timp -- --x86 --file examples/factorial.timp

# Montar e linkar com gcc
gcc -o factorial examples/factorial.s -no-pie

# Executar
echo 10 | ./factorial   # deve imprimir 3628800
```

# Comparação de Back-Ends

## TImp → C vs. WAT vs. X86-64

| Aspecto                        | Back-end C         | Back-end WAT           | Back-end X86-64         |
|--------------------------------|--------------------|------------------------|-------------------------|
| **Alocação de registradores**  | feita pelo compilador C | máquina de pilha: WAT gerencia | grafo de coloração: fazemos |
| **Controle de memória**        | malloc/free via C  | linear memory + `i32.load/store` | stack frame + malloc    |
| **Chamadas de função**         | ABI do compilador C | call stack do WAT      | System V AMD64 ABI      |
| **Portabilidade**              | qualquer plataforma | qualquer browser/WASI  | apenas x86-64 Linux     |
| **Esforço de implementação**   | baixo               | médio                  | alto                    |
| **Desempenho potencial**       | depende do C        | depende do runtime WAT | controle total          |
| **Depuração**                  | fácil (código legível) | ferramentas WAT      | assembly (objdump, gdb) |

## Lições Aprendidas

**Back-end C** é ideal para prototipagem: o compilador C faz o trabalho pesado
de alocação de registradores e ABI. O custo é a dependência de uma ferramenta
externa.

**Back-end WAT** é natural para linguagens funcionais com coleta de lixo.
A máquina de pilha simplifica a geração de código, mas requer lidar com as
peculiaridades do modelo de memória WebAssembly.

**Back-end X86-64** dá controle total e fecha o ciclo completo de um compilador:
nenhuma ferramenta de back-end é necessária além do `gcc` para linkar com libc.
O preço é implementar liveness, interferência e coloração de grafo.

# Resumo

## Pipeline de Três Fases

| Capítulo | Fase              | Conceito central             |
|----------|-------------------|------------------------------|
| Cap. 25  | Canonicalização   | Eliminar ESEQ; hoist stmts   |
| Cap. 26  | Alocação          | Vivacidade → grafo → coloração |
| Cap. 27  | Seleção           | IRT → X86-64; alinhamento de pilha |

## Invariantes do Gerador

1. **Resultado de expressão sempre em `%rax`** — regras de compilação garantem isso.
2. **RSP 16-alinhado antes de todo `callq`** — `frameAdj` + padding dinâmico.
3. **Registradores callee-saved preservados** — push no prólogo, pop no epílogo.
4. **Temporários não interferentes compartilham registradores** — coloração correta.
5. **Parâmetros com arestas mútuas** — evita conflito de ABI na entrada.

## Fim do Curso

Com este capítulo, o compilador `TImp` cobre:

- **Análise léxica** e **análise sintática** (Caps. 1–10)
- **Análise semântica** e **verificação de tipos** (Caps. 11–15)
- **Interpretação** e **geração de IR** (Caps. 16–20)
- **Geração de código** para C, WebAssembly e X86-64 (Caps. 21–27)
