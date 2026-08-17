---
title: "Geradores de Analisadores Léxicos"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentação da linguagem do Alex e seu uso para especificação de analisadores
  léxicos em Haskell.

# Motivação

## Motivação

- Construir analisadores léxicos manualmente é trabalhoso e propenso a erros
- A teoria (ER → AFN → AFD) é sólida, mas implementar o pipeline é repetitivo

## Motivação

- **Alex** automatiza esse processo para Haskell
- Dado uma especificação de tokens em ERs, Alex gera um analisador léxico
  eficiente
- Usado na prática: o próprio GHC usa Alex para sua análise léxica

# O que é o Alex?

## O que é o Alex?

- Gerador de analisadores léxicos para **Haskell**
- Análogo ao `flex` (C) e ao `JFlex` (Java)

## O que é o Alex?

- Recebe um arquivo `.x` com especificações de tokens
- Gera um módulo Haskell com o analisador léxico completo
- Usa o algoritmo AFD para reconhecimento eficiente

# Sessões de um Arquivo .x

## Seções de um Arquivo `.x`

```
{ cabeçalho Haskell }

%wrapper "..."
macros e configurações

tokens :-
  regras léxicas

{ rodapé Haskell }
```

## Seções de um Arquivo `.x`

1. **Cabeçalho**: módulo e imports Haskell
2. **Diretivas**: wrapper e macros de ERs
3. **Regras**: padrões mapeados a ações
4. **Rodapé**: funções auxiliares

# Definindo Tokens

## Tipos de Tokens para Exp

```haskell
data Token = Token {
      pos    :: (Int, Int)   -- (Linha, Coluna)
    , lexeme :: Lexeme
    } deriving (Eq, Show)

data Lexeme
  = TNumber Int | TLParen | TRParen
  | TPlus | TTimes | TEOF
  deriving (Eq, Show)
```

## Tipos de Tokens para Exp

- Mesma estrutura vista no capítulo de análise ad-hoc
- A posição `(linha, coluna)` é essencial para mensagens de erro
- `TEOF` marca o fim de entrada

# Sintaxe de Expressões Regulares no Alex

## Classes de Caracteres

| Padrão     | Significado                                  |
| ---------- | -------------------------------------------- |
| `[0-9]`    | Qualquer dígito de 0 a 9                     |
| `[a-zA-Z]` | Qualquer letra minúscula ou maiúscula        |
| `[^\"]`    | Qualquer coisa **exceto** aspas duplas       |
| `$digit`   | Conjunto de caracteres definido pelo usuário |

## Operadores de Repetição e Combinação

| Operador | Significado                       |
| -------- | --------------------------------- |
| `e*`     | Zero ou mais repetições de `e`    |
| `e+`     | Uma ou mais repetições de `e`     |
| `e?`     | Zero ou uma ocorrência (opcional) |

## Operadores de Repetição e Combinação

| Operador   | Significado                       |
| ---------- | --------------------------------- |
| `.`        | Qualquer caractere exceto `\n`    |
| `"str"`    | A string literal `str` exatamente |
| `e1 \| e2` | Alternativa: `e1` ou `e2`         |

## Exemplos de Padrões

```
$digit    = 0-9  -- classe: dígitos
@number   = $digit+ -- macro: um ou mais dígitos
@ident    = [a-zA-Z][a-zA-Z0-9_]*  -- identificador

-- Hexadecimal ou octal:
0(x[0-9a-fA-F]+ | o[0-7]+)
```

- Macros com `@` tornam as regras mais legíveis
- Conjuntos com `$` definem classes de caracteres reutilizáveis

# Estrutura do Arquivo Alex

## Cabeçalho e Macros

```haskell
{
{-# OPTIONS_GHC -Wno-name-shadowing #-}
module Exp.Frontend.Lexer.Alex.ExpLexer where

import Control.Monad
import Exp.Frontend.Lexer.Token
}

%wrapper "monadUserState"

$digit = 0-9
@number = $digit+
```

## Wrappers Disponíveis

| Wrapper | Características                                       |
| ------- | ----------------------------------------------------- |
| `basic` | Processa `String` de forma simples e pura             |
| `posn`  | Adiciona informação de linha e coluna automaticamente |

## Wrappers Disponíveis

| Wrapper          | Características                            |
| ---------------- | ------------------------------------------ |
| `monad`          | Executa dentro de uma mônada `Alex`        |
| `monadUserState` | Mônada com estado customizado pelo usuário |

## Wrappers Disponíveis

- A principal diferença: controle sobre o estado e os efeitos
- `monadUserState` é o mais flexível e poderoso

## Regras Léxicas

```
tokens :-
    -- espaços e comentários de linha
    <0> $white+       ;
    <0> "//" .*       ;
    -- tokens significativos
    <0> @number       { mkNumber }
    <0> "("           { simpleToken TLParen }
    <0> ")"           { simpleToken TRParen }
    <0> "+"           { simpleToken TPlus }
    <0> "*"           { simpleToken TTimes }
```

## Regras Léxicas

- Regras sem ação (`;`) descartam o match silenciosamente
- `mkNumber` cria um token com o valor inteiro do número
- `simpleToken` cria um token sem valor associado

# Start Codes e Comentários em Bloco

## Comentários Aninhados

```c
/* comentário externo
   /* comentário interno */
   ainda no externo
*/
```

## Comentários Aninhados

- Comentários em bloco podem ser **aninhados**
- O analisador precisa contar os níveis de aninhamento
- Não é possível expressar isso com uma simples ER

## Solução: Start Codes

- Start codes permitem ao analisador ter **múltiplos modos**
- `<0>`: modo normal de análise
- `<state_comment>`: modo "dentro de comentário em bloco"
- O analisador muda de modo conforme encontra `/*` e `*/`

## Regras com Start Codes

```
-- comentário em bloco:
<0>             "/*"  { nestComment `andBegin` state_comment }
<0>             "*/"  { \_ _ -> alexError "Unexpected close comment!" }
<state_comment> "/*"  { nestComment }
<state_comment> "*/"  { unnestComment }
<state_comment> .     ;
<state_comment> \n    ;
```

## Regras com Start Codes

- `andBegin state_comment`: muda para o modo de comentário
- Em `state_comment`: ignora tudo exceto `/*` e `*/`
- `*/` sem `/*` correspondente → erro imediato

## Def. do Estado

```haskell
data AlexUserState = AlexUserState
  { nestLevel :: Int   -- nível de aninhamento de comentários
  }

alexInitUserState :: AlexUserState
alexInitUserState = AlexUserState { nestLevel = 0 }
```

## Def. do Estado

- `nestLevel = 0`: fora de qualquer comentário
- `nestLevel = 1`: dentro de `/* ... */`
- `nestLevel = 2`: dentro de `/* /* ... */ */`

## Funções de Aninhamento

- Aumentando o aninhamento

```haskell
nestComment :: AlexInput -> Int -> Alex Token
nestComment _ _ = do
    modify (\s -> s { nestLevel = nestLevel s + 1 })
    alexMonadScan
```

## Funções de Aninhamento

- Diminuindo o aninhamento

```haskell
unnestComment :: AlexInput -> Int -> Alex Token
unnestComment _ _ = do
    st <- get
    let level = nestLevel st - 1
    put st { nestLevel = level }
    if level == 0
      then alexSetStartCode 0 >> alexMonadScan
      else alexMonadScan
```

## Manipulação do Estado

```haskell
get    :: Alex AlexUserState
put    :: AlexUserState -> Alex ()
modify :: (AlexUserState -> AlexUserState) -> Alex ()
```

## Manipulação do Estado

- `get`: lê o estado customizado atual
- `put`: substitui o estado por um novo
- `modify`: aplica uma função de transformação ao estado
- Padrão idêntico à mônada de estado de Haskell (`State`)

# Geração e Uso

## Como Gerar o Analisador

```bash
alex ExpLexer.x           # gera ExpLexer.hs
alex -o ExpLexer.hs ExpLexer.x  # especifica o arquivo de saída
```

## Como Gerar o Analisador

- Com Cabal: automático se `alex` está em `build-tool-depends`
- O arquivo gerado é um módulo Haskell normal

## Interface do Analisador Gerado

```haskell
-- Executa o analisador sobre uma String
runAlex :: String -> Alex a -> Either String a

-- Obtém o próximo token
alexMonadScan :: Alex Token

-- Sinaliza um erro
alexError :: String -> Alex a
```

## Usando o Analisador em Produção

```haskell
-- Obtém todos os tokens de uma String
tokenize :: String -> Either String [Token]
tokenize input = runAlex input loop
  where
    loop = do
      tok <- alexMonadScan
      case lexeme tok of
        TEOF -> return []
        _    -> (tok :) <$> loop
```

# Conclusão

## Conclusão

- Nesta aula apresentamos o gerador Alex.

- Criação automática de analisadores léxicos eficientes a partir de expressões
  regulares.

- Próximas aulas: Análise sintática.
