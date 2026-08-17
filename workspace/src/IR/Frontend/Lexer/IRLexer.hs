module IR.Frontend.Lexer.IRLexer
  (
    Parser
  , sc
  , lexeme
  , symbol
  , parens
  , braces
  , comma
  , identifier
  , integer
  , kw
  , binOpLit
  , IRToken (..)
  , TokenKind (..)
  , tokenize
  , showTokens
  ) where

import Data.Void
import Text.Megaparsec hiding (Token, showTokens)
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

-- Parser type

type Parser = Parsec Void String

-- Whitespace / comment handling

sc :: Parser ()
sc = L.space space1 (L.skipLineComment "--") (L.skipBlockComment "/*" "*/")

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: String -> Parser String
symbol = L.symbol sc

parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

braces :: Parser a -> Parser a
braces = between (symbol "{") (symbol "}")

comma :: Parser String
comma = symbol ","

-- Reserved words and binary-operator keywords

irConstructors :: [String]
irConstructors =
  [ "func"
  , "CONST", "TEMP", "NAME", "BINOP", "MEM", "CALL", "ESEQ"
  , "MOVE", "EXP", "SEQ", "JUMP", "CJUMP", "LABEL", "RETURN"
  ]

-- Ordered longest-first to avoid prefix ambiguity.
irBinOpNames :: [String]
irBinOpNames =
  [ "ARSHIFT", "LSHIFT", "RSHIFT"
  , "ADD", "SUB", "MUL", "DIV", "MOD"
  , "AND", "XOR", "OR"
  , "NEQ", "LEQ", "GEQ"
  , "EQ", "LT", "GT"
  ]

allKeywords :: [String]
allKeywords = irConstructors ++ irBinOpNames

-- Parse a keyword exactly (not a prefix of a longer identifier).
kw :: String -> Parser ()
kw w = (lexeme . try) (string w *> notFollowedBy alphaNumChar)

-- Parse a binary-operator name token and return it as a string.
binOpLit :: Parser String
binOpLit = lexeme . choice $ map (\w -> try (string w <* notFollowedBy alphaNumChar)) irBinOpNames

-- Parse an identifier that is not a reserved keyword.
identifier :: Parser String
identifier = lexeme . try $ do
  s <- (:) <$> (letterChar <|> char '_') <*> many (alphaNumChar <|> char '_')
  if s `elem` allKeywords
    then fail ("'" ++ s ++ "' is a reserved keyword")
    else return s

-- Parse a (possibly negative) integer literal.
integer :: Parser Int
integer = lexeme (L.signed sc L.decimal)

-- Stand-alone tokenizer

data TokenKind
  = TkKeyword String  -- constructor or operator keyword
  | TkInt     Int
  | TkIdent   String
  | TkLParen
  | TkRParen
  | TkLBrace
  | TkRBrace
  | TkComma
  deriving (Eq, Show)

data IRToken = IRToken
  { tokLine :: Int
  , tokCol  :: Int
  , tokKind :: TokenKind
  } deriving (Eq, Show)

-- Capture source position before consuming the token.
withPos :: Parser TokenKind -> Parser IRToken
withPos p = do
  pos <- getSourcePos
  tk  <- p
  return (IRToken (unPos (sourceLine pos)) (unPos (sourceColumn pos)) tk)

tokenKindP :: Parser TokenKind
tokenKindP = choice
  [ TkKeyword <$> choice (map (\w -> try (string w <* notFollowedBy alphaNumChar)) allKeywords)
  , TkInt     <$> L.signed (return ()) L.decimal
  , TkIdent   <$> ((:) <$> (letterChar <|> char '_') <*> many (alphaNumChar <|> char '_'))
  , TkLParen  <$  char '('
  , TkRParen  <$  char ')'
  , TkLBrace  <$  char '{'
  , TkRBrace  <$  char '}'
  , TkComma   <$  char ','
  ]

allTokensP :: Parser [IRToken]
allTokensP = sc *> many (withPos tokenKindP <* sc) <* eof

-- | Tokenize an IR source string.
tokenize :: String -> Either String [IRToken]
tokenize src = case parse allTokensP "" src of
  Left  err -> Left (errorBundlePretty err)
  Right tks -> Right tks

-- | Render a token list for display.
showTokens :: [IRToken] -> String
showTokens = unlines . map fmt
  where
    fmt (IRToken l c tk) =
      "(" ++ show l ++ "," ++ show c ++ ") " ++ showKind tk
    showKind (TkKeyword w) = "KEYWORD(" ++ w ++ ")"
    showKind (TkInt n)     = "INT(" ++ show n ++ ")"
    showKind (TkIdent s)   = "IDENT(" ++ s ++ ")"
    showKind TkLParen      = "LPAREN"
    showKind TkRParen      = "RPAREN"
    showKind TkLBrace      = "LBRACE"
    showKind TkRBrace      = "RBRACE"
    showKind TkComma       = "COMMA"
