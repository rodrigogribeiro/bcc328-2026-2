---
title: "Geração de Código WebAssembly"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar o formato textual WebAssembly (WAT) e o modelo de execução baseado
  em **máquina de pilha**.

- Definir as regras de tradução de expressões e comandos da IRT para instruções
  WAT: $\mathcal{E}\lbrack \cdot \rbrack$ e $\mathcal{S}\lbrack \cdot \rbrack$.

## Objetivos

- Explicar a reconstrução do **controle de fluxo estruturado** de WebAssembly a
  partir dos saltos explícitos da IRT linearizada.

- Descrever o runtime WASI embutido e o pipeline completo de execução.

# Introdução

## WebAssembly como Alvo

$$\text{IRT} \xrightarrow{\text{codegen}} \text{Módulo WAT} \xrightarrow{\texttt{wat2wasm}} \text{Binário Wasm}$$

- **WebAssembly** (Wasm): especificação de máquina virtual com semântica formal
  (W3C)

## WebAssembly como Alvo

- Excelente para fins pedagógicos:
  - Semântica **precisa** e publicada
  - Representação textual (WAT) **legível**
  - Ferramentas: `wabt` (compilar/validar) e `wasmtime` (executar)

## Por que WebAssembly?

- Executável no browser e fora dele (wasmtime, wasmer, WASI)
- Modelo de segurança: **sandbox** + verificação de tipos estática

## Por que WebAssembly?

- Tipo único no nosso subconjunto: **`i32`**.
- Todos os valores da IRT:
  - inteiros, ponteiros, endereços: mapeiam para `i32`

## Por que WebAssembly?

- Gerador produz módulo **auto-contido**: sem módulo de runtime separado

# O Formato WAT

## Estrutura de um Módulo WAT

```wat
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read  (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 4)
  (global $heap_ptr (mut i32) (i32.const 128))
  (func $alloc  ...)
  (func $main   ...)   ;; funções do usuário
  (func $print  ...)   ;; I/O embutido
  (func $read_int ...)
  (export "main"   (func $main))
  (export "_start" (func $main))
)
```

## Detalhe do Módulo

- **WASI**: importa `fd_write` e `fd_read` de `wasi_snapshot_preview1`
- **`(memory (export "memory") 4)`**:
  - 4 páginas × 64 KB = 256 KB (exigido pela WASI)

## Detalhe do Módulo

- **`$heap_ptr = 128`**: endereços 0–127 reservados para buffers de I/O do
  runtime
- **`$print` e `$read_int`**: embutidas como WAT verbatim (sem módulo externo)

## Layout de Memória Linear

| Endereços | Uso                                              |
| --------- | ------------------------------------------------ |
| 0–15      | estrutura `iovec` usada por `fd_write`/`fd_read` |
| 16–31     | slot de retorno `nwritten`/`nread`               |

## Layout de Memória Linear

| Endereços | Uso                                                    |
| --------- | ------------------------------------------------------ |
| 32–63     | buffer de entrada (stdin, 31 bytes úteis + terminador) |
| 64–95     | buffer de saída (stdout)                               |

## Layout de Memória Linear

| Endereços | Uso                                            |
| --------- | ---------------------------------------------- |
| 96–127    | reservado                                      |
| **128+**  | **heap do programa** (`$heap_ptr` inicia aqui) |

## Gramática do Subconjunto WAT

$$\scriptstyle{\begin{array}{lcl}
\mathit{mod} & ::= & \mathtt{(module}\ \vec{\mathit{import}}\ \mathit{mem}?\ \vec{\mathit{global}}\ \vec{\mathit{func}}\ \vec{\mathit{export}}\mathtt{)} \\
\mathit{func} & ::= & \mathtt{(func}\ \$f\ \vec{\mathit{param}}\ \mathit{result}?\ \vec{\mathit{local}}\ \vec{i}\mathtt{)} \\
\end{array}}$$

## Gramática do Subconjunto WAT

$$\begin{array}{lcl}
i & ::= & \mathtt{i32.const}\ n \mid \mathtt{local.get}\ \$x \\
  & \mid & \mathit{binop} \mid \mathtt{i32.load} \mid \mathtt{i32.store} \mid \mathtt{i32.eqz}\\
  & \mid & \mathtt{call}\ \$f \mid \mathtt{drop} \mid \mathtt{return} \mid \mathtt{unreachable}\\
  & \mid & \mathtt{(block}\ \$\ell\ \vec{i}\mathtt{)} \mid \mathtt{(loop}\ \$\ell\ \vec{i}\mathtt{)} \\
  & \mid & \mathtt{(if\ (then\ \vec{i})\ (else\ \vec{i}))} \mid \mathtt{local.set}\ \$x \\
  & \mid & \mathtt{br}\ \$\ell \mid \mathtt{br\_if}\ \$\ell
\end{array}$$

# Semântica Operacional

## Máquina de Pilha

- WebAssembly é uma **máquina de pilha**: instruções consomem do topo e empilham
  resultados.

## Máquina de Pilha

- Estado de uma função: $(\sigma, \mu)$
  - $\sigma = [v_1, \ldots, v_n]$: pilha de operandos (topo à direita)
  - $\mu$: variáveis locais (incluindo parâmetros)
  - $\mathbf{M}$, $\mathbf{G}$: memória linear e globais (estado global)

- Notação: $(\sigma, \mu) \xrightarrow{i} (\sigma', \mu')$

## Regras de Avaliação

$$\frac{}{(\sigma, \mu) \xrightarrow{\mathtt{i32.const}\ n} (\sigma \cdot n,\ \mu)}$$

$$\frac{\mu(\$x) = v}{(\sigma, \mu) \xrightarrow{\mathtt{local.get}\ \$x} (\sigma \cdot v,\ \mu)}$$

## Regras de Avaliação

$$\frac{\sigma = \sigma' \cdot v}{(\sigma, \mu) \xrightarrow{\mathtt{local.set}\ \$x} (\sigma',\ \mu[\$x \mapsto v])}$$

## Regras de Avaliação

$$\frac{\sigma = \sigma' \cdot v_2 \cdot v_1 \quad v = \mathit{eval}(\mathit{op}, v_1, v_2)}{(\sigma, \mu) \xrightarrow{\mathit{binop}} (\sigma' \cdot v,\ \mu)}$$

## Regras de Avaliação

$$\frac{\sigma = \sigma' \cdot a \quad \mathbf{M}[a] = v}{(\sigma, \mu) \xrightarrow{\mathtt{i32.load}} (\sigma' \cdot v,\ \mu)}$$

## Regras de Avaliação

$$\frac{\sigma = \sigma'' \cdot a \cdot v}{(\sigma, \mu) \xrightarrow{\mathtt{i32.store}} (\sigma'',\ \mu)\quad \mathbf{M}[a] \leftarrow v}$$

## Controle de Fluxo Estruturado

- WebAssembly usa controle de fluxo **estruturado** (sem `goto`):

| Construtor       | Comportamento de `br`                        |
| ---------------- | -------------------------------------------- |
| `(block $l ...)` | Salta para o **fim** do bloco (_break_)      |
| `(loop $l ...)`  | Salta para o **início** do laço (_continue_) |

## Controle de Fluxo Estruturado

- WebAssembly usa controle de fluxo **estruturado** (sem `goto`):

| Construtor                   | Comportamento de `br`                             |
| ---------------------------- | ------------------------------------------------- |
| `(if (then ...) (else ...))` | Consome topo; executa ramo verdadeiro se $\neq 0$ |
| `br_if $l`                   | Consome topo; ramifica se $\neq 0$                |

## Padrão Canônico de While em WAT

```wat
(block $exit
  (loop $head
    ;; condição de saída: se deve sair, br_if $exit
    <condição>
    br_if $exit
    ;; corpo do laço
    <corpo>
    br $head         ;; volta ao início
  )
)
```

# Tradução da IRT para WAT

## Estrutura Geral do Módulo

- Dado um programa IRT $P = [f_1, \ldots, f_n]$:

```wat
(module WasiImports
   (memory 4)
   (global $heap_ptr ...)
   ($alloc)
   f1 ... fn 
   (print)
   (read_int)
   Exports)
```

## Estrutura Geral do Módulo

- Módulo **auto-contido**: sem dependência de runtime externo em tempo de
  execução
- `$print` e `$read_int` embutidas como WAT verbatim (`wmRawDecls`)
- Exports incluem `"main"` e `"_start"` (ponto de entrada WASI)

## Alocação de Memória

```wat
(func $alloc (param $n i32) (result i32)
  (local $base i32)
  global.get $heap_ptr
  local.set $base
  global.get $heap_ptr
  local.get $n
  i32.const 8
  i32.mul
  i32.add
  global.set $heap_ptr
  local.get $base
)
```

## Alocação de Memória

- $\mathit{alloc}(n)$: aloca $n$ palavras, retorna endereço base.
  - $O(1)$, sem fragmentação.

## Tradução de Funções

- Seja $f = \mathtt{func}\ \mathit{name}(\vec{p})\ s$ uma definição IRT:

```wat
[f] = (func $name (param $pi i32) r 
                  (local $tj i32)
        [s]
        unreachable)
```

## Tradução de Funções

- $r = \mathtt{(result\ i32)}$ se há algum `RETURN` com valor; $r = \varepsilon$
  caso contrário
- $t_j$: temporários do corpo que não são parâmetros (declarados como `local`)

## Tradução de Funções

- `unreachable` final: necessário para o verificador de tipos WAT quando todos
  os caminhos de controle terminam com `return` explícito

## Tradução de Expressões $\mathcal{E}\lbrack \cdot \rbrack$

$$\mathcal{E}\lbrack \mathbf{CONST}(n) \rbrack = [\mathtt{i32.const}\ n]$$

$$\mathcal{E}\lbrack \mathbf{TEMP}(t) \rbrack = [\mathtt{local.get}\ \$t]$$

$$\mathcal{E}\lbrack \mathbf{BINOP}(\mathit{op}, e_1, e_2) \rbrack = \mathcal{E}\lbrack e_1 \rbrack \cdot \mathcal{E}\lbrack e_2 \rbrack \cdot [\mathit{op}_\mathtt{i32}]$$

$$\mathcal{E}\lbrack \mathbf{MEM}(e) \rbrack = \mathcal{E}\lbrack e \rbrack \cdot [\mathtt{i32.load}]$$

$$\mathcal{E}\lbrack \mathbf{CALL}(\mathbf{NAME}\ f, \vec{e}) \rbrack = \mathcal{E}\lbrack \vec{e} \rbrack \cdot [\mathtt{call}\ \$f]$$

## Tabela de Operadores

| IRT   | WAT         | IRT      | WAT         |
| ----- | ----------- | -------- | ----------- |
| $+$   | `i32.add`   | $\&$     | `i32.and`   |
| $-$   | `i32.sub`   | $\mid$   | `i32.or`    |
| $*$   | `i32.mul`   | $\oplus$ | `i32.xor`   |
| $/s$  | `i32.div_s` | $\ll$    | `i32.shl`   |
| $\%s$ | `i32.rem_s` | $\gg_s$  | `i32.shr_s` |

## Tradução de Comandos $\mathcal{S}\lbrack \cdot \rbrack$

$$\mathcal{S}\lbrack \mathbf{MOVE}(\mathbf{TEMP}\ t, e) \rbrack = \mathcal{E}\lbrack e \rbrack \cdot [\mathtt{local.set}\ \$t]$$

$$\mathcal{S}\lbrack \mathbf{MOVE}(\mathbf{MEM}(a), e) \rbrack = \mathcal{E}\lbrack a \rbrack \cdot \mathcal{E}\lbrack e \rbrack \cdot [\mathtt{i32.store}]$$

## Tradução de Comandos $\mathcal{S}\lbrack \cdot \rbrack$

$$\scriptstyle{\mathcal{S}\lbrack \mathbf{EXP}(\mathbf{CALL}(\mathbf{NAME}\ f, \vec{e})) \rbrack = \mathcal{E}\lbrack \vec{e} \rbrack \cdot [\mathtt{call}\ \$f] \cdot d_f}$$

onde $d_f = [\mathtt{drop}]$ se $f$ retorna valor; $d_f = [\ ]$ caso contrário.

## Tradução de Comandos $\mathcal{S}\lbrack\cdot\rbrack$

$$\mathcal{S}\lbrack \mathbf{RETURN}([e]) \rbrack = \mathcal{E}\lbrack e \rbrack \cdot [\mathtt{return}]$$

$$\mathcal{S}\lbrack \mathbf{RETURN}([\ ]) \rbrack = [\mathtt{return}]$$

# Reconstrução de Fluxo de Controle

## Linearização da IRT

- A IRT representa sequências com `SEQ` (árvore binária).

- O primeiro passo é **linearizar** o corpo:
  - Resulta em: lista $[s_0, \ldots, s_{n-1}]$ + mapa
    $\mathcal{L} : \mathit{Label} \to \mathbb{N}$

## Linearização da IRT

```haskell
linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s           = [s]

buildLabelMap :: [Stmt] -> LabelMap
buildLabelMap stmts =
  Map.fromList [(l, i) | (i, LABEL l) <- zip [0..] stmts]
```

## Reconhecimento de While

- Um laço aparece na sequência linearizada na forma:

$$\scriptscriptstyle{\underbrace{\mathbf{LABEL}\ \ell_h}_{i}\quad \underbrace{\mathbf{CJUMP}(e, \ell_a, \ell_b)}_{i+1}\quad \text{corpo}\quad \underbrace{\mathbf{JUMP}(\mathbf{NAME}\ \ell_h)}_{\text{antes do exit}}\quad \underbrace{\mathbf{LABEL}\ \ell_{\mathit{exit}}}_{\ldots}}$$

- Há duas convenções dependendo de como o front-end gera o CJUMP:

## Duas Convenções de While

- **Convenção A** (TWhile/TImp): $\ell_a = \ell_{\mathit{body}}$ logo após
  CJUMP; $\ell_b = \ell_{\mathit{exit}}$. Condição $e$ é verdadeira quando o
  laço deve **continuar**:

$$\lbrack e \rbrack \cdot [\mathtt{i32.eqz}] \cdot [\mathtt{br\_if}\ \ell_{\mathit{exit}}]$$

## Duas Convenções do While

- **Convenção B** (estilo fatorial): $\ell_b = \ell_{\mathit{body}}$ logo após
  CJUMP; $\ell_a = \ell_{\mathit{exit}}$. Condição $e$ é verdadeira quando o
  laço deve **parar**:

$$\lbrack e \rbrack \cdot [\mathtt{br\_if}\ \ell_{\mathit{exit}}]$$

## Duas Convenções do While

- Em ambos os casos, o código WAT gerado é

```wat
(block $exit (loop $head <check> <corpo> br $head))
```

## Reconhecimento de If/If-Else

- Um condicional aparece na forma:

$$\scriptscriptstyle{\underbrace{\mathbf{CJUMP}(e, \ell_t, \ell_f)}_{i}\quad \underbrace{\mathbf{LABEL}\ \ell_t}_{i+1}\quad \text{ramo then}\quad \underbrace{\mathbf{LABEL}\ \ell_f}_{\ldots}}$$

## Reconhecimento de If/If-Else

- Para if-else: o ramo then termina com $\mathbf{JUMP}(\mathbf{NAME}\ \ell_e)$
  onde $\ell_e$ é o rótulo de saída.

Código gerado:
$$\lbrack e \rbrack \cdot [\mathtt{if}\ (\mathtt{then}\ \lbrack\text{then}\rbrack)\ (\mathtt{else}\ \lbrack\text{else}\rbrack)]$$

# Implementação em Haskell

## WATSyntax: Tipos de Dados

```haskell
data WInstr
  = WI32Const  Int           -- i32.const n
  | WLocalGet  WIdent        -- local.get $x
  | WLocalSet  WIdent        -- local.set $x
  | WI32BinOp  WBinOp        -- i32.<op>
  | WI32Eqz                  -- i32.eqz
  | WI32Load                 -- i32.load
  | WI32Store                -- i32.store
  | WDrop | WReturn | WUnreachable
  | WBlock (Maybe WIdent) [WInstr]
  | WLoop  (Maybe WIdent) [WInstr]
  | WIf    [WInstr] (Maybe [WInstr])
  | WBr WIdent | WBrIf WIdent
  | WCall WIdent
  | WGlobalGet WIdent | WGlobalSet WIdent
```

## Compilação em Três Fases

- **Fase 1 - Linearização**: achatar `SEQ` em lista plana e construir mapa de
  rótulos.

## Compilação em Três Fases

- **Fase 2 - Coleta de temporários**: percorrer o corpo coletando todos os
  `TEMP` e subtrair parâmetros → declarações `local`.

## Compilação em Três Fases

- **Fase 3 - Compilação por faixa**: $[\mathit{from}, \mathit{to})$:
  - `LABEL lh + CJUMP` -> tenta `tryWhile` -> gera `WBlock`/`WLoop`
  - `CJUMP` com rótulos válidos → reconhece condicional → gera `WIf`
  - `JUMP` → ignorado (já consumido nos padrões acima)
  - Qualquer outro → `compileSingleStmt`

# Execução de Programas WebAssembly

## Pipeline Completo de Execução

```bash
# 1. Compilar TImp para IRT
$ cabal run timp -- --ir -f prog.timp   # gera prog.ir

# 2. Compilar IRT para WAT
$ cabal run ir -- --wat prog.ir         # gera prog.wat

# 3. Montar e executar
$ wat2wasm prog.wat -o prog.wasm
$ echo "5" | wasmtime prog.wasm
```

Não é necessário nenhum módulo de runtime separado: `prog.wat` já é
auto-contido.

## Exemplo: Fatorial (IRT)

```text
func fact(n) {
  t0 := 1;
L_head:
  cjump n <= 0 L_done L_body;
L_body:
  t0 := t0 * n;
  n  := n - 1;
  jump L_head;
L_done:
  return t0;
}
```

## Exemplo: Fatorial (WAT gerado)

```wat
(func $fact (param $n i32) (result i32)
  (local $t0 i32)
  i32.const 1
  local.set $t0
  (block $L_done
    (loop $L_head
      local.get $n
      i32.const 0
      i32.le_s
      br_if $L_done    ;; Convenção B: condição de saída direta
      local.get $t0
      local.get $n
      i32.mul
      local.set $t0
      local.get $n
      i32.const 1
      i32.sub
      local.set $n
      br $L_head
    )
  )
  local.get $t0
  return
  unreachable
)
```

## Validação com wasm-validate

Antes de executar, é útil validar o módulo gerado:

```bash
$ wasm-validate prog.wasm
```

- Sem saída → módulo válido
- Erros de tipo são detectados aqui (ex: função com `(result i32)` que não deixa
  valor na pilha)

- O `unreachable` final nas funções que sempre retornam via `return` explícito é
  exigido pelo verificador de tipos WAT.

# Conclusão

## Conclusão

- WebAssembly é uma máquina de **pilha** com tipo único `i32`
- Controle de fluxo **estruturado**: block, loop, if (sem goto)
- Módulo **auto-contido**: importa WASI, emite runtime embutido

## Conclusão

- Regras de tradução $\mathcal{E}$ e $\mathcal{S}$: mapeamento direto IRT $\to$
  WAT
- Duas **convenções de CJUMP** para reconhecimento de laços while
- Pipeline: `timp --ir` → `ir --wat` → `wat2wasm` + `wasmtime`
