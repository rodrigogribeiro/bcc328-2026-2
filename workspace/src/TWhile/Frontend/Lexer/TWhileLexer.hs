module TWhile.Frontend.Lexer.TWhileLexer
  ( Parser
  , sc
  , lexeme
  , symbol
  , parens
  , braces
  , semi
  , rword
  , identifier
  , intLit
  , strLit
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

braces :: Parser a -> Parser a
braces = between (symbol "{") (symbol "}")

semi :: Parser String
semi = symbol ";"

-- Reserved words

reservedWords :: [String]
reservedWords =
  [ "var", "int", "bool", "string"
  , "true", "false", "not"
  , "read", "print"
  , "if", "else", "while"
  ]

-- Reserved word parser: matches the word and ensures it is not
-- a prefix of a longer identifier.

rword :: String -> Parser ()
rword w = (lexeme . try) (string w *> notFollowedBy alphaNumChar)

-- Identifier: starts with a letter, followed by alphanumeric chars.
-- Rejected if it matches a reserved word.

identifier :: Parser String
identifier = (lexeme . try) $ do
    name <- (:) <$> letterChar <*> many alphaNumChar
    if name `elem` reservedWords
      then fail $ "keyword " ++ show name ++ " cannot be used as an identifier"
      else pure name

-- Integer literal (may be negative)

intLit :: Parser Int
intLit = lexeme (L.signed sc L.decimal)

-- String literal: characters between double quotes

strLit :: Parser String
strLit = lexeme (char '"' *> manyTill L.charLiteral (char '"'))
