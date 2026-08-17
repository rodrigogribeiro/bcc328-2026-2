module Lambda.Frontend.Parser.LambdaParser (lambdaParser) where

import Data.Void
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

import Lambda.Frontend.Syntax.Term

type Parser = Parsec Void String

sc :: Parser ()
sc = L.space space1 (L.skipLineComment "--") empty

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: String -> Parser String
symbol = L.symbol sc

parens :: Parser a -> Parser a
parens p = symbol "(" *> p <* symbol ")"

-- A keyword is an exact string not followed by identifier characters.
keyword :: String -> Parser ()
keyword w = lexeme . try $
  string w *> notFollowedBy (alphaNumChar <|> char '_' <|> char '\'')

identifier :: Parser Name
identifier = (lexeme . try) (p >>= check)
  where
    p     = (:) <$> letterChar <*> many (alphaNumChar <|> char '_' <|> char '\'')
    check s
      | s `elem` reserved = fail $ "reserved word: " ++ s
      | otherwise         = return s

reserved :: [String]
reserved = ["true", "false"]

lambdaParser :: String -> Either String Term
lambdaParser s =
  case runParser (sc *> termP <* eof) "" s of
    Left  err -> Left (errorBundlePretty err)
    Right t   -> Right t

-- ---------------------------------------------------------------------------
-- Grammar
--
--   term  ::= lam | app
--   lam   ::= ('λ' | '\') name+ '.' term
--   app   ::= atom+                        (left-associative)
--   atom  ::= var | lit | '(' term ')'
--   lit   ::= integer | 'true' | 'false'
-- ---------------------------------------------------------------------------

termP :: Parser Term
termP = lamP <|> appP

lamP :: Parser Term
lamP = do
    _ <- symbol "\\" <|> symbol "λ"
    xs <- some identifier
    _ <- symbol "."
    body <- termP
    return $ foldr Lam body xs

appP :: Parser Term
appP = foldl1 App <$> some atomP

atomP :: Parser Term
atomP = litP
    <|> Var <$> identifier
    <|> parens termP

litP :: Parser Term
litP = Lit (LBool True)  <$ keyword "true"
   <|> Lit (LBool False) <$ keyword "false"
   <|> Lit . LInt        <$> lexeme (L.signed sc L.decimal)
