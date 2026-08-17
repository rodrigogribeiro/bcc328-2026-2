module TExp.Frontend.Lexer.TExpLexer
  ( Parser
  , sc
  , lexeme
  , symbol
  , parens
  , rword
  , reserved
  ) where

import Data.Void
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void String

-- Whitespace and comment handling

sc :: Parser ()
sc = L.space space1 lineCmnt blockCmnt
  where
    lineCmnt  = L.skipLineComment "//"
    blockCmnt = L.skipBlockComment "/*" "*/"

-- Lexeme wrapper: skips trailing whitespace

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: String -> Parser String
symbol = L.symbol sc

parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

-- Reserved words of the language

reserved :: [String]
reserved = ["true", "false", "if", "then", "else", "succ", "pred", "iszero", "0"]

-- Parser for a reserved word: matches the word and ensures it is not
-- followed by an alphanumeric character or underscore, preventing
-- identifiers like "trueVal" from being accepted as "true".

rword :: String -> Parser ()
rword w = (lexeme . try) (string w *> notFollowedBy alphaNumChar)
