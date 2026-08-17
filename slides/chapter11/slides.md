---
title: "Geradores de Analisadores Sintáticos"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a linguagem de especificação do Happy.

- Apresentar exemplos de analisadores LALR construídos utilizando o Happy.

# Introdução ao Happy

## Motivação

- Construir tabelas LALR à mão é impraticável para gramáticas reais
- Assim como o **Alex** automatiza análise léxica, o **Happy** automatiza
  análise sintática

## Motivação

- Happy gera analisadores **LALR(1)** a partir de especificações gramaticais no
  estilo BNF
- O próprio compilador **GHC** usa um parser gerado pelo Happy
- Análogo ao `yacc` e `Bison` do ecossistema C/C++

## Estrutura de um Arquivo `.y`

```
{ cabeçalho Haskell }

diretivas e declaração de tokens

%%

regras gramaticais

{ rodapé Haskell }
```

## Estrutura de um Arquivo `.y`

- Quatro partes separadas pelo marcador `%%`:

1. **Cabeçalho**: módulo e imports Haskell (copiado literalmente)
2. **Diretivas**: configurações do parser e declaração de tokens
3. **Regras**: produções BNF com ações semânticas em Haskell
4. **Rodapé**: funções auxiliares

## Gerando o Parser

```bash
happy ExpParser.y            # gera ExpParser.hs
happy -i ExpParser.y         # também gera ExpParser.info (tabela)
happy -o ExpParser.hs ExpParser.y
```

## Gerando o Parser

- Com Cabal: basta listar `happy` em `build-tool-depends`

# Diretivas do Happy

## Principais Diretivas

| Diretiva    | Significado                                     |
| ----------- | ----------------------------------------------- |
| `%name p N` | Gera função `p` iniciando pelo não-terminal `N` |

## Principais Diretivas

| Diretiva           | Significado                                 |
| ------------------ | ------------------------------------------- |
| `%tokentype { T }` | Define o tipo Haskell dos tokens consumidos |

## Principais Diretivas

| Diretiva                          | Significado                           |
| --------------------------------- | ------------------------------------- |
| `%monad { M }{ (>>=) }{ return }` | Executa o parser dentro da mônada `M` |

## Principais Diretivas

| Diretiva              | Significado                                  |
| --------------------- | -------------------------------------------- |
| `%lexer { f }{ eof }` | Lexer incremental: `f` obtém o próximo token |

## Principais Diretivas

| Diretiva       | Significado                            |
| -------------- | -------------------------------------- |
| `%error { h }` | Chama `h` ao encontrar erro de sintaxe |

## Principais Diretivas

| Diretiva    | Significado                                             |
| ----------- | ------------------------------------------------------- |
| `%expect n` | Declara exatamente `n` conflitos shift-reduce esperados |

## Principais Diretivas

| Diretiva                       | Significado                   |
| ------------------------------ | ----------------------------- |
| `%left`, `%right`, `%nonassoc` | Precedência e associatividade |

## Diretivas

```
%name parser Exp
%monad {Alex}{(>>=)}{return}
%tokentype { Token }
%error     { parseError }
%lexer {lexer}{Token _ TEOF}
```

## Diretivas

- `%monad` integra com a mônada `Alex` do lexer gerado pelo Alex
- `%lexer` faz Happy chamar `lexer` para obter cada token (modo incremental)
- O modo incremental é necessário quando o lexer é monádico

## Declaração de Tokens

- A seção `%token` associa nomes simbólicos a padrões de correspondência:

```
%token
      num       {Token _ (TNumber $$)}
      '('       {Token _ TLParen}
      ')'       {Token _ TRParen}
      '+'       {Token _ TPlus}
      '*'       {Token _ TTimes}
```

## Declaração de Tokens

- `$$` em `Token _ (TNumber $$)` captura o valor inteiro

— Disponível nas ações como `$1`, `$2`, etc.

- Tokens sem valor (como `TLParen`) apenas verificam o construtor

## Declarações de Precedência

```
%left '+'
%left '*'
```

## Declarações de Precedência

- A **ordem** das linhas determina precedência: de menor para maior
- `*` aparece depois de `+` → `*` tem **maior** precedência

## Declarações de Precedência

- `%left`: associatividade à esquerda
- `%right`: associatividade à direita
- `%nonassoc`: não associativo (erro se encadeado)

# Regras Gramaticais e Ações

## Regras Gramaticais

- Após o `%%`, produções BNF com ações em Haskell:

```
Exp : num         { EInt $1 }
    | Exp '+' Exp { $1 :+: $3 }
    | Exp '*' Exp { $1 :*: $3 }
    | '(' Exp ')' { $2 }
```

## Regras Gramaticais

- `$1`, `$2`, `$3`: valores semânticos dos símbolos (da esquerda para a direita)
- Ação executada quando o parser **reduz** por aquela produção
- Tipo inferido pelo compilador a partir das ações: `Exp`

## Rodapé: Funções Auxiliares

```haskell
{
lexer :: (Token -> Alex a) -> Alex a
lexer = (=<< alexMonadScan)

expParser :: String -> IO (Either String Exp)
expParser content = pure $ runAlex content parser
}
```

# Gerando a Tabela LALR

## A Opção `-i`

```bash
happy -i ExpParser.y
# gera ExpParser.info
```

## Arquivos .info

O arquivo `.info` contém:

1. **Gramática aumentada** com produções numeradas
2. **Conjuntos FIRST** de cada não-terminal

## Arquivos .info

3. **Estados do autômato LALR**:cada um com seus itens LR(1) e lookaheads
4. **Tabela de ações**: shift, reduce, accept para cada (estado, terminal)

## Arquivos .info

5. **Tabela goto**: para cada (estado, não-terminal)
6. **Conflitos detectados**: com estado e token envolvidos

## Exemplo de Estado no `.info`

```
State 7

        Exp -> Exp . '+' Exp          (rule 2)
        Exp -> Exp . '*' Exp          (rule 3)
        Exp -> Exp '+' Exp .          (rule 2)

        '*'    shift, and enter state 5
               (reduce using rule 2)

        '+'    shift, and enter state 4
               (reduce using rule 2)

        ')'    reduce using rule 2
        '$'    reduce using rule 2
```

# Conflitos

## Shift-Reduce

- Ocorre quando o parser pode tanto fazer shift quanto reduce no mesmo estado e
  token.

**Causa comum**: gramática de expressões escrita de forma ambígua:

```
Exp : num
    | Exp '+' Exp
    | Exp '*' Exp
    | '(' Exp ')'
```

## Shift-Reduce

- Para `1 + 2 * 3`, após empilhar `Exp '+' Exp` (com `Exp` = `2`) e ver `*`:
  - **Reduce** `Exp '+' Exp` → interpreta `(1+2)*3`
  - **Shift** `*` → interpreta `1+(2*3)` (correto!)

- Happy retorna: `ExpParser.y: shift/reduce conflicts: 4`

## Solução: Precedência

Happy usa as declarações para resolver:

- Token com **maior** precedência que a produção → **shift**
- Token com **menor** precedência → **reduce**
- Token com **mesma** precedência → aplica associatividade

## Shift-Reduce

- Gramática para if/else

```
Stmt : 'if' Exp 'then' Stmt
     | 'if' Exp 'then' Stmt 'else' Stmt
     | 'other'
```

## Shift-Reduce

- Para `if e1 then if e2 then s1 else s2`:
  - Shift `else` → pertence ao `if` mais próximo (interno): convenção padrão
  - Reduce `if ... then s1` → `else` pertence ao `if` externo

- O comportamento padrão do Happy (preferir shift) resolve esse problema
  corretamente.

## Reduce-Reduce

- Ocorre quando dois itens completos diferentes reivindicam a mesma entrada.

```
Prog : Decl
     | Expr

Decl : 'id'
Expr : 'id'
```

## Reduce-Reduce

Ao ver `id` e precisar reduzir:

- Não sabe se deve criar `Decl` ou `Expr`
- Happy escolhe a **primeira regra** (aviso, não erro)

## Reduce-Reduce

- Diferentemente do shift-reduce, conflitos reduce-reduce raramente têm
  resolução padrão correta.

— **Quase sempre indicam uma gramática problemática**.

## Reduce-Reduce

- Solução: Tornar os dois não-terminais sintáticos distintos por contexto:

```
-- Antes: ambíguo
Prog : 'id'   -- pode ser Decl ou Expr?

-- Depois: discriminar por palavra-chave
Prog : 'let' 'id'    -- declaração
     | 'id'          -- expressão
```

## Reduce-Reduce

- Outra abordagem: remover ambiguidade na análise semântica

— Exemplo: `typedef` de C, onde identificadores de tipo requerem consulta ao
contexto.

# Indentação em Geradores de Parsers

## O Problema

- Geradores LALR como o Happy operam sobre **sequências de tokens**
- Tokens não carregam informação de coluna para o parser
- **Solução**: delegar ao lexer — injetar tokens `INDENT`/`DEDENT`

## O Lexer Hack

- O lexer mantém uma **pilha de colunas** (níveis de indentação abertos)
- A cada nova linha, compara a coluna do primeiro token com o topo da pilha:

| Situação                   | Ação                                |
|----------------------------|-------------------------------------|
| Coluna **>** topo da pilha | Emite `INDENT`, empilha a coluna    |
| Coluna **=** topo da pilha | Emite `NEWLINE` (separador de stmt) |
| Coluna **<** topo da pilha | Emite `DEDENT` (x níveis fechados)  |

## O Lexer Hack

- Ao final do arquivo: emite `DEDENT`s para fechar todos os blocos abertos
- Usado por Python (CPython), GHC (regra de layout de Haskell), YAML

## Alex: `monadUserState`

- O Alex oferece o wrapper **`monadUserState`**
- Integra estado arbitrário diretamente na mônada `Alex`
- Evita mônada de estado separada: indentação vive no mesmo contexto que o lexer

```
%wrapper "monadUserState"
```

## Estado de Usuário (Alex)

```haskell
data AlexUserState = AlexUserState
  { lsIndents :: [Int]    -- pilha de colunas abertas
  , lsPending :: [Token]  -- INDENT/DEDENTs pendentes
  }

-- Nome exigido pelo Alex
alexInitUserState :: AlexUserState
alexInitUserState = AlexUserState [1] []
```

- O Alex fornece `alexGetUserState` e `alexSetUserState`

## Regra Alex para Indentação

```
$white_no_nl = $white # \n

:-
-- Ignora espaços dentro da linha
$white_no_nl+            ;
-- Início de nova linha: calcula indentação
\n $white_no_nl*         { handleIndent }
```

- O lexema começa com `\n`; os espaços seguintes dão a coluna

## A Ação `handleIndent`

```haskell
handleIndent :: AlexAction Token
handleIndent (_, _, _, str) len = do
  let col   = 1 + length (takeWhile (`elem` " \t")
                           (drop 1 (take len str)))
  ust <- alexGetUserState
  let stack = lsIndents ust
  case compare col (head stack) of
    GT -> do alexSetUserState ust{lsIndents = col:stack}
             return TkIndent
    EQ -> return TkNewline
    LT -> do let (toClose,rest) = span (> col) stack
             alexSetUserState ust
               { lsIndents = rest
               , lsPending = replicate (length toClose - 1) TkDedent }
             return TkDedent
```

## Fim de Arquivo (`alexEOF`)

```haskell
-- O Alex chama alexEOF quando a entrada termina.
alexEOF :: Alex Token
alexEOF = do
  ust <- alexGetUserState
  case lsIndents ust of
    [_]    -> return TkEOF   -- só o nível base
    (_:rest) -> do
      alexSetUserState ust
        { lsIndents = rest
        , lsPending = replicate (length rest - 1) TkDedent ++ [TkEOF] }
      return TkDedent
    []     -> return TkEOF
```

## `lexer` para o Happy

- Happy pede um token de cada vez via continuação (`%lexer`)
- A ação só retorna **um** token; múltiplos DEDENTs ficam em `lsPending`
- `lexer` drena a fila antes de chamar `alexMonadScan`:

```haskell
lexer :: (Token -> Alex a) -> Alex a
lexer cont = do
  ust <- alexGetUserState
  case lsPending ust of
    (t:ts) -> do
      alexSetUserState ust { lsPending = ts }
      cont t
    [] -> alexMonadScan >>= cont
```

## Tokens com Indentação

```
%token
  ident  { TkIdent $$ }   int    { TkInt $$ }
  '='    { TkAssign }     ':'    { TkColon }
  'if'   { TkIf }         'else' { TkElse }
  'while'{ TkWhile }
  INDENT { TkIndent }     DEDENT { TkDedent }
  NL     { TkNewline }    EOF    { TkEOF }
```

## Gramática com Blocos Indentados

```
Program : Stmts EOF                            { $1 }

Block : INDENT Stmts DEDENT                    { $2 }

Stmts : {- vazio -}                            { [] }
      | Stmts Stmt                             { $1 ++ [$2] }

Stmt : ident '=' Expr NL                       { Assign $1 $3 }
     | 'if' Expr ':' NL Block                  { If $2 $5 Nothing }
     | 'if' Expr ':' NL Block 'else' ':' NL Block
                                               { If $2 $5 (Just $9) }
     | 'while' Expr ':' NL Block               { While $2 $5 }
```

## Gramática com Blocos Indentados

- `Block : INDENT Stmts DEDENT` é **idêntico** a `Block : '{' Stmts '}'`
- O parser LALR trata `INDENT`/`DEDENT` como tokens normais
- A gramática permanece livre de contexto

## Exemplo de Tokenização

Entrada:
```python
x = 5
if x > 0:
    y = x + 1
    while y > 0:
        y = y - 1
```

## Exemplo de Tokenização

Fluxo de tokens gerado pelo lexer:
```
x  =  5  NL
if  x  >  0  :  NL
INDENT
  y  =  x  +  1  NL
  while  y  >  0  :  NL
  INDENT
    y  =  y  -  1  NL
  DEDENT
DEDENT
EOF
```

## Comparação das Abordagens

|                  | **Megaparsec** `indentBlock`     | **Alex + Happy** (`monadUserState`)   |
|------------------|----------------------------------|---------------------------------------|
| Onde age         | No parser                        | No lexer (Alex)                       |
| Mecanismo        | Verifica coluna corrente         | Pilha de colunas; emite INDENT/DEDENT |
| Estado           | Implícito no combinator          | `AlexUserState` + `lsPending`         |
| Gramática        | Sem alteração                    | Usa INDENT/DEDENT como tokens normais |
| Erros            | Reportados com linha/col         | Token inesperado                      |
| Usado em         | Parsers Megaparsec, dhall        | Python, GHC (regra de layout)         |

# Conclusão

## Conclusão

- Apresentamos a linguagem do gerador de analisadores sintáticos LALR Happy.

- Apresentamos um exemplo de uma gramática de expressões.

## Conclusão

- **Indentação em parsers LALR**: injetar `INDENT`/`DEDENT` no lexer transforma
  o problema em delimitação convencional de blocos
- O Alex com `monadUserState` integra o estado da pilha diretamente na mônada do lexer
- O parser Happy trata `INDENT`/`DEDENT` como tokens normais — sem alterações na gramática
