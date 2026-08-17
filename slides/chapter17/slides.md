---
title: "Geração de Código Intermediário"
subtitle: "BCC328 – Construção de Compiladores I"
header-includes:
  - \usepackage{stmaryrd}
---

# Objetivos

## Objetivos

- Motivar o uso de representações intermediárias no pipeline de compilação e
  apresentar suas propriedades desejáveis.

## Objetivos

- Definir a sintaxe e a semântica operacional big-step da Representação
  Intermediária em Árvore (IRT).

## Objetivos

- Apresentar as regras de tradução dirigida por sintaxe que convertem a AST de
  TWhile e TImp para a IRT.

# Introdução

## O Papel da Representação Intermediária

- Converter a AST diretamente em código de máquina
- Problemas:
  - Código de baixa qualidade
  - Compilador fortemente acoplado à arquitetura

## O Papel da Representação Intermediária

- A **RI** desacopla _front-end_ de _back-end_
- Um _front-end_ pode gerar RI
  - A partir da RI pode-se suportar múltiplas arquiteturas

## Propriedades Desejáveis de uma RI

- **Simplicidade**: $\approx 15$ formas sintáticas (análise e transformação mais
  fáceis)
- **Independência de máquina**: sem detalhes de hardware

## Propriedades Desejáveis de uma RI

- **Independência de linguagem**: múltiplos _front-ends_ compartilham o mesmo
  _back-end_.
- **Suporte a transformações**: facilitar análise de fluxo e otimizações
- **Proximidade do código-alvo**: operações de memória e controle explícitos

# A IRT: Sintaxe

## Expressões da IRT

$$\begin{array}{lcll}
e & ::= & \mathbf{CONST}(n)  \\
  & \mid & \mathbf{TEMP}(t)  \\
  & \mid & \mathbf{NAME}(\ell) \\
  & \mid & \mathbf{BINOP}(\mathit{op}, e_1, e_2) \\
  & \mid & \mathbf{MEM}(e) \\
  & \mid & \mathbf{CALL}(e_f, e_1, \ldots, e_n) \\
  & \mid & \mathbf{ESEQ}(s, e)
\end{array}$$

## Expressões da IRT

- Booleanos: $\mathbf{CONST}(0)$ = falso, $\mathbf{CONST}(1)$ = verdadeiro
- **TEMP**: o alocador de registradores decide se vai para registrador ou pilha

## Comandos da IRT

$$\begin{array}{lcll}
s & ::= & \mathbf{MOVE}(\mathbf{TEMP}(t), e) \\
  & \mid & \mathbf{MOVE}(\mathbf{MEM}(e_a), e) \\
  & \mid & \mathbf{EXP}(e) \\
  & \mid & \mathbf{SEQ}(s_1, s_2) \\
  & \mid & \mathbf{JUMP}(e) \\
  & \mid & \mathbf{CJUMP}(e, \ell_t, \ell_f) \\
  & \mid & \mathbf{LABEL}(\ell) \\
  & \mid & \mathbf{RETURN}(e_1, \ldots, e_n)
\end{array}$$

# Semântica Operacional

## Estado e Valores

O estado da IRT é um par $\sigma = \langle \tau, \mu \rangle$:

- $\tau : \mathit{Temp} \rightharpoonup \mathbb{Z}$
  - Armazenamento de temporários
- $\mu : \mathbb{Z} \rightharpoonup \mathbb{Z}$
  - Memória (endereços → valores)

Todos os valores são inteiros de precisão de máquina.

## Expressões

**Regras para expressões**: $\sigma \vdash e \Downarrow v$:

$$
\begin{array}{c}
  \frac{}{\sigma \vdash \mathbf{CONST}(n) \Downarrow n} \\
  \frac{\sigma.\tau(t) = v}{\sigma \vdash \mathbf{TEMP}(t) \Downarrow v}\\
\end{array}
$$

## Expressões

$$
\begin{array}{c}
   \frac{\sigma \vdash e_1 \Downarrow v_1 \quad \sigma \vdash e_2 \Downarrow v_2}
        {\sigma \vdash \mathbf{BINOP}(\mathit{op}, e_1, e_2) \Downarrow \mathit{op}(v_1, v_2)}
\end{array}
$$

## Comandos

Resultado $r$ de um comando:

- $\langle \sigma', \blacksquare \rangle$: terminação normal
- $\langle \sigma', \uparrow (v_1,\ldots,v_k) \rangle$: retorno de função

## Comandos

$$
  \begin{array}{c}
  \frac{\sigma \vdash e \Downarrow v \quad \sigma' = \langle \tau[t \mapsto v], \mu \rangle}
       {P, \sigma \vdash \mathbf{MOVE}(\mathbf{TEMP}(t), e) \Downarrow \langle \sigma', \blacksquare \rangle}
  \end{array}
$$

## Comandos

$$
  \begin{array}{c}
    \frac{P, \sigma \vdash s_1 \Downarrow \langle \sigma', \blacksquare \rangle \quad P, \sigma' \vdash s_2 \Downarrow \langle \sigma'', r \rangle}{P, \sigma \vdash \mathbf{SEQ}(s_1, s_2) \Downarrow \langle \sigma'', r \rangle}
  \end{array}
$$

- Se $s_1$ retorna, $s_2$ **não é executado** (retorno propaga).

# Tradução Dirigida por Sintaxe

## Expressões

- Literais e variáveis

$$\mathcal{E}\lbrack \mathtt{false} \rbrack = \mathbf{CONST}(0) \qquad \mathcal{E}\lbrack \mathtt{true} \rbrack = \mathbf{CONST}(1)$$

$$\mathcal{E}\lbrack n \rbrack = \mathbf{CONST}(n) \qquad \mathcal{E}\lbrack x \rbrack = \mathbf{TEMP}(x)$$

## Expressões

- Operações:

$$\mathcal{E}\lbrack e_1 \oplus e_2 \rbrack = \mathbf{BINOP}(\widehat{\oplus},\; \mathcal{E}\lbrack e_1 \rbrack,\; \mathcal{E}\lbrack e_2 \rbrack)$$

## Expressões

| TWhile | IRT | TWhile | IRT |
| ------ | --- | ------ | --- |
| `+`    | ADD | `==`   | EQ  |
| `-`    | SUB | `<`    | LT  |
| `*`    | MUL | `&&`   | AND |

## Comandos

- Declaração:

$$\begin{array}{c}
   \mathcal{S}\lbrack \mathbf{var}\ x : T = e \rbrack = \mathbf{MOVE}(\mathbf{TEMP}(x),\; \mathcal{E}\lbrack e \rbrack)
\end{array}$$

## Comandos

- Atribuição:

$$\begin{array}{c}
   \mathcal{S}\lbrack x := e \rbrack = \mathbf{MOVE}(\mathbf{TEMP}(x),\; \mathcal{E}\lbrack e \rbrack)
\end{array}$$

## Comandos

- Condicional:

$$\mathcal{S}\lbrack \mathbf{if}\ e\ \mathbf{then}\ b_1\ \mathbf{else}\ b_2 \rbrack =$$

$$\mathbf{SEQ}(\mathbf{CJUMP}(\mathcal{E}\lbrack e \rbrack, \ell_t, \ell_f),\; \mathbf{SEQ}(\mathbf{LABEL}(\ell_t),\; \ldots))$$

## Comandos

- While:

$$\mathcal{S}\lbrack \mathbf{while}\ e\ \mathbf{do}\ B \rbrack =$$

```
LABEL(loop_head)
CJUMP(E[[e]], loop_body, loop_exit)
LABEL(loop_body)
  S[[B]]
JUMP(NAME(loop_head))
LABEL(loop_exit)
```

- $\ell_h$ = cabeça; $\ell_b$ = corpo; $\ell_f$ = saída
- A condição é reavaliada a cada iteração

## Implementação: A Mônada CgM

```haskell
data CgState = CgState
  { freshCounter :: Int
  , emitted      :: [Stmt]
  }

type CgM = StateT CgState (ExceptT String Identity)

freshLabel :: String -> CgM Label
freshLabel prefix = do
    n <- gets freshCounter
    modify (\s -> s { freshCounter = n + 1 })
    return (prefix ++ "_" ++ show n)

emit :: Stmt -> CgM ()
emit s = modify (\st -> st { emitted = emitted st ++ [s] })
```

## Compilando While

```haskell
compileTWhile :: [Stmt] -> CgM ()
compileTWhile stmts = mapM_ compileStmt stmts

compileStmt (SWhile cond body) = do
    lHead <- freshLabel "loop_head"
    lBody <- freshLabel "loop_body"
    lExit <- freshLabel "loop_exit"
    emit (LABEL lHead)
    cExpr <- compileExp cond
    emit (CJUMP cExpr lBody lExit)
    emit (LABEL lBody)
    mapM_ compileStmt body
    emit (JUMP (NAME lHead))
    emit (LABEL lExit)
```

# Geração de Código para Registros e Funções

## Motivação: TImp

- TImp estende TWhile com:
  - **Tipos registro** (`record Point { x : int; y : int }`)
  - **Declarações de funções** (`fn soma(p : Point) : int { ... }`)
- A IRT já possui `MEM`, `CALL` e `RETURN` — basta definir as regras de tradução

## Layout de Memória

- Registros são alocados no **heap** como blocos contíguos de palavras de 64
  bits ($w = 8$ bytes)
- Campos numerados pela **ordem de declaração**, a partir de 0

## Layout de Memória

$$\begin{array}{l}
   \mathit{addr}(x, i) = \\
   \:\:\:\mathbf{BINOP}(\mathtt{ADD},\; \mathbf{TEMP}(x),\; \mathbf{CONST}(i \cdot w))
\end{array}$$

| Campo | Índice $i$ | Deslocamento |
| ----- | ---------- | ------------ |
| `x`   | 0          | 0 bytes      |
| `y`   | 1          | 8 bytes      |

## Alocação de Registros

- Função embutida `alloc(n)`: aloca $n$ palavras no heap e retorna o endereço
  base
- Implementação via _bump-pointer_:

```haskell
callFunc _ (NAME "alloc") [n] = do
  ptr <- gets heapPtr
  modify (\s -> s { heapPtr = ptr + n * 8 })
  return ptr
```

## Alocação de Registros

- O tipo é apagado: **não há cabeçalho de tipo** no heap
- Distinção de tipo é responsabilidade do sistema de tipos estático

## Construção de Registro

$$
\begin{array}{l}
   \mathcal{E}\lbrack \mathbf{new}\; R\;\{f_0 {=} e_0,
   \ldots, f_{n-1} {=} e_{n-1}\} \rbrack = \\
   \:\:\:\:\:\:\:\mathbf{ESEQ}(s_{\mathit{alloc}},\; \mathbf{TEMP}(t))
\end{array}
$$

## Construção de Registro

$$\begin{array}{l}
  s_{\mathit{alloc}} =
\mathbf{SEQ}(\mathbf{MOVE}(\mathbf{TEMP}(t),\; \\
\:\:\:\:\:\:\:\:\:\:\mathbf{CALL}(\mathbf{NAME}(\texttt{alloc}),\; \mathbf{CONST}(n))),
\end{array}
$$

$$\mathbf{SEQ}(\mathbf{MOVE}(\mathbf{MEM}(\mathit{addr}(t,0)),\; \mathcal{E}\lbrack e_0 \rbrack),$$

$$\quad\cdots\quad \mathbf{MOVE}(\mathbf{MEM}(\mathit{addr}(t,n-1)),\; \mathcal{E}\lbrack e_{n-1} \rbrack)))$$

- $t$ é um novo temporário
- Campos avaliados na **ordem de declaração** de $R$

## Acesso a Campo

**Acesso**: $e$ tem tipo $R$, campo $f$ tem índice $i$:

$$
\begin{array}{l}
   \mathcal{E}\lbrack e.f \rbrack =
    \mathbf{MEM}\!\left(\mathbf{BINOP}\left(
         \begin{array}{c}
            \mathtt{ADD},\\
            \mathcal{E}\lbrack e \rbrack,\\
             \mathbf{CONST}(i \cdot w)\\
          \end{array}
         \right)\right)
\end{array}
$$

## Atribuição a Campo

**Atribuição**:

$$
\begin{array}{l}
   \mathcal{S}\lbrack x.f \mathbin{:=} e \rbrack =\\
      \mathbf{MOVE}\!\left(\begin{array}{c}
       \mathbf{MEM}\!\left(
          \mathbf{BINOP}\left(
            \begin{array}{c}
              \mathtt{ADD},\\
              \mathbf{TEMP}(x),\\
              \mathbf{CONST}(i \cdot w)\\
            \end{array}
            \right)\right),\\
      \mathcal{E}\lbrack e \rbrack
   \end{array}
   \right)
\end{array}
$$

- `TEMP(x)` guarda o **endereço** do registro

## Declarações de Funções

$$\begin{array}{l}
    \mathcal{F}\lbrack \mathbf{fn}\; f(\overline{x_i:\tau_i}):
  \rho\;\{B\} \rbrack =\\
  \:\:\:\:\:\mathtt{FuncDef}\; f\; [x_1,\ldots,x_n]\; (\mathit{foldStmts}(\mathcal{S}\lbrack B \rbrack))
\end{array}$$

## Declarações de Funções

- Parâmetros formais $x_i$ usados diretamente como temporários no corpo
- O interpretador IRT inicializa $\mathbf{TEMP}(x_i) = v_i$ no estado local de
  cada chamada

## Declarações de Funções

- Regras de retorno:

$$\begin{array}{l}
  \mathcal{S}\lbrack \mathbf{return}\; e; \rbrack = \mathbf{RETURN}(\mathcal{E}\lbrack e \rbrack)
\\
\mathcal{S}\lbrack \mathbf{return}; \rbrack = \mathbf{RETURN}()
\end{array}$$

## Modificações

```haskell
data CgState = CgState
  { nextLabel  :: Int
  , nextTemp   :: Int
  , stmtAcc    :: [IR.Stmt]
  , recFields  :: Map Name [Field]   -- campos por tipo R
  , varTypes   :: Map Var Ty         -- tipo de cada variável
  }
```

## Modificações

- `recFields`: calcula o índice $i$ de campo $f$ em tipo $R$
- `varTypes`: necessário para traduzir `EField` e `SFieldAssign` (recupera o
  nome do tipo registro para consultar `recFields`)
- `nextTemp`: gera temporários `_t0`, `_t1`, … sem colidir com variáveis

## Atribuição a Campo

```haskell
codegenStmt (SFieldAssign v f e) = do
  vts <- gets varTypes
  case Map.lookup v vts of
    Just (TRecord rname) -> do
      i   <- fieldIndex rname f
      rhs <- codegenExp e
      let addr = IR.BINOP IR.BAdd (IR.TEMP v)
                   (IR.CONST (i * wordSize))
      emit (IR.MOVE (IR.MEM addr) rhs)
```

## Construção de Registro

```haskell
codegenExp (ENew rname initFields) = do
  Just flds <- Map.lookup rname <$> gets recFields
  let n = length flds
  t <- freshTemp
  fieldVals <- mapM (lookupFieldVal initFields) flds
  let allocStmt  = IR.MOVE (IR.TEMP t)
                     (IR.CALL (IR.NAME "alloc") [IR.CONST n])
      fieldStmts = [ IR.MOVE
                       (IR.MEM (IR.BINOP IR.BAdd
                         (IR.TEMP t) (IR.CONST (i * wordSize)))) v
                   | (i, v) <- zip [0..] fieldVals ]
  pure (IR.ESEQ (foldStmts (allocStmt : fieldStmts)) (IR.TEMP t))
```

## Programa TImp

```
record Point { x : int; y : int; }

fn soma(p : Point) : int {
  return p.x + p.y;
}

var q : Point = new Point { x = 3, y = 4 };
print soma(q);
```

## Exemplo Completo: IRT Gerada

```
func soma(p) {
  RETURN(BINOP(ADD,
    MEM(BINOP(ADD, TEMP(p), CONST(0))),   -- p.x (índice 0)
    MEM(BINOP(ADD, TEMP(p), CONST(8)))))  -- p.y (índice 1)
}
func main() {
  MOVE(TEMP(q),
    ESEQ(
      SEQ(MOVE(TEMP(_t0), CALL(NAME(alloc), CONST(2))),
          SEQ(MOVE(MEM(BINOP(ADD,TEMP(_t0),CONST(0))), CONST(3)),
              MOVE(MEM(BINOP(ADD,TEMP(_t0),CONST(8))), CONST(4)))),
      TEMP(_t0)))
  EXP(CALL(NAME(print), CALL(NAME(soma), TEMP(q))))
}
```

# Conclusão

## Conclusão

- A **IRT** separa expressões (produzem valor) de comandos (produzem efeitos)
- **7 expressões**: CONST, TEMP, NAME, BINOP, MEM, CALL, ESEQ
- **7 comandos**: MOVE, EXP, SEQ, JUMP, CJUMP, LABEL, RETURN

## Conclusão

- Registros: **layout linear** no heap, acesso via `MEM` + deslocamento
- Funções: cada declaração vira um `FuncDef` independente
- A semântica big-step define o estado como par $\langle \tau, \mu \rangle$
- A tradução **dirigida por sintaxe** converte AST na IRT sistematicamente
