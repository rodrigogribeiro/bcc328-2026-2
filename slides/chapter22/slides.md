---
title: "Inferência de Tipos"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Distinguir verificação de tipos de inferência de tipos e apresentar a
  linguagem MiniML.

## Objetivos

- Apresentar a abordagem de geração e resolução de restrições para inferência de
  tipos, incluindo o algoritmo de unificação de Robinson, a generalização de
  Milner e a verificação de anotações polimórficas via subsumção.

## Objetivos

- Apresentar a eliminação de tipos como ponte entre o inferidor e o backend do
  compilador, e o pipeline completo MiniML → Lambda → TImp.

# Introdução

## Verificação vs. Inferência

- **Verificação de tipos**: dado um programa **com anotações**, decide se é bem
  tipado.

- **Inferência de tipos**: dado um programa **sem anotações**, encontra os tipos
  mais gerais — ou reporta que nenhum existe.

## Diferença central

- Regra (T-Abs) no STLC:

$$\frac{\Gamma,\, x : T_1 \vdash t : T_2}{\Gamma \vdash \lambda x {:} T_1.\; t : T_1 \to T_2}$$

- Verificação: $T_1$ é fornecido pelo programador
- Inferência: $T_1$ deve ser **descoberto** a partir do uso de $x$ no corpo

## A Linguagem MiniML

```
e ::= x              -- variável
    | ℓ              -- literal (int ou bool)
    | e₁ e₂          -- aplicação
    | λx. e          -- abstração sem anotação
    | let x = e₁ in e₂  -- definição polimórfica
```

- Abstrações **não** têm anotações de tipo
- O inferidor deduz tudo automaticamente

## Tipos e Esquemas

- **Tipos monomórficos:**

$$T ::= \mathbf{Int} \mid \mathbf{Bool} \mid T \to T \mid \alpha$$

## Tipos e Esquemas

- **Esquemas de tipo** (tipos polimórficos):

$$\sigma ::= T \mid \forall \vec{\alpha}.\; T$$

## Tipos e Esquemas

- Esquema $\forall \alpha_1 \ldots \alpha_n.\; T$ generaliza $T$ nas variáveis
  $\alpha_i$
- A **instanciação** substitui variáveis quantificadas por tipos novos
- A **generalização** de $T$ em $\Gamma$: $\forall \vec{\alpha}.\; T$ onde
  $\vec{\alpha} = \mathrm{fv}(T) \setminus \mathrm{fv}(\Gamma)$

# Linguagem de Restrições

## Gramática de Restrições

$$\begin{array}{rcll}
C & ::= & \top & \text{trivial} \\
  & \mid & T_1 = T_2 & \text{equação de tipos} \\
  & \mid & C_1 \wedge C_2 & \text{conjunção} \\
  & \mid & \exists \alpha.\; C & \text{var. existencial} \\
  & \mid & \mathbf{def}\; x : T\; \mathbf{in}\; C & \text{var. monomórfica} \\
  & \mid & \mathbf{let}\; x : T\; [C_1]\; \mathbf{in}\; C_2 & \text{def. polimórfica} \\
  & \mid & \mathbf{inst}(x,\, T) & \text{instanciação} \\
  & \mid & \mathbf{instScheme}(\sigma,\, T) & \text{verificação de anotação}
\end{array}$$

## Restrições

- $\exists \alpha.\; C$: variável de tipo local, visível apenas em $C$
- $\mathbf{def}$: parâmetro de lambda (não polimórfico)
- $\mathbf{let}$: polimorfismo de let (generaliza após resolver $C_1$)
- $\mathbf{instScheme}(\sigma, T)$: anotação polimórfica; requer subsumção

## Geração de Restrições

- $\mathcal{G}(e, \alpha)$ produz uma restrição cuja solução torna $\alpha$ o
  tipo de $e$:

$$\begin{array}{l}
     \mathcal{G}(x,\; \alpha) = \mathbf{inst}(x,\, \alpha)
    \end{array}
  $$

## Geração de Restrições

$$\begin{array}{l}
      \mathcal{G}(\ell,\; \alpha) = \alpha = \mathrm{tylit}(\ell)
    \end{array}
  $$

## Geração de Restrições

$$\begin{array}{ll}
   \mathcal{G}(e_1\; e_2,\; \alpha) = & \exists \beta.\;\bigl(\mathcal{G}(e_1,\; \beta \to \alpha) \wedge\\
    & \mathcal{G}(e_2,\; \beta)\bigr)
  \end{array}$$

## Geração de Restrições

$$\begin{array}{ll}
   \mathcal{G}(\lambda x.\; e,\; \alpha) = & \exists \beta_1.\; \exists \beta_2.\; \bigl(\mathbf{def}\; x : \beta_1\; \mathbf{in}\; \mathcal{G}(e,\, \beta_2)\bigr) \wedge \\
   & (\alpha = \beta_1 \to \beta_2)
\end{array}$$

## Geração de Restrições

$$\begin{array}{ll}
  \mathcal{G}(\mathbf{let}\; x = e_1\; \mathbf{in}\; e_2,\; \alpha) = & \exists \beta.\; \mathbf{let}\; x : \beta\; [\mathcal{G}(e_1,\, \beta)]\; \mathbf{in}\; \\ & \mathcal{G}(e_2,\, \alpha)
\end{array}$$

## Geração de Restrições

Com anotação polimórfica
$\mathbf{let}\; x {:} \sigma = e_1\; \mathbf{in}\; e_2$:

$$\begin{array}{ll}
  \mathcal{G}(\mathbf{let}\; x {:} \sigma = e_1\; \mathbf{in}\; e_2,\; \alpha) = & \exists \beta.\; \mathbf{let}\; x : \beta\; [\mathcal{G}(e_1,\, \beta) \wedge \mathbf{instScheme}(\sigma, \beta)]\; \mathbf{in}\; \\ & \mathcal{G}(e_2,\, \alpha)
\end{array}$$

- $\mathbf{instScheme}(\sigma, \beta)$ verifica que $\sigma$ é compatível com o
  tipo inferido

## Exemplo

- Considere $\lambda f.\; f\; \mathbf{true}$ com alvo $\alpha_0$

## Exemplo

$$\begin{array}{l}
   \mathcal{G}(\lambda f.\; f\; \mathbf{true},\; \alpha_0) = \\
   \exists \beta_1\, \beta_2\, \beta_3.\; \bigl(\mathbf{def}\; f : \beta_1\; \mathbf{in}\; \mathbf{inst}(f,\, \beta_3 \to \beta_2) \wedge\\
 \beta_3 = \mathbf{Bool}\bigr) \wedge (\alpha_0 = \beta_1 \to \beta_2)
\end{array}$$

## Exemplo

- A resolução força $\beta_1 = \mathbf{Bool} \to \beta_2$.

- Tipo principal: $\alpha_0 = (\mathbf{Bool} \to \beta_2) \to \beta_2$,
  generalizado em $\beta_2$:

- $$\forall \beta.\; (\mathbf{Bool} \to \beta) \to \beta$$

# Subsumção

## A Relação de Subsumção

- **Motivação**: quando é que uma anotação $\sigma_\mathit{ann}$ é compatível
  com o tipo inferido?

- **Definição**: $\sigma_1 \preceq \sigma_2$ ($\sigma_1$ subsume $\sigma_2$) se
  toda instância de $\sigma_2$ é instância de $\sigma_1$

## A Relação de Subsumção

Formalmente, $\forall \vec{\alpha}.\, T_1 \preceq \forall \vec{\beta}.\, T_2$ se
existe $S$ com $\mathrm{dom}(S) \subseteq \{\vec{\alpha}\}$ tal que:

$$S(T_1) = [\vec{\beta} \mapsto \vec{\gamma}]\, T_2 \quad \text{para novas variáveis } \vec{\gamma}$$

## Exemplos de Subsumção

- $\forall \alpha.\, \alpha \to \alpha \;\preceq\; \mathbf{Int} \to \mathbf{Int}$
  - via $[\alpha \mapsto \mathbf{Int}]$ ✓

- $\forall \alpha.\, \alpha \to \alpha \;\preceq\; \forall \alpha.\, \alpha \to \alpha$
  - reflexividade ✓

- $\forall \alpha.\, \alpha \to \alpha \;\not\preceq\; \forall \alpha.\, \alpha \to \mathbf{Bool}$
  - não existe substituição que force $\alpha = \mathbf{Bool}$ para $\alpha$
    arbitrário ✗

## Subsumção e Anotações

A restrição $\mathbf{instScheme}(\sigma_\mathit{ann}, T)$ tem semântica:

$$\begin{array}{l}
(S, \Gamma) \models \mathbf{instScheme}(\sigma_\mathit{ann}, T) \iff\\
\mathrm{gen}(\Gamma, S(T)) \preceq \sigma_\mathit{ann}
\end{array}$$

## Subsumção e Anotações

- O tipo inferido deve ser **pelo menos tão geral** quanto a anotação
- Permite restringir: $\lambda x.\, x$ anotado com
  $\mathbf{Int} \to \mathbf{Int}$ ✓
- Proíbe generalizar além: anotar com
  $\forall \alpha.\, \alpha \to \mathbf{Bool}$ ✗

## Algoritmo de Verificação de Subsumção

Para verificar $\sigma_1 \preceq \sigma_2$:

1. Renomeia variáveis de $\sigma_2$ como **variáveis rígidas** $\vec{\gamma}$
   (não instanciáveis)
2. Instancia $\sigma_1$ com variáveis **flexíveis** $\vec{\delta}$
3. Unifica os corpos — falha = subsumção falha
4. Verifica que nenhuma $\vec{\gamma}$ foi instanciada

## Algoritmo de Verificação de Subsumção

```haskell
subsumes :: Scheme -> Scheme -> Solve ()
subsumes (Forall as t1) (Forall bs t2) = do
    rigidTs <- mapM (\_ -> freshTyVar) bs
    let rigidMap = Map.fromList (zip bs rigidTs)
        t2'      = apply rigidMap t2
        rigidNms = Set.fromList [v | TVar v <- rigidTs]
    flexTs <- mapM (\_ -> freshTyVar) as
    let t1' = apply (Map.fromList (zip as flexTs)) t1
    s <- mgu t1' t2'
    let constrained = Map.keysSet s `Set.intersection` rigidNms
    unless (Set.null constrained) $
        throwError "Falha de subsumcao: variavel rigida instanciada"
```

# O Resolvedor

## Unificação de Robinson

$\mathrm{mgu}(T_1, T_2)$ encontra o **unificador mais geral**:

$$\begin{array}{ll}
\mathrm{mgu}(\alpha, \alpha) = \varepsilon \\
\mathrm{mgu}(\alpha, T) = [\alpha \mapsto T]\:\:\:\:\text{se } \alpha \notin \mathrm{fv}(T) \\
\mathrm{mgu}(T_1 \to T_2,\; T_1' \to T_2') = S_2 \circ S_1 \\
\:\:\:\:\:S_1 = \mathrm{mgu}(T_1, T_1'),\; S_2 = \mathrm{mgu}(S_1(T_2), S_1(T_2')) \\
\mathrm{mgu}(T, T) = \varepsilon \\
\mathrm{mgu}(T_1, T_2) = \text{erro}\\
\end{array}$$

## O Algoritmo de Resolução

```haskell
solve :: Constraint -> Solve ()
solve CTrue = pure ()
solve (t1 :=: t2) = do
    s  <- askSubst
    s' <- mgu (apply s t1) (apply s t2)
    extSubst s'
solve (c1 :&: c2) = solve c1 >> solve c2
```

## O Algoritmo de Resolução

```haskell
solve (CExists c) = do
    v <- freshTyVar
    solve (c v)
solve (CDef x t c) =
    withLocalCtx x (Forall [] t) (solve c)
solve (CLet x t c1 c2) = do
    solve c1
    scheme <- generalize t
    withLocalCtx x scheme (solve c2)
solve (CInst x t) = do
    t' <- lookupVar x
    solve (t :=: t')
solve (CInstScheme sigma inf) = do
    s      <- askSubst
    sigInf <- generalize (apply s inf)
    subsumes sigInf sigma
```

# Correção e Completude

## Teoremas Fundamentais

- **Teorema (Correção)**: Se o resolvedor aceita $C_e$ com substituição $S$,
  então $\vdash e : S(\alpha_0)$.

## Teoremas Fundamentais

- **Teorema (Completude)**: Se $\Gamma \vdash e : T$, então o resolvedor aceita
  $C_e$ e produz um tipo do qual $T$ é instância.

## Teoremas Fundamentais

- _Se $e$ é tipável, o algoritmo encontra o tipo mais geral._

- **Teorema (Tipo Principal)**: Existe $\sigma$ tal que:
  1. $\vdash e : T$ para todo $T$ instância de $\sigma$
  2. Todo tipo válido $T'$ é instância de $\sigma$

- O algoritmo sempre encontra o **tipo principal**.

# Eliminação de Tipos e Pipeline

## Eliminação de Tipos

- Tipos são necessários para análise estática, mas **desnecessários em
  execução**.

## Eliminação de Tipos

- A função $\lfloor \cdot \rfloor : \mathit{TyExp} \to \mathit{Term}$ descarta
  anotações:

$$\begin{array}{rcl}
\lfloor x : T \rfloor & = & x \\
\lfloor (te_1\; te_2) : T \rfloor & = & \lfloor te_1 \rfloor\; \lfloor te_2 \rfloor \\
\lfloor \lambda x {:} T_1.\; te : T \rfloor & = & \lambda x.\; \lfloor te \rfloor \\
\lfloor \mathbf{let}\; x = t:w
e_1\; \mathbf{in}\; te_2 : T \rfloor & = & (\lambda x.\; \lfloor te_2 \rfloor)\; \lfloor te_1 \rfloor
\end{array}$$

## O Pipeline Completo de MiniML

```haskell
processTImp :: String -> IO ()
processTImp input =
  case parser input of
    Left err  -> putStrLn $ "Parse error: " ++ err
    Right ast ->
      case inferElab ast of
        Left err -> putStrLn $ "Type error: " ++ err
        Right (_, _, te, ty) -> do
          putStrLn $ "val : " ++ pretty ty    -- tipo exibido
          let lterm = erase te                -- elimina tipos
              prog  = lambdaToTImp lterm      -- closure conversion
          result <- interpret prog
          ...
```

## Exemplo

Para `let f = \x . x in f 42`:

## Exemplo

1. **Inferência**: tipo `Int`, árvore tipada
   $\mathbf{let}\; f = (\lambda x{:}\alpha.\; x){:}\alpha \to \alpha\; \mathbf{in}\; (f\; 42){:}\mathbf{Int}$

## Exemplo

2. **Eliminação**: $(\lambda f.\; f\; 42)\; (\lambda x.\; x)$

## Exemplo

3. **Closure conversion**: duas funções promovidas, `lam_0` (identidade) e
   `lam_1` (aplicação de `f`)

## Exemplo

4. **Execução TImp**: imprime `42`

# Conclusão

## Conclusão

- Inferência de tipos resolve um problema mais difícil que a verificação.
  - Fundamentação teórica.
  - Base para polimorfismo em linguagens

## Conclusão

- Algoritmo baseado em geração + solução de restrições.
  - Geração: restrições são fórmulas da lógica.
  - Solução: para igualdade, unificação.

## Conclusão

- Compilação
  - Eliminação de tipos + closure conversion.
