---
title: "Análise Descendente Recursiva"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a técnica de análise sintática descendente recursiva.

- Mostrar como combinadores de parsing implementam essa estratégia em Haskell.

# Análise Descendente

## Análise Descendente Recursiva

- Técnica para construir analisadores sintáticos como um **conjunto de funções**
- Uma função por não-terminal da gramática

## Análise Descendente Recursiva

- A chamada de funções reflete a estrutura das produções
- Em Haskell: abordagem elegante com **combinadores de parsing**
- Um parser é tratado como um **valor de primeira classe**

## O Tipo `Parser`

```haskell
newtype Parser s a =
  Parser { runParser :: [s] -> [(a, [s])] }
```

- `s`: tipo dos símbolos de entrada (ex.: `Char`, `Token`)
- `a`: tipo do resultado (ex.: `Exp`, `[Token]`)

## O Tipo `Parser`

- Retorna **lista de pares** (resultado, entrada restante)
- Lista vazia `[]` significa **falha**
- Lista com vários elementos significa **ambiguidade**

## Resultados

- Sucesso sem não determinismo.
  - Apenas um resultado.

```haskell
runParser (symbol 'a') "abc"
-- → [('a', "bc")]    -- sucesso: consome 'a', resta "bc"
```

## Resultados

- Falha: Lista vazia de resultados

```haskell
runParser (symbol 'x') "abc"
-- → []               -- falha: 'a' ≠ 'x'
```

## Resultados

- Mais de um resultado: não determinismo
  - Pode resultar em backtracking.

```haskell
runParser (item <|> item) "abc"
-- → [('a', "bc"), ('a', "bc")]
```

## Resultados

- Parsers determinísticos retornam no máximo um par
- A lista permite parsers **não-determinísticos** de forma elegante

# Instâncias de Classes de Tipos

## Functor

- Um parser é um `Functor`
  - Responsável por executar ações.
  - Ex. Construir AST.

```haskell
instance Functor (Parser s) where
  fmap f p = Parser (\s ->
    [(f x, s') | (x, s') <- runParser p s])
```

## Functor

- Transforma o resultado sem modificar o que é consumido
- Exemplo: `EInt <$> naturalParser` aplica `EInt` ao resultado

## Applicative

- Concatenação (sequência) de parsers.

```haskell
instance Applicative (Parser s) where
  pure a    = Parser (\ts -> [(a, ts)])
  p1 <*> p2 = Parser (\s ->
    [(f x, s2) | (f, s1) <- runParser p1 s
               , (x, s2) <- runParser p2 s1])
```

## Applicative

- `pure a`: sempre tem sucesso sem consumir entrada
- `p1 <*> p2`: executa `p1` e depois `p2` com a entrada restante

## Alternative

- Escolha entre dois parsers.

```haskell
instance Alternative (Parser t) where
  empty     = Parser (\_ -> [])
  p1 <|> p2 = Parser (\s ->
    runParser p1 s ++ runParser p2 s)
```

## Alternative

- `empty`: sempre falha
- `p1 <|> p2`: tenta ambas as alternativas (concatena resultados)
- Devido à avaliação lazy, `p2` só é avaliado se `p1` falhar

## Monad

- Permite a definição de parsers que dependem do resultado de um parser
  anterior.

```haskell
instance Monad (Parser t) where
  return = pure
  p >>= f = Parser (\ts -> concat
    [ runParser (f a) cs'
    | (a, cs') <- runParser p ts ])
```

## Monad

- Permite que o segundo parser **dependa do resultado** do primeiro
- Habilita notação `do` para parsers mais legíveis

# Combinadores Primitivos

## Combinador `item`

```haskell
-- Consome um símbolo qualquer
item :: Parser t t
item = Parser (\ts -> case ts of
  []     -> []
  (c:cs) -> [(c, cs)])
```

## Combinador `sat`

```haskell
-- Consome um símbolo se satisfaz o predicado
sat :: (t -> Bool) -> Parser t t
sat p = do
  t <- item
  if p t then return t else mzero
```

## Combinador `symbol`

```haskell
symbol :: Eq s => s -> Parser s s
symbol c = sat (c ==)
```

## Combinador `token`

```haskell
token :: Eq s => [s] -> Parser s [s]
token = mapM symbol
```

## Combinador `digit`

```haskell
digit :: Parser Char Int
digit = f <$> sat isDigit
  where f c = ord c - ord '0'
```

## Combinador `natural`

```haskell
natural :: Parser Char Int
natural = foldl (\a b -> a*10 + b) 0 <$> many1 digit
```

# Combinadores de Alto Nível

## Repetição

```haskell
-- Um ou mais
many :: Parser s a -> Parser s [a]
many p = (:) <$> p <*> many p <|> pure []
```

## Repetição

```haskell
-- Um ou mais
many1 :: Parser s a -> Parser s [a]
many1 p = (:) <$> p <*> many p
```

## Opção

```
-- Zero ou um
option :: Parser s a -> a -> Parser s a
option p v = p <|> succeed v
```

## Delimitadores

```haskell
-- Reconhece p entre dois delimitadores
pack :: Parser s a -> Parser s b -> Parser s c -> Parser s b
pack p r q = pi32 <$> p <*> r <*> q
```

## Delimitadores

```haskell
-- Expressão entre parênteses:
parens p = pack (symbol '(') p (symbol ')')
```

## Separadores

```haskell
-- Lista separada por delimitador
listOf :: Parser s a -> Parser s b -> Parser s [a]
listOf p s = list <$> p <*> many (pi22 <$> s <*> p)
```

## Repetição Gulosa

```haskell
determ :: Parser s b -> Parser s b
determ p = Parser (\ts -> case runParser p ts of
  []    -> []
  (x:_) -> [x])

greedy  :: Parser s b -> Parser s [b]
greedy  = determ . many
```

## Operadores

- Para gramáticas da forma $E \to E \oplus T \mid T$:

- `chainl`: associatividade **à esquerda** — `1+2+3` → `(1+2)+3`

```haskell
chainl :: Parser s a -> Parser s (a -> a -> a) -> Parser s a
chainl pe po = h <$> pe <*> many (j <$> po <*> pe)
  where j op x = (`op` x)
        h x fs = foldl (flip ($)) x fs
```

## Operadores

- Para gramáticas da forma $E \to T \oplus E \mid T$:

- `chainr`: associatividade **à direita** — `1+2+3` → `1+(2+3)`

```haskell
chainr :: Parser s a -> Parser s (a -> a -> a) -> Parser s a
chainr pe po = h <$> many (j <$> pe <*> po) <*> pe
  where j x op = (x `op`)
        h fs x = foldr ($) x fs
```

# Parser de Expressões

## Gramática e Tokens

```haskell
data Token = Id String | Number Int | Add | Mult
           | LParen | RParen deriving (Eq, Show)

data Expr = Var String | Lit Int
          | Expr :+: Expr | Expr :*: Expr
```

## O Combinador `gen`

```haskell
type Op s a = (s, a -> a -> a)

gen :: Eq s => [Op s a] -> Parser s a -> Parser s a
gen ops p = chainl p (choice (map f ops))
  where f (s, c) = const c <$> symbol s
```

- `gen ops p` reconhece expressões com operadores de `ops` e operandos de `p`
- Associatividade à esquerda via `chainl`

# Parser de Expressões

## Parser de Expressões

- $E \to E + T \,|\, T$

```haskell
exprParser :: Parser Token Expr
exprParser = addtable `gen` termParser
  where addtable = [(Add, (:+:))]
```

## Parser de Expressões

- $T \to T * F \,|\, F$

```haskell
termParser :: Parser Token Expr
termParser = multable `gen` factParser
  where multable = [(Mult, (:*:))]
```

## Parser de Expressões

```haskell
factParser :: Parser Token Expr
factParser = numParser <|> varParser
          <|> pack (symbol LParen) 
                   exprParser 
                   (symbol RParen)
```

# Megaparsec

## Por que Megaparsec?

- A biblioteca didática é para ensino; **Megaparsec** é para produção
- Mensagens de erro detalhadas: linha, coluna, contexto, o que era esperado

## Por que Megaparsec?

- Melhor desempenho com _committed choice_
- Combinador `makeExprParser` para hierarquias de precedência

## O Tipo Parser no Megaparsec

```haskell
type Parser a = Parsec Void String a 
-- Parsec tipo-de-erro tipo-de-entrada tipo-de-resultado
```

- `Void`: sem tipo de erro customizado (usa os padrões da biblioteca)
- `String`: entrada como lista de caracteres

## Tratamento de Espaços

- Remover espaços e lidar com comentários

```haskell
sc :: Parser ()
sc = L.space space1 lineCmnt blockCmnt
  where lineCmnt  = L.skipLineComment "//"
        blockCmnt = L.skipBlockComment "/*" "*/"
```

## Tokens

```
lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc  -- consome espaço após o token

symbol :: String -> Parser String
symbol = L.symbol sc

parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")
```

## Operadores com `makeExprParser`

```haskell
opTable :: [[Operator Parser Exp]]
opTable
  = [ [ infixL (:*:) "*" ]   -- maior precedência
    , [ infixL (:+:) "+" ]   -- menor precedência
    ]
  where infixL op sym = InfixL $ op <$ symbol sym
```

## Operadores

- Lista externa: do **maior** para o **menor** nível de precedência
- Lista interna: operadores de mesma precedência
- `InfixL`: associatividade à esquerda; `InfixR`: à direita

## Parser com `makeExprParser`

```haskell
termP :: Parser Exp
termP = parens expP <|> EInt <$> int

expP :: Parser Exp
expP = makeExprParser termP opTable
```

## Parser com `makeExprParser`

- `makeExprParser` constrói automaticamente toda a hierarquia de precedências
- Sem necessidade de codificar manualmente cada nível como função separada

# Linguagens Sensíveis à Indentação

## O Problema da Indentação

- Linguagens como Python e Haskell usam a **indentação** para delimitar blocos

```python
x = 5
if x > 0:
    y = x + 1   # bloco do if
    if y > 3:
        z = y * 2  # bloco aninhado
```

## O Problema da Indentação

- A gramática passa a depender da **posição** dos tokens, não só dos tokens
- Um consumidor de espaços convencional descarta quebras de linha — perde a estrutura

## Dois Consumidores de Espaço

```haskell
-- Consome espaços/tabs dentro de uma linha (NÃO newlines)
sc :: Parser ()
sc = L.space
       (void $ takeWhile1P Nothing (\c -> c==' ' || c=='\t'))
       (L.skipLineComment "--")
       empty

-- Consome tudo, incluindo newlines (ENTRE linhas)
scn :: Parser ()
scn = L.space space1 (L.skipLineComment "--") empty

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc   -- consome espaço pós-token (sem newlines)
```

## Dois Consumidores de Espaço

- **`sc`**: usado com `lexeme` para cada token léxico dentro de uma linha
- **`scn`**: passado aos combinadores de indentação; salta de linha verificando coluna

## Combinadores de Indentação

| Combinador      | Função                                                             |
|-----------------|--------------------------------------------------------------------|
| `L.indentLevel` | Devolve a coluna atual como `Pos`                                  |
| `L.indentGuard` | Exige que o próximo token satisfaça GT/EQ/LT em relação a uma col |
| `L.nonIndented` | Exige que o parser comece na coluna 1                              |
| `L.indentBlock` | Parseia cabeçalho + bloco indentado de itens                       |

## `indentBlock` e `IndentOpt`

```haskell
indentBlock :: m ()               -- scn
            -> m (IndentOpt m a b) -- parser do cabeçalho
            -> m a

data IndentOpt m a b
  = IndentNone a
  | IndentMany (Maybe Pos) ([b] -> m a) (m b)  -- 0 ou mais itens
  | IndentSome (Maybe Pos) ([b] -> m a) (m b)  -- 1 ou mais itens
```

## `indentBlock` — Funcionamento

1. Executa o parser do **cabeçalho** → obtém `IndentOpt`
2. Se `IndentNone a`: devolve `a`
3. Se `IndentMany`/`IndentSome`:
   - Usa `scn` para avançar ao **primeiro item** → registra coluna de referência
   - Cada item subsequente deve estar **exatamente** na mesma coluna
   - Qualquer desvio encerra o bloco

## Exemplo: Bloco de Declarações

```haskell
-- Bloco: um ou mais stmts no mesmo nível de indentação
block :: Parser [Stmt]
block = L.indentBlock scn
          (return (L.IndentSome Nothing return stmt))
```

## Exemplo: `if` com bloco

```haskell
ifStmt :: Parser Stmt
ifStmt = L.indentBlock scn $ do
  rword "if"
  cond <- expr
  symbol ":"
  return (L.IndentSome Nothing (mkIf cond) stmt)
  where
    mkIf cond body = do
      elseBody <- optional elseBlock
      return (If cond body elseBody)
```

## Exemplo: Programa Completo

```haskell
-- Nível mais externo: todas as stmts devem estar na coluna 1
program :: Parser [Stmt]
program = scn *> many (L.nonIndented scn stmt) <* eof
```

- `L.nonIndented scn p`: garante que `p` começa na coluna 1
- Erro de indentação reportado com linha e coluna exatas

## Resultado do Parsing

Entrada:
```python
x = 5
if x > 0:
    y = x + 1
    while y > 0:
        y = y - 1
```

AST resultante:
```haskell
[ Assign "x" (Lit 5)
, If (BinOp Gt (Var "x") (Lit 0))
     [ Assign "y" (BinOp Add (Var "x") (Lit 1))
     , While (BinOp Gt (Var "y") (Lit 0))
             [Assign "y" (BinOp Sub (Var "y") (Lit 1))]
     ] Nothing
]
```

## Vantagens e Limitações

**Vantagens**
- Integração natural: indentação verificada durante o parsing
- Mensagens de erro com linha e coluna precisas
- Combinável com outros delimitadores

**Limitações**
- Casos complexos (regra de layout completa do Haskell) requerem injeção de tokens no lexer

# Conclusão

## Conclusão

- **Combinadores de parsing** tratam parsers como valores de primeira classe
- O tipo `Parser s a` retorna lista de pares (resultado, entrada restante)
- Instâncias de `Functor`, `Applicative`, `Alternative`, `Monad` dão
  expressividade

## Conclusão

- Primitivos: `item`, `sat`, `symbol`; combinadores: `many`, `option`, `pack`,
  `chainl`
- O combinador `gen` + `chainl` resolve associatividade sem transformar a
  gramática

## Conclusão

- **Megaparsec**: `indentBlock` + dois consumidores de espaço tratam
  indentação diretamente no parser
- **Alternativa**: injetar `INDENT`/`DEDENT` no lexer (abordagem do capítulo 11)
