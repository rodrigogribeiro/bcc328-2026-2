---
title: "Subtipagem e Featherweight Java"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Formalizar a **relação de subtipagem** $S <: T$ e o princípio de substituição
  de Liskov.

- Estudar a **contravariância** em tipos função e a regra de **subsunção**.

## Objetivos

- Apresentar o **Featherweight Java (FJ)**: sintaxe, tabela de classes,
  semântica operacional e sistema de tipos.

- Discutir as **propriedades** de FJ: progresso, preservação e os três tipos de
  cast.

## Objetivos

- Apresentar a **implementação** Haskell: verificador de tipos, interpretador e
  gerador de código IR.

# Motivação

## O Problema

Sistemas de tipos baseados em **igualdade exata** rejeitam programas seguros:

> "Se uma função espera `Number` e fornecemos um `Int`, por que reclamar? Todo
> inteiro é um número."

## O Problema

A **subtipagem** torna esse raciocínio preciso:

> $S <: T$ significa: _todo valor de tipo $S$ pode ser usado com segurança onde
> um valor de tipo $T$ é esperado._

Este é o **Princípio de Substituição de Liskov**: a base da orientação a
objetos.

## Dois Sistemas Neste Capítulo

1. **$\lambda$-cálculo com subtipagem**
   - $\mathsf{Bool} <: \mathsf{Int}$
   - Progresso, preservação, decidibilidade

## Dois Sistemas Neste Capítulo

2. **Featherweight Java (FJ)** _(Igarashi, Pierce e Wadler, 2001)_
   - Núcleo formal mínimo de Java
   - Classes, herança, campos, métodos, _casts_
   - Subtipagem por herança

# $\lambda$-cálculo com Subtipagem

## Sintaxe

**Termos:**

$$\begin{array}{l}
  t ::= x \mid n \mid \mathsf{true} \mid \mathsf{false} \mid t + t \\
\:\:\:\mid \mathsf{if}\ t\ \mathsf{then}\ t\ \mathsf{else}\ t \mid \lambda x {:} T.\, t \mid t\, t
\end{array}$$

## Sintaxe

**Tipos:**

$$T ::= \mathsf{Int} \mid \mathsf{Bool} \mid T \to T$$

## Sintaxe

**Valores (formas canônicas):**

$$v ::= n \mid \mathsf{true} \mid \mathsf{false} \mid \lambda x {:} T.\, t$$

## A Relação de Subtipagem

Menor relação **reflexiva e transitiva** que satisfaz:

$$\frac{}{T <: T} \;\text{(S-Refl)} \qquad \frac{S <: U \quad U <: T}{S <: T} \;\text{(S-Trans)}$$

$$\frac{}{\mathsf{Bool} <: \mathsf{Int}} \;\text{(S-Bool)}$$

$$\frac{T_1 <: S_1 \quad S_2 <: T_2}{S_1 \to S_2 <: T_1 \to T_2} \;\text{(S-Arrow)}$$

## A Relação de Subtipagem

- **S-Bool**: `true` interpreta-se como 1, `false` como 0 — promoção sem perda
- **S-Arrow**: **contravariante** no domínio, **covariante** no contradomínio

## Intuição da Contravariância

- Por que $S_1 \to S_2 <: T_1 \to T_2$ exige $T_1 <: S_1$?
  - Queremos usar $f : S_1 \to S_2$ onde se espera $T_1 \to T_2$

## Intuição da Contravariância

- O chamador fornecerá argumentos do tipo $T_1$:
  - Como $T_1 <: S_1$, esses argumentos são aceitos por $f$ ✓

## Intuição da Contravariância

- $f$ retorna $S_2$:
  - Como $S_2 <: T_2$, o resultado pode ser usado onde se espera $T_2$ ✓

## Exemplo

- $(\mathsf{Int} \to \mathsf{Bool}) <: (\mathsf{Bool} \to \mathsf{Int})$
  - $\mathsf{Bool} <: \mathsf{Int}$ e
  - $\mathsf{Bool} <: \mathsf{Int}$.

## Sistema de Tipos

A **regra de subsunção** conecta subtipagem e tipagem:

$$\frac{\Gamma \vdash t : S \quad S <: T}{\Gamma \vdash t : T} \;\text{(T-Sub)}$$

## Sistema de Tipos

$$\frac{x {:} T \in \Gamma}{\Gamma \vdash x : T} \;\text{(T-Var)}$$

## Sistema de Tipos

$$\frac{}{\Gamma \vdash n : \mathsf{Int}} \;\text{(T-Int)}$$

## Sistema de Tipos

$$\frac{}{\Gamma \vdash \mathsf{true} : \mathsf{Bool}} \;\text{(T-True)}$$

## Sistema de Tipos

$$\frac{\Gamma \vdash t_1 : \mathsf{Int} \quad \Gamma \vdash t_2 : \mathsf{Int}}{\Gamma \vdash t_1 + t_2 : \mathsf{Int}} \;\text{(T-Add)}$$

## Sistema de Tipos

$$\frac{\Gamma, x {:} T_1 \vdash t : T_2}{\Gamma \vdash \lambda x {:} T_1.\, t : T_1 \to T_2} \;\text{(T-Abs)} $$

## Sistema de Tipos

$$\frac{\Gamma \vdash t_1 : T_1 \to T_2 \quad \Gamma \vdash t_2 : T_1}{\Gamma \vdash t_1\, t_2 : T_2} \;\text{(T-App)}$$

## Semântica Operacional

$$\frac{t_1 \to t_1'}{t_1 + t_2 \to t_1' + t_2} \;\text{(E-AddL)}$$

## Semântica Operacional

$$\frac{t \to t'}{n + t \to n + t'} \;\text{(E-AddR)}$$

## Semântica Operacional

$$\frac{}{n_1 + n_2 \to n_1 \oplus n_2} \;\text{(E-Add)}$$

## Semântica Operacional

$$\frac{}{{\mathsf{if}\ \mathsf{true}\ \mathsf{then}\ t_2\ \mathsf{else}\ t_3 \to t_2}} \;\text{(E-IfTrue)}$$

## Semântica Operacional

$$\frac{}{{\mathsf{if}\ \mathsf{false}\ \mathsf{then}\ t_2\ \mathsf{else}\ t_3 \to t_3}} \;\text{(E-IfFalse)}$$

## Semântica Operacional

$$\frac{t_1 \to t_1'}{t_1\, t_2 \to t_1'\, t_2} \;\text{(E-AppFun)}$$

## Semântica Operacional

$$\frac{t \to t'}{v\, t \to v\, t'} \;\text{(E-AppArg)}$$

## Semântica Operacional

$$\frac{}{(\lambda x {:} T.\, t)\, v \to t[x \mapsto v]} \;\text{(E-Beta)}$$

## Propriedades

**Lema (Formas Canônicas):** se $v$ é valor bem tipado em contexto vazio:

- $\vdash v : \mathsf{Int}$ $\Rightarrow$ $v$ é inteiro $n$ _ou_ booleano
- $\vdash v : \mathsf{Bool}$ $\Rightarrow$
  $v \in \{\mathsf{true}, \mathsf{false}\}$
- $\vdash v : T_1 \to T_2$ $\Rightarrow$ $v = \lambda x {:} T.\, t$ com
  $T <: T_1$

## Propriedades

**Teorema (Progresso):** $\vdash t : T$ $\Rightarrow$ $t$ é valor ou
$\exists t'.\; t \to t'$

## Propriedades

**Teorema (Preservação):** $\vdash t : T$ e $t \to t'$ $\Rightarrow$
$\vdash t' : T'$ e $T' <: T$

## Decidibilidade da Subtipagem

**Teorema:** $S <: T$ é decidível — algoritmo por indução estrutural em $S$ e
$T$:

1. Se $S = T$: retorna $\mathsf{true}$ (S-Refl)
2. Se $S = \mathsf{Bool}$ e $T = \mathsf{Int}$: retorna $\mathsf{true}$ (S-Bool)
3. Se $S = S_1 \to S_2$ e $T = T_1 \to T_2$: retorna
   $T_1 <: S_1 \wedge S_2 <: T_2$ (S-Arrow)
4. Caso contrário: retorna $\mathsf{false}$

## Decidibilidade da Subtipagem

**Correção:** a única cadeia de comprimento $> 1$ é
$\mathsf{Bool} <: \mathsf{Int} <: \mathsf{Int}$, coberta pelos casos acima.

A transitividade não precisa de tratamento especial: o algoritmo termina.

# Featherweight Java

## O que é FJ?

Proposto por **Igarashi, Pierce e Wadler (2001)**:

- Núcleo formal **mínimo** de Java
- Captura os mecanismos essenciais de OO em linguagem pequena o suficiente para
  análise rigorosa

## O que é FJ?

- **FJ inclui:** classes, herança, campos, métodos, criação de objetos, _casts_

- **FJ omite** (deliberadamente): atribuição, controle de fluxo, interfaces,
  sobrecarga, tipos primitivos — tudo imutável, tudo é objeto

- Suficiente para demonstrar **progresso**, **preservação** e correção dos
  _casts_.

## Sintaxe de FJ

**Declaração de classe:**
$$\mathtt{class}\ C\ \mathtt{extends}\ D\ \{\ \overline{T\ f};\ K\ \overline{M}\ \}$$

## Sintaxe de FJ

**Construtor canônico:**
$$C(\overline{D\ g},\, \overline{T\ f})\ \{\ \mathtt{super}(\bar{g});\ \overline{\mathtt{this}.f = f};\ \}$$

## Sintaxe de FJ

**Declaração de método:** $$T\ m(\overline{T\ x})\ \{\ \mathtt{return}\ e;\ \}$$

## Sintaxe de FJ

**Expressões:**
$$e ::= x \mid e.f \mid e.m(\bar{e}) \mid \mathtt{new}\ C(\bar{e}) \mid (C)\ e$$

**Único tipo de valor:** $v ::= \mathtt{new}\ C(\bar{v})$

## Exemplo de Programa FJ

```java
class A extends Object { A() { super(); } }
class B extends Object { B() { super(); } }

class Pair extends Object {
  Object fst;  Object snd;
  Pair(Object fst, Object snd) {
    super();  this.fst = fst;  this.snd = snd;
  }
  Object fst() { return this.fst; }
  Object snd() { return this.snd; }
  Pair swap() { return new Pair(this.snd, this.fst); }
}
```

## Tabela de Classes

A **tabela de classes** $\mathit{CT}$: nomes de classe $\to$ declarações.

## Funções Auxiliares

$$\begin{array}{l}
\mathit{fields}(\mathsf{Object}) = \bullet \\
\dfrac{\mathit{CT}(C) = \ldots\quad \mathit{fields}(D) = \bar{D}\ \bar{g}}{\mathit{fields}(C) = \bar{D}\ \bar{g},\, \overline{C'\ f}}\end{array}$$

## Funções Auxiliares

$$\begin{array}{l}
  \dfrac{\mathit{CT}(C) = \ldots\ T\ m(\overline{T\ x})\ \{\ldots\}\ \ldots}{\mathit{mtype}(m, C) = \bar{T} \to T} \\
\dfrac{m \notin \mathit{CT}(C)\quad \mathit{mtype}(m, D) = U}{\mathit{mtype}(m, C) = U}
\end{array}$$

**$\mathit{mbody}(m, C)$** — parâmetros e corpo de $m$ em $C$.

## Subtipagem em FJ

Fecho **reflexivo-transitivo** da relação `extends`:

$$\begin{array}{c}
\dfrac{}{C <: C} \;\text{(S-Refl)} \\
\dfrac{C <: D \quad D <: E}{C <: E} \;\text{(S-Trans)}
\end{array}$$

## Subtipagem em FJ

$$\frac{\mathit{CT}(C) = \mathtt{class}\ C\ \mathtt{extends}\ D\ \{\ldots\}}{C <: D} \;\text{(S-Extends)}$$

## Subtipagem em FJ

- Todo tipo é subtipo de `Object` (por S-Trans e S-Extends iterados até a raiz)
- Subtipagem é **nominal**: baseada em declaração explícita de herança
- Contraste com subtipagem **estrutural** (Go, TypeScript)

## Semântica Operacional de FJ

**Acesso a campo (B-Field):**
$$\frac{\mathit{fields}(C) = \overline{C\ f}}{(\mathtt{new}\ C(\bar{v})).f_i \to v_i}$$

## Semântica Operacional de FJ

**Invocação de método (B-Invk):**
$$\frac{\mathit{mbody}(m, C) = (\bar{x}, e)}{(\mathtt{new}\ C(\bar{v})).m(\bar{u}) \to e[\bar{x} \mapsto \bar{u},\; \mathtt{this} \mapsto \mathtt{new}\ C(\bar{v})]}$$

## Semântica Operacional de FJ

**Cast (B-Cast):**
$$\frac{D <: C}{(C)\; (\mathtt{new}\ D(\bar{v})) \to \mathtt{new}\ D(\bar{v})}$$

Se $D \not<: C$: lança `ClassCastException` em **tempo de execução**.

## Regras de Congruência de FJ

$$\frac{e_0 \to e_0'}{e_0.f \to e_0'.f} \;\text{(E-Field)}$$

## Regras de Congruência de FJ

$$\frac{e_0 \to e_0'}{e_0.m(\bar{e}) \to e_0'.m(\bar{e})} \;\text{(E-InvkRecv)}$$

## Regras de Congruência de FJ

$$\frac{e_i \to e_i'}{v_0.m(\ldots, e_i, \ldots) \to v_0.m(\ldots, e_i', \ldots)} \;\text{(E-InvkArg)}$$

## Regras de Congruência de FJ

$$\frac{e_i \to e_i'}{\mathtt{new}\ C(\ldots, e_i, \ldots) \to \mathtt{new}\ C(\ldots, e_i', \ldots)} \;\text{(E-New)}$$

## Regras de Congruência de FJ

$$\frac{e \to e'}{(C)\ e \to (C)\ e'} \;\text{(E-Cast)}$$

## Sistema de Tipos de FJ

$$\frac{x {:} T \in \Gamma}{\Gamma \vdash x : T} \;\text{(T-Var)}$$

## Sistema de Tipos de FJ

$$\frac{\Gamma \vdash e_0 : C_0 \quad \mathit{fields}(C_0) = \overline{T\ f}}{\Gamma \vdash e_0.f_i : T_i} \;\text{(T-Field)}$$

## Sistema de Tipos de FJ

$$\dfrac{\begin{array}{c}\Gamma \vdash e_0 : C_0 \\ \mathit{mtype}(m, C_0) = \bar{T} \to T \\ \Gamma \vdash \bar{e} : \bar{C} \\ \bar{C} <: \bar{T}\end{array}}{\Gamma \vdash e_0.m(\bar{e}) : T} \;\text{(T-Invk)}$$

## Sistema de Tipos de FJ

$$\dfrac{\mathit{fields}(C) = \overline{T\ f} \quad \Gamma \vdash \bar{e} : \bar{C} \quad \bar{C} <: \bar{T}}{\Gamma \vdash \mathtt{new}\ C(\bar{e}) : C} \;\text{(T-New)}$$

## Os Três Tipos de Cast

$$\dfrac{\Gamma \vdash e_0 : D \quad D <: C}{\Gamma \vdash (C)\ e_0 : C} \;\text{(T-UCast)}$$

## Os Três Tipos de Cast

$$\dfrac{\Gamma \vdash e_0 : D \quad C <: D \quad C \neq D}{\Gamma \vdash (C)\ e_0 : C} \;\text{(T-DCast)}$$

## Os Três Tipos de Cast

$$\dfrac{\Gamma \vdash e_0 : D \quad C \not<: D \quad D \not<: C}{\Gamma \vdash (C)\ e_0 : C} \;\text{(T-SCast)}$$

## Os Três Tipos de Cast

- T-UCast: Seguro
  - Subtipo $\to$ supertipo
- T-DCast: Pode falhar em execução
  - Verificado dinamicamente
- T-SCast: Aceito com aviso

## Boa Formação de Métodos e Classes

**Método bem formado em $C$:**
$$\dfrac{\begin{array}{c}\overline{x {:} T},\, \mathtt{this} {:} C \vdash e : S \quad S <: T \\ \text{override}(m, D, \bar{T} \to T)\end{array}}{T\ m(\overline{T\ x})\{\ \mathtt{return}\ e;\ \}\ \mathsf{OK}\ \text{em}\ C} \;\text{(T-Method)}$$

## Boa Formação de Métodos e Classes

$\text{override}(m, D, \bar{T} \to T)$: se $m$ já é declarado em superclasse
$D$, a assinatura deve ser **idêntica** (FJ não suporta contravariância em
overrides).

## Boa Formação de Métodos e Classes

- **Classe bem formada** requer:

1. Superclasse existe em $\mathit{CT}$
2. Construtor aceita todos os campos (herdados + próprios) na ordem correta
3. Cada método é bem formado

## Propriedades de FJ

**Teorema (Progresso para FJ):** se $\vdash e : T$ e $e$ não é valor, então
$\exists e'.\; e \to e'$ **ou** $e$ lança `ClassCastException`.

_A ressalva sobre o cast é essencial_: downcasts podem falhar mesmo em programas
bem tipados. FJ captura com fidelidade o comportamento real de Java.

## Propriedades de FJ

**Teorema (Preservação para FJ):** se $\vdash e : T$ e $e \to e'$, então
$\vdash e' : T'$ com $T' <: T$.

O tipo do resultado pode ser um **subtipo** do tipo original. Por exemplo, após
um downcast bem-sucedido. Esse enfraquecimento é necessário e esperado.

# Implementação em Haskell

## Sintaxe Abstrata

```haskell
data Expr
  = EVar    VarName
  | EField  Expr FieldName
  | EInvk   Expr MethodName [Expr]
  | ENew    ClassName [Expr]
  | ECast   ClassName Expr

data ClassDecl = ClassDecl
  { cdName    :: ClassName
  , cdSuper   :: ClassName
  , cdFields  :: [(FJType, FieldName)]
  , cdCtor    :: Constructor
  , cdMethods :: [MethodDecl]
  }
```

## Sintaxe Abstrata

```haskell
data MethodDecl = MethodDecl
  { mdRetType :: FJType
  , mdName    :: MethodName
  , mdParams  :: [(FJType, VarName)]
  , mdBody    :: Expr
  }
```

## Tabela de Classes

```haskell
type ClassTable = Map.Map ClassName ClassDecl

-- Todos os campos de C (herdados + próprios), raiz primeiro
classFields :: ClassTable -> ClassName -> Maybe [(FJType, FieldName)]
classFields _  "Object" = Just []
classFields ct c = do
    cd <- Map.lookup c ct
    parentFs <- classFields ct (cdSuper cd)
    return (parentFs ++ cdFields cd)
```

## Obtendo Assinaturas

```haskell
-- Assinatura de m em C, buscando na hierarquia
mtype :: ClassTable -> MethodName -> ClassName
      -> Maybe ([FJType], FJType)
mtype _  _ "Object" = Nothing
mtype ct m c = do
    cd <- Map.lookup c ct
    case filter (\md -> mdName md == m) (cdMethods cd) of
      (md:_) -> Just (map fst (mdParams md), mdRetType md)
      []     -> mtype ct m (cdSuper cd)
```

## Subtipagem em Haskell

```haskell
-- Fecho reflexivo-transitivo de extends
isSubtype :: ClassTable -> ClassName -> ClassName -> Bool
isSubtype _  c d | c == d   = True
isSubtype _  _ "Object"     = True   -- Object é sempre supertipo
isSubtype ct c d =
    case Map.lookup c ct of
      Nothing -> False
      Just cd -> isSubtype ct (cdSuper cd) d
```

`isSubtype ct c "Object"` é sempre `True` — reflecte a raiz universal.

## Verificador de Tipos

```haskell
tcExpr :: ClassTable -> Env -> Expr -> TcM FJType

-- T-Field
tcExpr ct env (EField e f) = do
    FJType c <- tcExpr ct env e
    fs <- maybe (throwError "Unknown class") return (classFields ct c)
    case lookup f (map (\(t,fn) -> (fn,t)) fs) of
      Just t  -> return t
      Nothing -> throwError $ "Field not found: " ++ f
```

## Verificador de Tipos

```haskell
-- T-Invk
tcExpr ct env (EInvk e m args) = do
    FJType c <- tcExpr ct env e
    (paramTypes, retType) <-
      maybe (throwError "Method not found") return (mtype ct m c)
    argTypes <- mapM (tcExpr ct env) args
    forM_ (zip argTypes paramTypes) $ \(FJType got, FJType expected) ->
      unless (isSubtype ct got expected) $ throwError "Argument type mismatch"
    return retType
```

## Interpretador de FJ

Único tipo de valor:

```haskell
data FJValue = FJVal ClassName [FJValue]
```

## Interpretador de FJ

```haskell
eval :: ClassTable -> Expr -> EvalM FJValue

-- B-Field: localiza índice do campo na lista plana
eval ct (EField e f) = do
    v@(FJVal c _) <- eval ct e
    fs <- maybe (throwError "Unknown class") return (classFields ct c)
    case findIndex (\(_, fn) -> fn == f) fs of
      Nothing -> throwError "Field not found"
      Just i  -> return ((\(FJVal _ vs) -> vs !! i) v)
```

## Interpretador de FJ

```haskell
-- B-Invk: substitui this e parâmetros no corpo
eval ct (EInvk e m args) = do
    v@(FJVal c _) <- eval ct e
    argVals <- mapM (eval ct) args
    (params, body) <- maybe (throwError "Method not found") return 
                            (mbody ct m c)
    let env = ("this", valToExpr v) : zip params (map valToExpr argVals)
    eval ct (subst env body)
```

## Interpretador de FJ

```haskell
-- B-Cast: verifica subtipagem em tempo de execução
eval ct (ECast c e) = do
    v@(FJVal d _) <- eval ct e
    unless (isSubtype ct d c) $ throwError "ClassCastException"
    return v
```

# Geração de Código IR para FJ

## Visão Geral do Compilador FJ

| Categoria       | Função gerada | Descrição                             |
| --------------- | ------------- | ------------------------------------- |
| Construtor      | `C_new`       | Aloca objeto e inicializa campos      |
| Corpo de método | `C_m_m`       | Implementação de $m$ declarado em $C$ |

## Visão Geral do Compilador FJ

| Categoria        | Função gerada | Descrição                             |
| ---------------- | ------------- | ------------------------------------- |
| Despacho         | `dispatch_m`  | Rota chamada ao implementador correto |
| Ponto de entrada | `main`        | Expressão principal do programa       |

## Layout de Objetos em Memória

- Todo objeto FJ é um bloco contíguo de palavras de 8 bytes no heap:

$$\underbrace{\mathtt{class\_tag}}_{\text{offset } 0} \mid \underbrace{f_0}_{\text{offset } 8} \mid \underbrace{f_1}_{\text{offset } 16} \mid \cdots \mid \underbrace{f_n}_{\text{offset } (n{+}1) \cdot 8}$$

## Layout de Objetos em Memória

- **Palavra 0**: tag inteira única atribuída a cada classe em compilação
  (`Object` = 0)
- **Palavras $1 \ldots n$**: campos em ordem de $\mathit{fields}(C)$ (herdados
  primeiro)
- Todos os valores como inteiros de 8 bytes (ponteiros ou escalares)

## Compilação de Construtores

```haskell
compileConstructor env cd = do
    let n = length fields
        params = ["_p" ++ show i | i <- [0..n-1]]
    body <- inNewBlock $ do
        objT <- fresh
        -- alloca n+1 palavras (tag + n campos)
        emit $ IR.MOVE (IR.TEMP objT)
                       (IR.CALL (IR.NAME "alloc") [IR.CONST (n + 1)])
        -- escreve a tag na palavra 0
        emit $ IR.MOVE (IR.MEM (IR.TEMP objT)) (IR.CONST classId)
        -- escreve cada campo no offset (i+1)*8
        forM_ (zip [0..] params) $ \(i, p) ->
            emit $ IR.MOVE
                     (IR.MEM (IR.BINOP IR.BAdd (IR.TEMP objT)
                                               (IR.CONST ((i + 1) * 8))))
                     (IR.TEMP p)
        emit $ IR.RETURN [IR.TEMP objT]
```

## Despacho Dinâmico

- FJ usa **despacho dinâmico**: o método executado depende do tipo **dinâmico**
  do receptor.
  - Gera `dispatch_m` que lê a tag e encadeia comparações:

```
dispatch_m(_recv, _dp0, ...):
  tagT := MEM(_recv)          ;; lê tag do objeto
  CJUMP(tagT == tag_A) → ok_A, next_A
ok_A:
  RETURN CALL(A_m_m, _recv, _dp0, ...)
next_A:
  CJUMP(tagT == tag_B) → ok_B, next_B
ok_B:
  RETURN CALL(B_m_m, _recv, _dp0, ...)
  ...
```

## Verificação de Cast em Tempo de Execução

```haskell
compileExpr env (ECast d e) = do
    ptrT <- compileExpr env e
    let validIds = [i | (cn, i) <- Map.toList ids, isSubtype ct cn d]
    tagT  <- fresh
    emit $ IR.MOVE (IR.TEMP tagT) (IR.MEM (IR.TEMP ptrT))
    emit $ IR.CJUMP (buildOrChain (IR.TEMP tagT) validIds) okL failL
    emit $ IR.LABEL failL
    emit $ IR.EXP (IR.CALL (IR.NAME "print") [IR.CONST (-1)])  -- ClassCastException
    emit $ IR.RETURN [IR.CONST 0]
    emit $ IR.LABEL okL
    return ptrT
```

## Verificação de Casts em Tempo de Execução

```haskell
buildOrChain :: IR.Expr -> [Int] -> IR.Expr
buildOrChain _   []     = IR.CONST 0
buildOrChain tag [i]    = IR.BINOP IR.BEq tag (IR.CONST i)
buildOrChain tag (i:is) =
    IR.BINOP IR.BOr (IR.BINOP IR.BEq tag (IR.CONST i)) (buildOrChain tag is)
```

## Compilação de Expressões

```haskell
-- EVar: já é um temporário
compileExpr _ (EVar x) = return x

-- ENew: chama C_new
compileExpr env (ENew c args) = do
    argTs <- mapM (compileExpr env) args
    t <- fresh
    emit $ IR.MOVE (IR.TEMP t)
                   (IR.CALL (IR.NAME (c ++ "_new")) (map IR.TEMP argTs))
    return t
```

## Compilação de Expressões

```haskell
-- EField: lê palavra no offset do campo
compileExpr env (EField e f) = do
    ptrT <- compileExpr env e
    -- offset = (índice em fields(C) + 1) * 8
    t <- fresh
    emit $ IR.MOVE (IR.TEMP t)
                   (IR.MEM (IR.BINOP IR.BAdd (IR.TEMP ptrT) (IR.CONST offset)))
    return t
```

## Compilação de Expressões

```haskell
-- EInvk: chama dispatch_m
compileExpr env (EInvk e m args) = do
    recvT <- compileExpr env e
    argTs <- mapM (compileExpr env) args
    t <- fresh
    emit $ IR.MOVE (IR.TEMP t)
                   (IR.CALL (IR.NAME ("dispatch_" ++ m))
                            (map IR.TEMP (recvT : argTs)))
    return t
```

# Conclusão

## Conclusão

- **Subtipagem** $S <: T$: princípio de substituição de Liskov
- **S-Arrow**: contravariante no domínio, covariante no contradomínio
- **T-Sub** (subsunção): conecta subtipagem ao sistema de tipos

## Conclusão

- **FJ**: cinco formas de expressão, subtipagem nominal por herança
- **Três tipos de cast**: upcast (seguro), downcast (dinâmico), stupid cast
  (aviso)
- **Preservação enfraquecida**: tipo pode ser refinado para subtipo após
  downcast
- **Geração IR**: tag de classe + layout linear + despacho por cadeia de CJUMPs
