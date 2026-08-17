---
title: "A Pesquisa em Compiladores"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar técnicas de teste sistemático de compiladores: geração
  aleatória de programas, testes diferenciais e testes metamórficos.

- Discutir a verificação formal de compiladores, com destaque para o
  CompCert e a noção de preservação semântica.

- Apresentar uma panorâmica de tópicos avançados de pesquisa: sistemas de
  tipos expressivos, representações intermediárias modernas e infraestrutura
  de otimização.

# Introdução

## Por que Pesquisar Compiladores?

- Todo programa de alto nível passa pelo compilador — um bug pode comprometer **todo o ecossistema**
- *Wrong-code bugs*: o compilador gera código errado sem avisar
- GCC: > 15 milhões de linhas; LLVM: > 20 milhões de linhas

A pesquisa em compiladores vai além de "construir compiladores corretos":

- Como **testá-los** sistematicamente?
- Como **prová-los formalmente** corretos?
- Como **enriquecer as linguagens** com sistemas de tipos mais expressivos?
- Como **representar programas** de forma mais eficiente?

## Tópicos Deste Capítulo

1. **Teste de compiladores**: fuzzing, testes diferenciais, metamórficos
2. **Verificação formal**: CompCert, simulações, Alive
3. **Sistemas de tipos avançados**: tipos dependentes, lineares, session types
4. **Representações intermediárias**: SSA, VSDG
5. **Otimização**: inlining, vetorização, LLVM como infraestrutura

# Teste de Compiladores

## Geração Aleatória de Programas (Fuzzing)

**CSmith** [Yang et al., 2011]:

1. Gera programas C aleatórios com semântica bem definida
2. Compila com múltiplos compiladores e níveis de otimização
3. Compara saídas: discrepâncias = bugs

Este princípio chama-se **teste diferencial** (*differential testing*):

> "Dois compiladores corretos devem concordar, mesmo sem saber a resposta correta."

**Resultado**: centenas de bugs encontrados em GCC e LLVM.

## Teste Baseado em Propriedades

Popularizado pelo **QuickCheck** [Claessen & Hughes, 2000]:

- Especifica **propriedades** que o compilador deve satisfazer
- A ferramenta gera inputs aleatórios para **falsificá-las**

Exemplo de propriedade — equivalência semântica após otimização:

$$\forall P\ \text{bem tipado}.\; \llbracket P \rrbracket = \llbracket \mathit{opt}(P) \rrbracket$$

**Testes metamórficos** [Le et al., 2014]: aplica transformações semânticas conhecidas ao programa-fonte:

> "Se $P'$ é obtido de $P$ por substituição de $x + 0$ por $x$, então $P$ e $P'$ devem produzir o mesmo resultado compilados."

# Verificação Formal de Compiladores

## Preservação Semântica

Um compilador $\mathcal{C}$ é **correto** se para todo programa $P$ bem tipado:

$$P \Downarrow v \implies \mathcal{C}(P) \Downarrow v$$

A compilação **preserva o comportamento observável** do programa.

## CompCert

**CompCert** [Leroy, 2009]: o primeiro compilador de uso real com preservação semântica provada formalmente.

- Compila C para assembly x86, PowerPC e ARM
- Cada passagem acompanhada de prova mecânica no **Coq**
- **Resultado**: estudo com CSmith descobriu **zero** wrong-code bugs no CompCert, enquanto GCC e LLVM apresentaram dezenas

**Estrutura da prova**: cada passagem $\mathcal{T}$ é acompanhada de uma relação de **simulação**:

$$\frac{e \to e' \quad \mathcal{T}(e) \to^* \mathcal{T}(e')}{e \to^* v \implies \mathcal{T}(e) \to^* v}$$

## Verificação de Passagens Individuais

Nem sempre é necessário verificar o compilador inteiro:

- **Alocação de registradores** [Rideau & Leroy, 2010]: verificada no Coq
- **Compilação JIT** [Carbonneaux et al., 2014]: com garantias de tempo real
- **Alive** [Lopes et al., 2015]: verifica automaticamente transformações de peephole do LLVM via SMT solvers

# Sistemas de Tipos Avançados

## Tipos Dependentes

Em sistemas de tipos comuns, tipos e valores habitam mundos separados. **Tipos dependentes** eliminam essa separação:

$$\mathsf{Vec} : \mathbb{N} \to \mathsf{Type} \to \mathsf{Type}$$

$$\mathsf{append} : \mathsf{Vec}\ m\ A \to \mathsf{Vec}\ n\ A \to \mathsf{Vec}\ (m + n)\ A$$

- O compilador verifica **em compilação** que tamanhos são corretos
- Acesso fora do intervalo é **impossível** de escrever

**Linguagens**: Agda, Idris, Coq, Lean 4

**Desafio**: inferência de tipos geralmente indecidível — exige anotações explícitas.

## Tipos Lineares

Um **tipo linear** garante que um recurso é usado *exatamente uma vez*:

```
open   : String → File
read   : File   → (String, File)
close  : File   → Unit
```

O compilador garante:
- Todo arquivo aberto é fechado **exatamente uma vez**
- Sem *use after free*; sem *double close*

**Rust**: o sistema de *ownership* e *borrows* é uma forma de tipos lineares/afins integrada a linguagem de sistemas.

**Base teórica**: Lógica Linear [Girard, 1987]; Linear Type Theory [Wadler, 1990].

## Session Types

**Session types** tipam canais de comunicação:

$$S = \mathsf{!Int}.\; \mathsf{!Int}.\; \mathsf{?Int}.\; \mathsf{end}$$

"Envie um inteiro, envie outro, receba um inteiro, encerre."

O cliente tem o tipo **dual** $\bar{S}$:

$$\bar{S} = \mathsf{?Int}.\; \mathsf{?Int}.\; \mathsf{!Int}.\; \mathsf{end}$$

O compilador garante ausência de **deadlock** e erros de protocolo em tempo de compilação.

# Representações Intermediárias

## Static Single Assignment (SSA)

Em SSA, **cada variável é atribuída exatamente uma vez**:

```python
# Antes da SSA:          # Após SSA:
x = 0                    x0 = 0
x = x + 1                x1 = x0 + 1
if b: x = 5              if b: x2 = 5
else: x = 10             else: x3 = 10
z = x + y                x4 = phi(x2, x3)
                         z0 = x4 + y0
```

A **função $\phi$** seleciona o valor correto no ponto de junção.

**Por que SSA facilita otimizações?**

- Propagação de constantes: trivial (uma definição por variável)
- Eliminação de código morto: variáveis sem uso são imediatamente identificáveis
- Alocação de registradores: grafo de interferência calculado eficientemente

SSA é a representação central do **LLVM IR** e do **GCC GIMPLE**.

## Value State Dependence Graph (VSDG)

O **VSDG** [Johnson et al., 2004] representa o programa como um grafo de dependências:

| Tipo de aresta | Significado |
|---|---|
| **Valor** | Resultado de uma operação é entrada de outra |
| **Estado** | Uma operação com efeito deve preceder outra |
| **Controle** | Uma operação só executa se condição for satisfeita |

**Vantagem**: CSE é **gratuita** — expressões idênticas são representadas pelo **mesmo nó**.

Duas leituras independentes não têm aresta entre si — podem ser reordenadas livremente.

## LLVM como Infraestrutura de Pesquisa

**LLVM** [Lattner & Adve, 2004]: principal plataforma de pesquisa em compiladores hoje.

- IR bem definida, documentada e manipulável via API
- Passes (*opt*): pipeline de otimizações composável
- Clang (C/C++), Flang (Fortran), Kotlin/Native, Rust, Swift — todos usam LLVM
- **TableGen**: geração automática de seleção de instruções por especificação declarativa

Pesquisadores implementam passagens como plugins LLVM e avaliam em programas reais.

# Conclusão

## Sumário do Capítulo

- **Fuzzing + testes diferenciais**: CSmith encontrou centenas de bugs sem oráculo explícito
- **CompCert**: prova formal de preservação semântica — zero wrong-code bugs
- **Tipos dependentes**: verificação de propriedades quantitativas em compilação
- **Tipos lineares**: controle de recursos sem garbage collector (Rust!)
- **SSA**: uma definição por variável facilita análise e otimização
- **VSDG**: CSE gratuita; reordenação explícita por dependências reais

## Perspectivas Futuras

- **Compiladores para IA/ML**: compilação de grafos de tensores (XLA, TVM, MLIR)
- **Compiladores formalmente verificados**: extensão do CompCert para outras linguagens
- **Compilação incremental**: apenas recompilar o que mudou
- **Segurança por compilação**: *information flow control*, isolamento de memória por tipo
