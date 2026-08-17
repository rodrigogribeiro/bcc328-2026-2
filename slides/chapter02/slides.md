---
title: "Introdução à Análise Léxica"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar a importância da análise léxica.

- Apresentar a implementação de um analisador léxico ad-hoc.

# Análise Léxica

## O Papel da Análise Léxica

- Primeira fase do compilador
- Recebe o código-fonte como **sequência de caracteres**
- Agrupa os caracteres em **tokens** significativos

## O Papel da Análise Léxica

- Remove espaços em branco e comentários
- Detecta erros léxicos precocemente (caracteres inválidos, etc.)
- Funciona como a "porta de entrada" que organiza o texto bruto

## O que é um Token?

- Um **token** é um componente indivisível da sintaxe de uma linguagem
- O conjunto de tokens pode ser entendido como o **alfabeto** da linguagem
- Exemplos de tokens: palavras reservadas, identificadores, números, operadores

## O que é um Token?

- O analisador léxico produz uma **lista de tokens** para o analisador sintático
- Cada token carrega sua **categoria** (lexema) e posição no código-fonte

## Estrutura de um Token

```haskell
type Line   = Int
type Column = Int

data Token = Token
  { pos    :: (Line, Column)  -- posição no código-fonte
  , lexeme :: Lexeme          -- categoria do token
  }
```

- A posição é essencial para **mensagens de erro** precisas
- O lexema identifica a categoria do token

# A Linguagem Exp

## Gramática da Linguagem Exp

$$E \to n \mid E + E \mid E * E \mid (E)$$

- $n$: constante numérica inteira
- $+$: operador de adição
- $*$: operador de multiplicação
- $($ e $)$: parênteses para agrupamento
- Linguagem simples: expressões aritméticas básicas

## Tokens da Linguagem Exp

| Token | Construtor    | Descrição                        |
| ----- | ------------- | -------------------------------- |
| `n`   | `TNumber Int` | número inteiro (carrega o valor) |
| `+`   | `TPlus`       | operador de adição               |
| `*`   | `TTimes`      | operador de multiplicação        |

## Tokens da Linguagem Exp

| Token | Construtor | Descrição                  |
| ----- | ---------- | -------------------------- |
| `(`   | `TLParen`  | abre parênteses            |
| `)`   | `TRParen`  | fecha parênteses           |
| EOF   | `TEOF`     | marcador de fim de entrada |

## Definição do Tipo Lexeme

```haskell
data Lexeme
  = TNumber Int   -- número com seu valor inteiro
  | TLParen       -- (
  | TRParen       -- )
  | TPlus         -- +
  | TTimes        -- *
  | TEOF          -- fim de entrada
```

## Definição do Tipo Lexeme

- Cada construtor corresponde a uma categoria de token
- `TNumber` carrega o valor inteiro do número
- Os demais construtores apenas identificam o símbolo

# Analisadores Léxicos Ad-Hoc

## Analisadores Ad-Hoc

- Implementação **manual** e específica para uma linguagem
- Processa caracteres sequencialmente com casamento de padrões

## Analisadores Ad-Hoc

- Não usa geradores automáticos como o Alex
- Adequado para linguagens **pequenas e simples**
- Oferece controle total sobre as mensagens de erro

## Tipo do Analisador

```haskell
-- Versão simples (sem tratamento de erros):
lexer :: String -> [Token]

-- Versão com tratamento de erros:
lexer :: String -> Either String [Token]
```

- `Left msg` indica um **erro léxico** com mensagem `msg`
- `Right tokens` indica **sucesso** com a lista de tokens produzida

## O Tipo Either

```haskell
data Either a b = Left a | Right b
```

- `Left a` representa falha/erro com valor do tipo `a`
- `Right b` representa sucesso com valor do tipo `b`

## Estado do Analisador

```haskell
type State = (Line, Column, String, [Token])
--            ^      ^       ^        ^
--           linha  coluna  dígitos  tokens
--                          acum.    produzidos
```

- `Line`, `Column`: posição atual no arquivo de entrada
- `String`: dígitos consecutivos acumulados (para montar números)
- `[Token]`: tokens reconhecidos até o momento

## Função de Transição

```haskell
transition :: State -> Char -> Either String State
transition state@(l, col, t, ts) c
  | c == '\n'  = mkDigits state c   -- nova linha
  | isSpace c  = mkDigits state c   -- espaço
  | c == '+'   = Right (l, col+1, "", mkToken state TPlus    : ts)
  | c == '*'   = Right (l, col+1, "", mkToken state TTimes   : ts)
  | c == '('   = Right (l, col+1, "", mkToken state TLParen  : ts)
  | c == ')'   = Right (l, col+1, "", mkToken state TRParen  : ts)
  | isDigit c  = Right (l, col+1, c:t, ts)  -- acumula dígito
  | otherwise  = unexpectedCharError l col c
```

## Tratamento de Dígitos

```haskell
mkDigits :: State -> Char -> Either String State
mkDigits state@(l, col, s, ts) c
  | null s      = -- nenhum dígito acumulado: só atualiza posição
      let l'   = if c == '\n' then l + 1 else l
          col' = if isSpace c then col + 1 else col
      in Right (l', col', s, ts)
  | all isDigit s = -- dígitos válidos: cria token TNumber
      let t    = Token (l,col) (TNumber (read $ reverse s))
          l'   = if c == '\n' then l + 1 else l
          col' = if c /= '\n' && isSpace c then col + 1 else col
      in Right (l', col', "", t : ts)
  | otherwise   = unexpectedCharError l col c
```

## A Função `lexer` Completa

```haskell
lexer :: String -> Either String [Token]
lexer = finish . foldl step base
  where
    base          = Right (1, 1, "", [])
    finish        = either Left (Right . extract)
    step (Left e) _ = Left e
    step (Right s) c = transition s c

    extract (l, col, s, ts)
      | null s    = reverse ts
      | otherwise = let n = read (reverse s)
                        t = Token (l, col - length s) (TNumber n)
                    in reverse (t : ts)
```

## Como `foldl` Funciona

```haskell
foldl :: (b -> a -> b) -> b -> [a] -> b
foldl _ v []     = v
foldl f v (x:xs) = foldl f (f v x) xs
```

Exemplo: `sum [1,2,3]` com `foldl (+) 0`:

```
foldl (+) 0 [1,2,3]
= foldl (+) (0+1) [2,3]
= foldl (+) (0+1+2) [3]
= foldl (+) (0+1+2+3) []
= 6
```

- `foldl` percorre a lista **da esquerda para a direita**
- Acumula um resultado a cada passo

## Exemplo de Execução

Entrada: `"2 + 3"`

| Char | Estado (linha, col, dígitos, tokens) |
| ---- | ------------------------------------ |
| `2`  | `(1, 2, "2", [])`                    |
| `_`  | `(1, 3, "", [TNumber 2])`            |
| `+`  | `(1, 4, "", [TPlus, TNumber 2])`     |

## Exemplo de Execução

Entrada: `"2 + 3"`

| Char | Estado (linha, col, dígitos, tokens)     |
| ---- | ---------------------------------------- |
| `_`  | `(1, 5, "", [TPlus, TNumber 2])`         |
| `3`  | `(1, 6, "3", [TPlus, TNumber 2])`        |
| EOF  | extrai → `[TNumber 2, TPlus, TNumber 3]` |

# Vantagens e Desvantagens

## Vantagens dos Analisadores Ad-Hoc

- **Simples de implementar** para linguagens pequenas
- **Controle total** sobre mensagens de erro
- Sem dependências externas (geradores de código)

## Vantagens dos Analisadores Ad-Hoc

- Fácil de entender e depurar para casos simples
- Pode ser altamente otimizado para o caso específico

## Desvantagens dos Analisadores Ad-Hoc

- **Difíceis de manter e extender**:
  - Como adicionar identificadores?
  - Como suportar comentários de linha (`//`)? E comentários em bloco (`/* */`)?

## Desvantagens dos Analisadores Ad-Hoc

- **Ineficientes para estruturas léxicas complexas**
  - Cada nova funcionalidade exige modificar toda a estrutura do estado
  - Não há garantia de correção: é fácil esquecer um caso

## Dificuldades

```
if (x > 0) ift = x + 1;
```

- Como distinguir `if` (palavra reservada) de `ift` (identificador)?
- Como tratar palavras reservadas de forma eficiente?

## Dificuldades

- Para linguagens reais: dezenas de tokens, comentários aninhados, etc.
- Solução: **expressões regulares** + **autômatos finitos**

# Conclusão

## Conclusão

- Análise léxica transforma **texto bruto** em uma **lista de tokens**
- Cada token carrega categoria (lexema) e posição no fonte
- O tipo `Either` de Haskell permite tratamento elegante de erros

## Conclusão

- Analisadores ad-hoc funcionam para linguagens simples
- As limitações motivam o uso de **expressões regulares e autômatos**
