---
title: "Geração de Código X86-64 — Parte II: Análise de Vivacidade e Alocação de Registradores"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Definir formalmente **vivacidade** (*liveness*) de temporários e apresentar
  as equações de ponto fixo que a computam.

- Construir o **grafo de interferência** a partir da análise de vivacidade.

- Apresentar o algoritmo de **coloração de grafo de Kempe** para alocação de
  registradores, incluindo simplificação, derramamento e seleção de cores.

- Implementar os módulos `Liveness`, `IGraph` e `GraphColor` em Haskell,
  verificando cada passo com o exemplo de `factorial`.

# Vivacidade

## Motivação

Dado que o hardware possui um número fixo de registradores físicos, o
compilador precisa decidir **quais temporários colocam nos registradores e
quais vão para a pilha** (derramamento — *spilling*).

Dois temporários podem ocupar o **mesmo registrador** se e somente se eles
**nunca estão ambos vivos ao mesmo tempo**.

> Um temporário $t$ é **vivo** no ponto $p$ se existe algum caminho de $p$
> até um uso de $t$ que não passa por nenhuma definição de $t$.

## Equações de Vivacidade

Dado o CFG linearizado com instruções $s_0, s_1, \ldots, s_{n-1}$, definimos:

$$\mathit{use}[i] = \text{temporários lidos por } s_i$$
$$\mathit{def}[i] = \text{temporários escritos por } s_i$$

As equações de **análise retroativa** (*backward dataflow*) são:

$$\mathit{live\_out}[i] = \bigcup_{j \in \mathit{succs}(i)} \mathit{live\_in}[j]$$

$$\mathit{live\_in}[i] = \mathit{use}[i] \cup (\mathit{live\_out}[i] \setminus \mathit{def}[i])$$

O ponto fixo é a **menor solução** (partindo de $\mathit{live\_in}[i] = \emptyset$
e iterando até estabilizar).

## Use e Def para Instruções IRT

| Instrução                  | $\mathit{use}[i]$             | $\mathit{def}[i]$ |
|----------------------------|-------------------------------|-------------------|
| `MOVE(TEMP t, e)`          | $\mathit{temps}(e)$           | $\{t\}$           |
| `MOVE(MEM\, addr, val)`    | $\mathit{temps}(addr) \cup \mathit{temps}(val)$ | $\emptyset$ |
| `EXP e`                    | $\mathit{temps}(e)$           | $\emptyset$        |
| `CJUMP e _ _`              | $\mathit{temps}(e)$           | $\emptyset$        |
| `JUMP e`                   | $\mathit{temps}(e)$           | $\emptyset$        |
| `RETURN [e]`               | $\mathit{temps}(e)$           | $\emptyset$        |
| `LABEL _`                  | $\emptyset$                   | $\emptyset$        |

Onde $\mathit{temps}(e)$ coleta recursivamente todos os `TEMP` em $e$.

## Implementação: Use e Def

```haskell
freeTempsExpr :: Expr -> Set Temp
freeTempsExpr (TEMP t)        = Set.singleton t
freeTempsExpr (BINOP _ e1 e2) = freeTempsExpr e1 `Set.union` freeTempsExpr e2
freeTempsExpr (MEM e)         = freeTempsExpr e
freeTempsExpr (CALL ef args)  = Set.unions (map freeTempsExpr (ef : args))
freeTempsExpr (ESEQ s e)      = useTemp s `Set.union` freeTempsExpr e
freeTempsExpr _               = Set.empty  -- CONST, NAME

useTemp :: Stmt -> Set Temp
useTemp (MOVE (TEMP _)   e)   = freeTempsExpr e
useTemp (MOVE dst        src) = freeTempsExpr dst `Set.union` freeTempsExpr src
useTemp (EXP e)               = freeTempsExpr e
useTemp (RETURN es)           = Set.unions (map freeTempsExpr es)
useTemp (CJUMP e _ _)         = freeTempsExpr e
useTemp _                     = Set.empty

defTemp :: Stmt -> Set Temp
defTemp (MOVE (TEMP t) _) = Set.singleton t
defTemp _                 = Set.empty
```

## Implementação: Ponto Fixo

```haskell
type LiveMap = Map Int (Set Temp)  -- live_in[i]

liveness :: FuncCFG -> LiveMap
liveness cfg = fixpoint initMap
  where
    idxs    = reverse (cfgIndices cfg)  -- ordem retroativa
    initMap = Map.fromList [(i, Set.empty) | i <- cfgIndices cfg]

    fixpoint m =
      let m' = foldl step m idxs
      in if m' == m then m else fixpoint m'

    step acc i =
      let lo    = Set.unions [acc Map.! j | j <- succs cfg i]
          newIn = useTemp (cfgStmtAt cfg i)
                  `Set.union`
                  (lo `Set.difference` defTemp (cfgStmtAt cfg i))
      in Map.insert i newIn acc
```

Iterar em **ordem reversa** dentro de cada passagem acelera a convergência:
informação flui "para trás" e cada passo já aproveita o que foi computado
pelos sucessores na mesma iteração (ordem de Gauss-Seidel).

## Exemplo: Vivacidade em `factorial`

Trecho da IRT após canonicalização (simplificado):

```
0: MOVE(TEMP n,  TEMP arg)
1: MOVE(TEMP t0, BINOP(EQ, TEMP n, CONST 0))
2: CJUMP(TEMP t0, .true, .false)
3: .true:   RETURN [CONST 1]
4: .false:  MOVE(TEMP t1, BINOP(SUB, TEMP n, CONST 1))
5: MOVE(TEMP r,  CALL(factorial, [TEMP t1]))
6: MOVE(TEMP t2, BINOP(MUL, TEMP n, TEMP r))
7: RETURN [TEMP t2]
```

| $i$ | instrução              | $\mathit{use}$ | $\mathit{def}$ | $\mathit{live\_in}$ |
|-----|------------------------|----------------|----------------|---------------------|
| 7   | RETURN t2              | {t2}           | ∅              | {t2}                |
| 6   | t2 = n * r             | {n, r}         | {t2}           | {n, r}              |
| 5   | r = factorial(t1)      | {t1}           | {r}            | {t1, n}             |
| 4   | t1 = n − 1             | {n}            | {t1}           | {n}                 |
| 3   | RETURN 1               | ∅              | ∅              | ∅                   |
| 2   | CJUMP t0               | {t0}           | ∅              | {t0, n}             |
| 1   | t0 = (n == 0)          | {n}            | {t0}           | {n}                 |
| 0   | n = arg                | {arg}          | {n}            | {arg}               |

Observe que `n` é viva do índice 0 até o índice 6: ela interfere com
qualquer temporário definido e vivo durante esse intervalo.

# Grafo de Interferência

## Definição Formal

O **grafo de interferência** $G = (V, E)$ tem:

- $V$ = conjunto de todos os temporários do programa
- $(t, u) \in E$ se e somente se $t \neq u$ e existe uma instrução $i$ tal
  que $t \in \mathit{def}[i]$ e $u \in \mathit{live\_out}[i]$

Dois temporários com uma aresta **não podem receber o mesmo registrador**.

### Regra de construção

$$\frac{t \in \mathit{def}[i] \quad u \in \mathit{live\_out}[i] \quad t \neq u}
      {(t, u) \in E}$$

Executamos esta regra para todo $i$ e todo par $(t, u)$ aplicável.

## Parâmetros com Interferência Mútua

Os **parâmetros formais** de uma função chegam já carregados em registradores
distintos da ABI (`%rdi`, `%rsi`, …). Portanto eles são **todos vivos
simultaneamente** no ponto de entrada — mesmo que a análise de vivacidade
não os veja em nenhum $\mathit{live\_in}[i]$ (se não houver usos explícitos).

**Solução**: antes de iniciar a coloração, adicionamos arestas entre todos
os pares de parâmetros:

$$\forall\, p_1, p_2 \in \mathit{params},\; p_1 \neq p_2 \implies (p_1, p_2) \in E$$

Sem isso, dois parâmetros distintos podem receber o mesmo registrador —
um bug silencioso que causa resultados errados.

## Implementação: Estrutura do Grafo

```haskell
data IGraph = IGraph
  { igAdj :: Map Temp (Set Temp)  -- lista de adjacência simétrica
  , igDeg :: Map Temp Int          -- cache de graus
  }

addEdge :: Temp -> Temp -> IGraph -> IGraph
addEdge t u g
  | t == u    = addNode t g          -- auto-laço: só garante presença
  | u `Set.member` neighbors t g' = g'  -- aresta já existe
  | otherwise = g'
      { igAdj = Map.adjust (Set.insert u) t
              $ Map.adjust (Set.insert t) u
              $ igAdj g'
      , igDeg = Map.adjust (+1) t
              $ Map.adjust (+1) u
              $ igDeg g'
      }
  where g' = addNode u (addNode t g)
```

O cache `igDeg` evita recomputation do grau a cada passo da simplificação.

## Implementação: Construção do Grafo

```haskell
buildIGraph :: FuncCFG -> LiveMap -> IGraph
buildIGraph cfg liveIn =
  let allTemps =
        Set.unions (Map.elems liveIn)
        `Set.union`
        Set.unions [defTemp (cfgStmtAt cfg i) | i <- cfgIndices cfg]
      g0 = Set.foldl' (flip addNode) emptyIGraph allTemps
  in foldl' addInstr g0 (cfgIndices cfg)
  where
    addInstr g i =
      let tSet = defTemp (cfgStmtAt cfg i)
          out  = liveOut cfg liveIn i
      in if Set.null tSet then g
         else Set.foldl' (\g' u -> addEdge (Set.findMin tSet) u g') g out
```

# Alocação por Coloração de Grafo

## O Problema de k-Coloração

Dados $k$ registradores disponíveis (o **pool de alocação**), o problema é:

> Atribuir a cada temporário uma cor (= registrador) tal que temporários
> adjacentes no grafo de interferência recebam cores distintas.

Se não for possível colorir algum nó, ele é **derramado** (*spilled*):
seu valor é armazenado na pilha em vez de um registrador.

### Pool de alocação (k = 10)

```
%rbx  %rcx  %rsi  %rdi  %r8  %r9  %r12  %r13  %r14  %r15
```

Registradores **excluídos** do pool (uso reservado pelo gerador):

| Registrador | Papel                                       |
|-------------|---------------------------------------------|
| `%rax`      | Acumulador de expressões / retorno          |
| `%rdx`      | Extensão de sinal (`cqo`) / resto (`idivq`) |
| `%r10`      | Scratch de endereço em `MOVE(MEM,_)`        |
| `%r11`      | Scratch do primeiro operando em `BINOP`     |
| `%rbp`      | Ponteiro de frame                           |
| `%rsp`      | Ponteiro de pilha                           |

## Algoritmo de Kempe

O algoritmo opera em três fases:

1. **Simplificação**: remove nós de grau $< k$ do grafo empilhando-os.
2. **Derramamento potencial**: se não há nó de grau $< k$, escolhe um
   candidato a derramar e o remove (marcando-o).
3. **Seleção**: desempilha os nós e atribui a menor cor disponível.
   Se um candidato a derramamento não conseguir cor, ele é de fato derramado.

### Propriedade chave

Se $G$ tem algum nó $t$ com $\mathit{grau}(t) < k$, então $G$ pode ser
$k$-colorido se e somente se $G \setminus \{t\}$ pode. Portanto podemos
**simplificar com segurança** qualquer nó de grau $< k$.

## Fase 1: Simplificação

$$\frac{\mathit{grau}(t, G) < k}
      {G \xrightarrow{\mathit{push}(t)} G \setminus \{t\}}$$

$$\frac{\forall t.\; \mathit{grau}(t, G) \geq k \quad t = \mathit{spill}(G)}
      {G \xrightarrow{\mathit{spill}(t)} G \setminus \{t\}}$$

**Heurística de derramamento**: derrama o temporário com o **maior intervalo
de vivacidade** — ele exerce mais pressão sobre o pool durante mais instruções.

```haskell
simplify :: IGraph -> IntervalMap -> ([Temp], Set Temp)
simplify ig0 ivm = go ig0 [] Set.empty (Set.toList (nodes ig0))
  where
    go _  stk spills []  = (stk, spills)
    go ig stk spills wl  =
      case findLow ig wl of
        Just t  -> go (removeNode t ig) (t : stk) spills (filter (/= t) wl)
        Nothing ->
          let t = maximumBy (comparing (\t' -> maybe 0 ivLen (Map.lookup t' ivm))) wl
          in  go (removeNode t ig) (t : stk) (Set.insert t spills) (filter (/= t) wl)

findLow :: IGraph -> [Temp] -> Maybe Temp
findLow ig = listToMaybe . filter (\t -> degree t ig < k)
```

## Fase 2: Seleção de Cores

Após o empilhamento, desempilhamos e atribuímos cores:

$$\frac{t \text{ topo da pilha} \quad C_{\mathit{usadas}} = \{c \mid (t,u) \in E_{\mathit{orig}},\; \mathit{cor}(u) = c\}
       \quad c^* = \min(\mathit{Pool} \setminus C_{\mathit{usadas}})}
      {t \mapsto c^*}$$

Se $\mathit{Pool} \setminus C_{\mathit{usadas}} = \emptyset$: $t$ é derramado
em memória (slot $= -8, -16, \ldots$ em relação a `%rbp`).

**Preferência de cores**: registradores callee-saved primeiro (`%rbx`, `%r12`–`%r15`).
Motivo: temporários vivos entre chamadas não precisam ser salvos e restaurados
antes de cada `callq`.

```haskell
preferOrder :: [Reg]
preferOrder = Set.toList calleeSaved ++
              filter (`Set.notMember` calleeSaved) allocPool
```

## Implementação: Seleção

```haskell
selectColors :: [Temp] -> Set Temp -> IGraph -> Int -> (Coloring, Int)
selectColors stack _potSpills origGraph startSlot =
  foldl' step (Map.empty, startSlot) stack
  where
    step (col, nextSlot) t =
      let used  = Set.fromList
                    [ r | u <- Set.toList (neighbors t origGraph)
                        , Just (InReg r) <- [Map.lookup u col] ]
          avail = filter (`Set.notMember` used) preferOrder
      in case avail of
           (r : _) -> (Map.insert t (InReg r)       col, nextSlot)
           []      -> (Map.insert t (InMem nextSlot) col, nextSlot - 8)
```

A fase de seleção usa o **grafo original** (antes das remoções da simplificação)
para consultar os vizinhos: as remoções são apenas um dispositivo algorítmico
para determinar a ordem de coloração.

## Intervalos de Vivacidade

O **intervalo** de um temporário $t$ é o par $[\mathit{start}, \mathit{end}]$
onde:

- $\mathit{start}$ = menor índice onde $t \in \mathit{live\_in}[i]$ ou $t \in \mathit{def}[i]$
- $\mathit{end}$   = maior índice onde $t \in \mathit{live\_in}[i]$ ou $t \in \mathit{live\_out}[i]$

O comprimento $\mathit{end} - \mathit{start}$ é a heurística de derramamento.

```haskell
data Interval = Interval
  { ivTemp  :: Temp
  , ivStart :: Int
  , ivEnd   :: Int
  }

ivLen :: Interval -> Int
ivLen iv = ivEnd iv - ivStart iv
```

## Entrada Principal: `colorFunc`

```haskell
colorFunc :: [Temp] -> Stmt -> (Coloring, Int)
colorFunc params body =
  let cfg        = buildCFG body
      livm       = liveness cfg
      ivm        = buildIntervalMap cfg livm
      ig0        = buildIGraph cfg livm
      ig         = addParamEdges params ig0
      (stack, potSpills) = simplify ig ivm
      (col, nextSlot)    = selectColors stack potSpills ig (-8)
      spillBytes         = negate nextSlot - 8
  in (col, spillBytes)
  where
    addParamEdges ps g =
      foldr (\(p1, p2) acc -> addEdge p1 p2 acc) g
            [(p1, p2) | p1 <- ps, p2 <- ps, p1 /= p2]
```

`spillBytes` = espaço total em bytes a reservar na pilha para temporários
derramados (0 se não houver derramamento).

# Layout de Frame e Alinhamento

## Layout do Frame de Ativação

```
     chamador
  ┌────────────────────┐  ← RSP do chamador (16-alinhado antes do callq)
  │ endereço de retorno│  ← callq empilha 8 bytes
  ├────────────────────┤  ← novo RBP (após pushq %rbp)
  │    RBP antigo      │
  ├────────────────────┤
  │ callee-saved regs  │  N × 8 bytes  (ex: %rbx, %r12, ...)
  ├────────────────────┤
  │ slots de spill     │  spillBytes (múltiplo de 8)
  ├────────────────────┤  ← RSP atual (deve ser 16-alinhado antes de callq)
  │   ...              │
```

## Cálculo de `frameAdj`

O ABI System V AMD64 exige que RSP seja **16-byte alinhado** no momento da
instrução `callq` (que empilha o endereço de retorno de 8 bytes).

Após `pushq %rbp` o RSP está alinhado. Cada `pushq` de callee-saved desloca
8 bytes. Precisamos de $F$ tal que:

$$8N + F \equiv 0 \pmod{16}, \quad F \geq \mathit{spillBytes}$$

```haskell
frameAdj :: Int -> Int -> Int
frameAdj nCallee spillBytes =
  let base     = align16 spillBytes
      total    = 8 * nCallee + base
      misalign = total `mod` 16
  in if misalign == 0 then base else base + (16 - misalign)

align16 :: Int -> Int
align16 n = ((n + 15) `div` 16) * 16
```

Se $F = 0$, a instrução `subq $0, %rsp` é omitida.

# Exemplo Completo: `factorial`

## Grafo de Interferência de `factorial`

Temporários: `arg`, `n`, `t0`, `t1`, `r`, `t2`

| temporário | vivo em índices | intervalo |
|------------|-----------------|-----------|
| `arg`      | {0}             | [0, 0]    |
| `n`        | {0..6}          | [0, 6]    |
| `t0`       | {1, 2}          | [1, 2]    |
| `t1`       | {4, 5}          | [4, 5]    |
| `r`        | {5, 6}          | [5, 6]    |
| `t2`       | {6, 7}          | [6, 7]    |

Arestas pelo critério de interferência:

- $n$ ↔ `t0` (n viva em live_out[1] quando t0 é definido)
- $n$ ↔ `t1` (n viva em live_out[4] quando t1 é definido)
- $n$ ↔ `r`  (n viva em live_out[5] quando r é definido)
- $n$ ↔ `t2` (n viva em live_out[6] quando t2 é definido)

## Coloração de `factorial`

Pool: `%rbx %rcx %rsi %rdi %r8 %r9 %r12 %r13 %r14 %r15` (preferência callee-saved primeiro)

Ordem de simplificação (todos com grau < 10):

`t2` → `r` → `t1` → `t0` → `n` → `arg`

Seleção (desempilhando):

| temporário | vizinhos já coloridos | cor atribuída |
|------------|-----------------------|---------------|
| `arg`      | ∅                     | `%rbx`        |
| `n`        | ∅                     | `%rbx`        |
| `t0`       | {n=%rbx}              | `%rcx`        |
| `t1`       | {n=%rbx}              | `%rcx`        |
| `r`        | {n=%rbx}              | `%rcx`        |
| `t2`       | {n=%rbx}              | `%rcx`        |

`arg` e `n` recebem `%rbx` — mas `arg` só é usada para inicializar `n`
e não interfere com ela no grafo (seus intervalos se tocam apenas na
instrução de definição, não simultaneamente no live_out).

## Resultado: Prólogo e Epílogo

Com `n` em `%rbx` (callee-saved) e k = 1 callee-saved registrador:

```
factorial:
    pushq  %rbp
    movq   %rsp, %rbp
    pushq  %rbx          # salva %rbx (callee-saved)
    subq   $8, %rsp      # frameAdj: 8*1 + 0 = 8, misalign = 8 → +8 → F=8
    movq   %rdi, %rbx    # arg (em %rdi) → n (em %rbx)
    ...
    addq   $8, %rsp
    popq   %rbx
    popq   %rbp
    retq
```

O assembly gerado pelo compilador pode ser inspecionado com:

```bash
cabal run timp -- --x86 --file examples/factorial.timp
```

# Resumo

## O que Aprendemos

| Fase                     | Entrada                    | Saída                        |
|--------------------------|----------------------------|------------------------------|
| Análise de vivacidade    | CFG + use/def por instrução | `LiveMap` (live_in por índice) |
| Grafo de interferência   | CFG + LiveMap              | `IGraph` (nós e arestas)     |
| Intervalos               | CFG + LiveMap              | `IntervalMap` (heurística)   |
| Simplificação (Kempe)    | IGraph + IntervalMap       | Pilha de temporários          |
| Seleção de cores         | Pilha + IGraph original    | `Coloring` (temp → reg/mem)  |
| Layout de frame          | Coloring + spillBytes      | `frameAdj` (subq amount)     |

## Ponto-Chave: Por que Retroativo?

Vivacidade é uma propriedade do **futuro de um ponto de execução**.
Para saber se $t$ é viva antes de $s_i$, precisamos saber se $t$ é
usada depois de $s_i$ — informação que está nos **sucessores** no CFG.
Por isso a análise é retroativa e iteramos de trás para frente.

## Próxima Aula

**Capítulo 27**: Seleção de Instruções — tradução formal de expressões e
enunciados IRT para instruções X86-64, gestão do alinhamento de pilha em
chamadas de função, e o pipeline completo de compilação `TImp → IRT → X86`.
