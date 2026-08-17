---
title: "Otimizações de Código Intermediário"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Classificar as otimizações de código intermediário por escopo:
  local (intra-bloco), global (inter-bloco) e de laço.

- Definir formalmente e implementar dobramento de constantes, propagação
  de constantes, eliminação de subexpressões comuns (CSE) e eliminação de
  código morto (DCE).

- Apresentar otimizações estruturais de laço: movimentação de código
  invariante (LICM), desenrolamento e fusão.

- Definir formalmente e implementar inlining de funções e eliminação de
  chamadas em cauda (TCO), com suas condições de elegibilidade e correção.

# Introdução

## O que são Otimizações?

- "Otimização" é um exagero: raramente o código é **ótimo** segundo alguma métrica global
- O que se busca: código **melhor** — mais rápido, menor, mais econômico
- Aplicadas sobre a **IRT** sem alterar o significado observável do programa

**Classificação por escopo:**

| Escopo | Descrição | Exemplos |
|---|---|---|
| **Local** (intra-bloco) | Dentro de um bloco básico | Const folding, CSE |
| **Global** (inter-bloco) | Análise de fluxo de controle | Const propagation global |
| **De laço** | Exploram estrutura iterativa | LICM, unrolling, fusion |

## Dez Otimizações Neste Capítulo

1. **Dobramento de constantes** (*constant folding*)
2. **Propagação de constantes** (*constant propagation*)
3. **Dobramento e propagação combinados**
4. **Eliminação de subexpressões comuns** (CSE)
5. **Eliminação de código morto** (DCE)
6. **Movimentação de código invariante de laço** (LICM)
7. **Desenrolamento de laço** (*loop unrolling*)
8. **Fusão de laços** (*loop fusion*)
9. **Inlining de funções** (*function inlining*)
10. **Eliminação de chamadas em cauda** (*tail-call elimination*)

## Terminologia

Uma expressão é **pura** se não produz efeitos colaterais:
$$e \text{ pura} \iff e \in \{\mathbf{CONST}, \mathbf{TEMP}, \mathbf{NAME}\} \text{ ou } e = \mathbf{BINOP}(\mathit{op}, e_1, e_2) \text{ com } e_1, e_2 \text{ puras}$$

- $\mathbf{MEM}$, $\mathbf{CALL}$, $\mathbf{ESEQ}$ **não são puras**
- $\mathit{freeTemps}(e)$ = temporários que ocorrem livres em $e$
- $\mathit{defs}(s)$ = temporários **escritos** por $s$
- $\mathit{uses}(s)$ = temporários **lidos** por $s$

# Dobramento de Constantes

## Definição Formal

$$\mathit{fold}(\mathbf{BINOP}(\mathit{op}, e_1, e_2)) = \begin{cases}
  \mathbf{CONST}(\mathit{op}(n_1, n_2)) & \text{se } e_1' = \mathbf{CONST}(n_1) \text{ e } e_2' = \mathbf{CONST}(n_2) \\
  \mathit{simplify}(\mathit{op}, e_1', e_2') & \text{caso contrário}
\end{cases}$$

**Identidades algébricas** aplicadas por $\mathit{simplify}$:

$$e + 0 = e \qquad e - 0 = e \qquad e \times 0 = 0 \qquad e \times 1 = e$$

**Cuidado**: divisão por zero em compile-time deve ser evitada!

## Exemplo de Dobramento

Antes:
```
BINOP(ADD, CONST(3), BINOP(MUL, CONST(2), CONST(5)))
```

Depois:
```
CONST(13)
```

Também:
```
BINOP(MUL, TEMP(x), CONST(0))  →  CONST(0)
```

(sem precisar saber o valor de `x`)

**Correção**: $\sigma \vdash e \Downarrow v \iff \sigma \vdash \mathit{fold}(e) \Downarrow v$

# Propagação de Constantes

## Ambiente de Propagação

Um **ambiente de propagação** $\rho : \mathit{Temp} \rightharpoonup \mathbb{Z}$ mapeia temporários a seus valores constantes conhecidos.

$$\mathit{foldProp}_\rho(\mathbf{TEMP}(t)) = \begin{cases}
  \mathbf{CONST}(\rho(t)) & \text{se } t \in \mathit{dom}(\rho) \\
  \mathbf{TEMP}(t) & \text{caso contrário}
\end{cases}$$

Para comandos — ao processar $\mathbf{MOVE}(\mathbf{TEMP}(t), e)$:

$$\rho' = \begin{cases}
  \rho[t \mapsto n] & \text{se } e' = \mathbf{CONST}(n) \\
  \rho \setminus \{t\} & \text{caso contrário}
\end{cases}$$

## Exemplo de Propagação Combinada

Antes:
```
MOVE(TEMP(x), CONST(5))
MOVE(TEMP(y), BINOP(MUL, TEMP(x), CONST(2)))
RETURN(TEMP(y))
```

Depois (com $\rho = \{x \mapsto 5, y \mapsto 10\}$):
```
MOVE(TEMP(x), CONST(5))
MOVE(TEMP(y), CONST(10))
RETURN(CONST(10))
```

Combinado com DCE, as duas primeiras linhas são eliminadas: `RETURN(CONST(10))`

# Eliminação de Subexpressões Comuns (CSE)

## Definição

A **tabela CSE** $\theta : \mathit{PureExpr} \rightharpoonup \mathit{Temp}$ mapeia expressões puras ao temporário que armazena seu valor mais recente.

Para $\mathbf{MOVE}(\mathbf{TEMP}(t), e)$ onde $e$ é pura:

$$\mathit{CSE}_\theta(\mathbf{MOVE}(\mathbf{TEMP}(t), e)) = \begin{cases}
  \mathbf{MOVE}(\mathbf{TEMP}(t), \mathbf{TEMP}(\theta(e))) & \text{se } e \in \mathit{dom}(\theta) \\
  \mathbf{MOVE}(\mathbf{TEMP}(c), e);\; \mathbf{MOVE}(\mathbf{TEMP}(t), \mathbf{TEMP}(c)) & \text{caso contrário}
\end{cases}$$

A tabela é **reiniciada** em fronteiras de bloco (LABEL, JUMP, CJUMP, RETURN).

## Exemplo de CSE

Antes:
```
MOVE(TEMP(a), BINOP(ADD, TEMP(x), TEMP(y)))
MOVE(TEMP(b), BINOP(ADD, TEMP(x), TEMP(y)))
```

Depois:
```
MOVE(TEMP(_cse0), BINOP(ADD, TEMP(x), TEMP(y)))
MOVE(TEMP(a),     TEMP(_cse0))
MOVE(TEMP(b),     TEMP(_cse0))
```

A expressão $x + y$ é calculada **uma única vez**.

**Por que só expressões puras?** `MEM(e)` pode mudar após escrita em memória.

# Eliminação de Código Morto (DCE)

## Fase 1: Código Inalcançável

Uma instrução é **inalcançável** se está imediatamente após JUMP ou RETURN sem LABEL intermediário:

```
RETURN(CONST(42))
MOVE(TEMP(x), CONST(1))   ← inalcançável! (sem LABEL antes)
LABEL(continue)
```

## Fase 2: Atribuições Mortas

Uma instrução $\mathbf{MOVE}(\mathbf{TEMP}(t), e)$ é **morta** se $t$ é redefinido antes de ser lido, ou a função termina sem usar $t$.

Estado de análise: $(\mathit{pend}, \mathit{dead})$

- $\mathit{pend}$ = atribuições pendentes (ainda não consumidas)
- $\mathit{dead}$ = índices das instruções marcadas para remoção

Em fronteiras de bloco (LABEL, JUMP, CJUMP): descarte conservador de $\mathit{pend}$.

## Exemplo de DCE

Após propagação de constantes:
```
MOVE(TEMP(x), CONST(5))     ← x nunca lido → morta
MOVE(TEMP(y), CONST(10))    ← y nunca lido → morta
RETURN(CONST(10))
```

Depois da DCE:
```
RETURN(CONST(10))
```

# Otimizações de Laço

## Estrutura de Laço na IRT

Um laço `while` na IRT linearizada tem o padrão:

$$\underbrace{\mathbf{LABEL}(\ell_h)}_{\text{cabeça}} \;\; \mathbf{CJUMP}(e, \ell_b, \ell_f) \;\; \underbrace{\mathbf{LABEL}(\ell_b)}_{\text{corpo}} \;\; s_1 \cdots s_k \;\; \mathbf{JUMP}(\mathbf{NAME}(\ell_h)) \;\; \underbrace{\mathbf{LABEL}(\ell_f)}_{\text{saída}}$$

Um **laço** $L = (\ell_h, \ell_b, \ell_f, e_\mathit{cond}, B)$ onde $B = [s_1, \ldots, s_k]$.

## Movimentação de Invariante de Laço (LICM)

Uma instrução $\mathbf{MOVE}(\mathbf{TEMP}(t), e)$ é **invariante de laço** se:

1. $e$ é pura
2. $\mathit{freeTemps}(e) \cap \mathit{defs}(L) = \emptyset$ — nenhuma variável de $e$ é modificada no laço
3. $t$ é definido exatamente **uma vez** no corpo
4. Nenhuma instrução anterior lê $t$ no corpo

**Transformação**: instruções invariantes são içadas (*hoisted*) para antes do cabeçalho.

## Exemplo de LICM

Antes:
```
LABEL(loop_head)
CJUMP(...)
LABEL(loop_body)
  MOVE(TEMP(k), BINOP(MUL, CONST(4), CONST(8)))  ← invariante!
  MOVE(TEMP(a), BINOP(MUL, TEMP(i), TEMP(k)))
  MOVE(TEMP(i), BINOP(SUB, TEMP(i), CONST(1)))
JUMP(NAME(loop_head))
```

Depois:
```
MOVE(TEMP(k), BINOP(MUL, CONST(4), CONST(8)))   ← içado
LABEL(loop_head)
  ...
  MOVE(TEMP(a), BINOP(MUL, TEMP(i), TEMP(k)))
  MOVE(TEMP(i), BINOP(SUB, TEMP(i), CONST(1)))
```

## Desenrolamento de Laço

Com fator $k = 2$, replica o corpo $k-1$ vezes extras:

```
LABEL(head)  CJUMP(cond, body, exit)
LABEL(body)
  <corpo original>
  CJUMP(cond, body2, exit)   ← verificação extra
LABEL(body2)
  <cópia do corpo>           ← renomeando rótulos internos
JUMP(NAME(head))
LABEL(exit)
```

**Benefícios**: menos avaliações da condição, mais oportunidades para outras otimizações.

## Fusão de Laços

**Loop fusion** combina dois laços adjacentes com a **mesma condição** em um único laço:

Antes:
```
while (cond) { corpo1 }
while (cond) { corpo2 }
```

Depois:
```
while (cond) { corpo1; corpo2 }
```

**Benefícios**: reduz overhead de controle, melhora localidade de dados.

**Restrição**: os dois laços devem ter a mesma condição e não haver dependências conflitantes entre `corpo1` e `corpo2`.

# Inlining de Funções

## O que é Inlining?

Substituir uma chamada $\mathbf{CALL}(\mathbf{NAME}(f), \bar{a})$ pelo corpo de $f$:

$$\mathit{inline}(f, \bar{a}) = \mathbf{ESEQ}\!\Bigl(\mathbf{MOVE}(x_1^s, a_1) \mathbin{;} \cdots \mathbin{;} B_f^s \mathbin{;} \mathbf{LABEL}(\ell_\mathit{exit}^s),\; \mathbf{TEMP}(r^s)\Bigr)$$

- $x_i^s$: parâmetros **renomeados** com sufixo único $s$
- $B_f^s$: corpo com temporários/rótulos locais **renomeados** com $s$
- Cada `RETURN(e)` em $B_f^s$ → `MOVE(r^s, e); JUMP(exit^s)`

**Benefícios**: elimina overhead de chamada + expõe código a dobramento, CSE, LICM.

## Elegibilidade para Inlining

Uma chamada é elegível se:

1. **Alvo estático**: `NAME(f)`, não um ponteiro computado
2. **Não auto-recursiva**: $f \notin \mathit{calls}(B_f)$
   (evita expansão infinita)
3. **Tamanho controlado**: $|\mathit{linearize}(B_f)| \leq \tau$
   (evita *code bloat*)

**Correção**: $\sigma \vdash \mathbf{CALL}(\mathbf{NAME}(f), \bar{a}) \Downarrow v \iff \sigma \vdash \mathit{inline}(f, \bar{a}) \Downarrow v$

Segue diretamente da regra semântica de invocação.

## Implementação em Haskell

```haskell
inlineProgram :: InlineConfig -> Program -> Program
inlineProgram cfg prog =
  removeDeadFuncs $
    map (inlineFuncDef funcMap inlineable) prog
  where
    funcMap    = Map.fromList [(funcName fd, fd) | fd <- prog]
    inlineable = Set.fromList
      [ funcName fd
      | fd <- prog
      , funcSize fd <= inlineThreshold cfg
      , not (isSelfRecursive fd) ]
```

- `inlineThreshold`: limiar $\tau$ (padrão: 10 instruções)
- `removeDeadFuncs`: elimina funções sem chamadores após inlining
- Mônada `State Int` gera sufixos únicos para cada sítio de chamada

## Renomeação e Transformação de Retorno

**renameLocals**: adiciona sufixo $s$ a todos os temporários e rótulos locais

**transformReturns**: substitui `RETURN([e])` por `MOVE(r^s, e); JUMP(exit^s)`

```haskell
transformReturns retTemp exitLbl = go
  where
    go (RETURN [e]) = SEQ (MOVE (TEMP retTemp) e)
                          (JUMP (NAME exitLbl))
    go (RETURN _)   = JUMP (NAME exitLbl)
    go (SEQ s1 s2)  = SEQ (go s1) (go s2)
    go s            = s
```

Sem renomeação, inlinar a mesma função em dois sítios produziria **colisões de temporários**.

# Eliminação de Chamadas em Cauda

## Chamadas em Posição de Cauda

Uma chamada está em **posição de cauda** se o único efeito posterior é retornar seu resultado:

| Padrão | Descrição |
|---|---|
| `RETURN [CALL(NAME(f), args)]` | Retorno com valor |
| `EXP(CALL(NAME(f), args)); RETURN []` | Retorno vazio |

**Ideia**: quando $f = g$ (auto-recursão), o frame corrente pode ser **reutilizado** — basta atualizar os parâmetros e saltar para o início.

Resultado: recursão $O(n)$ em pilha → laço $O(1)$ em pilha.

## A Transformação TCO

Para função $g$ com parâmetros $\bar{x} = (x_1,\ldots,x_n)$, introduz $\ell_h = \mathtt{L\_tco\_}g$:

1. Inserir $\mathbf{LABEL}(\ell_h)$ no início do corpo
2. Substituir cada chamada em cauda por:

$$\underbrace{\mathbf{MOVE}(t_1, a_1) \mathbin{;} \cdots \mathbin{;} \mathbf{MOVE}(t_n, a_n)}_{\text{passo 1: avaliar para auxiliares}} \mathbin{;} \underbrace{\mathbf{MOVE}(x_1, t_1) \mathbin{;} \cdots \mathbin{;} \mathbf{MOVE}(x_n, t_n)}_{\text{passo 2: atualizar parâmetros}} \mathbin{;} \mathbf{JUMP}(\ell_h)$$

**Por que dois passos?** Se $\bar{a} = (x_2, x_1)$, uma única passagem sobrescreveria $x_1$ antes de ser lido para $x_2$. Os temporários $t_i$ quebram a dependência cíclica.

## Exemplo: Fatorial com Acumulador

Antes da TCO:
```
RETURN [CALL(NAME(factAcc),
        [BINOP(BSub, TEMP(n),   CONST(1)),
         BINOP(BMul, TEMP(acc), TEMP(n))])]
```

Após a TCO:
```
LABEL(L_tco_factAcc)
  ...
  MOVE(TEMP(_tco_0), BINOP(BSub, TEMP(n),   CONST(1)))
  MOVE(TEMP(_tco_1), BINOP(BMul, TEMP(acc), TEMP(n)))
  MOVE(TEMP(n),   TEMP(_tco_0))
  MOVE(TEMP(acc), TEMP(_tco_1))
  JUMP(NAME(L_tco_factAcc))
```

Recursão convertida em laço — **sem crescimento de pilha**.

## Implementação em Haskell

```haskell
tcoFuncDef :: FuncDef -> FuncDef
tcoFuncDef fd
  | not (anyTailCall (funcName fd) stmts) = fd
  | otherwise =
      fd { funcBody = rebuildSeq (LABEL lh : transformed) }
  where
    stmts       = linearize (funcBody fd)
    lh          = "L_tco_" ++ funcName fd
    transformed = transformStmts (funcName fd) (funcParams fd) lh stmts

makeTCO :: [Temp] -> [Expr] -> [Stmt]
makeTCO params args =
  zipWith (\t e -> MOVE (TEMP t) e) tcoTemps args ++
  zipWith (\p t -> MOVE (TEMP p) (TEMP t)) params tcoTemps ++
  [JUMP (NAME lh)]
  where tcoTemps = ["_tco_" ++ show i | i <- [0..]]
```

O pipeline completo aplica TCO **antes** do inlining, pois o inlining pode expor novas chamadas em cauda.

# Conclusão

## Sumário do Capítulo

- **Dobramento** e **propagação** de constantes: avaliar em compile-time
- **CSE**: evitar recomputo de expressões puras já calculadas
- **DCE**: remover código inalcançável e atribuições nunca lidas
- **LICM**: içar código invariante para fora do laço
- **Unrolling / Fusion**: otimizações estruturais de laço
- **Inlining**: substituir chamada pelo corpo — elimina overhead, expõe otimizações
- **TCO**: converter auto-recursão em cauda em laço — pilha $O(1)$

## Próximos Passos

- **Geração de código WebAssembly** (próximo capítulo): IRT → WAT executável
- **Análise de fluxo de dados**: otimizações globais mais precisas
- **Otimizações baseadas em SSA**: Single Static Assignment, uma definição por variável
