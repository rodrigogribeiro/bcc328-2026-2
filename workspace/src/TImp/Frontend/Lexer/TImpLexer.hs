module TImp.Frontend.Lexer.TImpLexer
  ( Parser
  , sc
  , lexeme
  , symbol
  , parens
  , braces
  , semi
  , comma
  , rword
  , identifier
  , intLit
  , strLit
  -- * Tokenizer
  , Token (..)
  , tokenize
  , showTokens
  ) where

import Data.Void
import Text.Megaparsec hiding (Token, showTokens)
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void String

-- Whitespace and comments

sc :: Parser ()
sc = L.space space1 lineCmnt blockCmnt
  where
    lineCmnt  = L.skipLineComment "//"
    blockCmnt = L.skipBlockComment "/*" "*/"

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

comma :: Parser String
comma = symbol ","

-- Reserved words

reservedWords :: [String]
reservedWords =
  [ "var", "int", "bool", "string"
  , "true", "false", "not"
  , "read", "print"
  , "if", "else", "while"
  , "fn", "record", "new", "return", "void"
  ]

rword :: String -> Parser ()
rword w = (lexeme . try) (string w *> notFollowedBy alphaNumChar)

identifier :: Parser String
identifier = (lexeme . try) $ do
  name <- (:) <$> letterChar <*> many alphaNumChar
  if name `elem` reservedWords
    then fail $ "keyword " ++ show name ++ " cannot be used as an identifier"
    else pure name

-- Literals

intLit :: Parser Int
intLit = lexeme (L.signed sc L.decimal)

strLit :: Parser String
strLit = lexeme (char '"' *> manyTill L.charLiteral (char '"'))

-- Tokenizer (for --lex output)

data Token
  = TkKeyword  String
  | TkIdent    String
  | TkInt      Int
  | TkBool     Bool
  | TkString   String
  | TkSymbol   String
  deriving (Eq, Show)

type TokP = Parsec Void String

tokSc :: TokP ()
tokSc = L.space space1 (L.skipLineComment "//") (L.skipBlockComment "/*" "*/")

tokenize :: String -> Either String [Token]
tokenize src = case parse (tokSc *> many tokenP <* eof) "" src of
  Left err -> Left (errorBundlePretty err)
  Right ts -> Right ts

tokenP :: TokP Token
tokenP = choice
  [ kwOrIdent
  , TkInt    <$> L.lexeme tokSc (L.signed tokSc L.decimal)
  , TkBool True  <$ L.symbol tokSc "true"
  , TkBool False <$ L.symbol tokSc "false"
  , TkString <$> L.lexeme tokSc (char '"' *> manyTill L.charLiteral (char '"'))
  , TkSymbol <$> L.lexeme tokSc multicharOp
  , TkSymbol <$> L.lexeme tokSc (fmap (:[]) punctChar)
  ]
  where
    kwOrIdent = L.lexeme tokSc $ do
      name <- (:) <$> letterChar <*> many alphaNumChar
      pure $ if name `elem` reservedWords
               then TkKeyword name
               else TkIdent   name

    multicharOp = choice
      [ string "<="
      , string ">="
      , string "!="
      , string "=="
      , string ":="
      , string "&&"
      , string "||"
      ]

    punctChar = oneOf (":;,(){}.<>!+-*/" :: String)

showTokens :: [Token] -> String
showTokens = unlines . map showTok
  where
    showTok (TkKeyword kw) = "KEYWORD  " ++ kw
    showTok (TkIdent   n)  = "IDENT    " ++ n
    showTok (TkInt     n)  = "INT      " ++ show n
    showTok (TkBool    b)  = "BOOL     " ++ show b
    showTok (TkString  s)  = "STRING   " ++ show s
    showTok (TkSymbol  s)  = "SYMBOL   " ++ s
