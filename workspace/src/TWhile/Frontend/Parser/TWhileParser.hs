module TWhile.Frontend.Parser.TWhileParser (twhileParser) where

import Control.Monad.Combinators.Expr
import Text.Megaparsec

import TWhile.Frontend.Lexer.TWhileLexer
import TWhile.Frontend.Syntax.TWhileSyntax

-- Top-level entry point.
-- Parses a complete TWhile program from a string.

twhileParser :: String -> Either String TWhile
twhileParser s = case parse (sc *> programP <* eof) "" s of
    Left err -> Left (errorBundlePretty err)
    Right p  -> Right p

-- Program: a sequence of statements

programP :: Parser TWhile
programP = TWhile <$> many stmtP

-- Block: a sequence of statements enclosed in braces

blockP :: Parser Block
blockP = braces (many stmtP)

stmtP :: Parser Stmt
stmtP
    =   declP
    <|> assignP
    <|> readP
    <|> printP
    <|> ifP
    <|> whileP

declP :: Parser Stmt
declP = do
    rword "var"
    v <- identifier
    _ <- symbol ":"
    t <- tyP
    _ <- symbol "="
    e <- expP
    _ <- semi
    pure (SDecl v t e)

assignP :: Parser Stmt
assignP = do
    v <- try (identifier <* symbol ":=")
    e <- expP
    _ <- semi
    pure (SAssign v e)

readP :: Parser Stmt
readP = do
    rword "read"
    e <- expP
    v <- identifier
    _ <- semi
    pure (SRead e v)

printP :: Parser Stmt
printP = do
    rword "print"
    e <- expP
    _ <- semi
    pure (SPrint e)

ifP :: Parser Stmt
ifP = do
    rword "if"
    e  <- expP
    b1 <- blockP
    rword "else"
    b2 <- blockP
    pure (SIf e b1 b2)

whileP :: Parser Stmt
whileP = do
    rword "while"
    e <- expP
    b <- blockP
    pure (SWhile e b)

tyP :: Parser Ty
tyP
    =   TInt    <$ rword "int"
    <|> TBool   <$ rword "bool"
    <|> TString <$ rword "string"

-- Operator table (highest to lowest precedence).
opTable :: [[Operator Parser Exp]]
opTable =
    [ [ Prefix (Not <$ rword "not") ]
    , [ infixL (:*:) "*"
      , infixL (:/:) "/"
      ]
    , [ infixL (:+:) "+"
      , infixL (:-:) "-"
      ]
    , [ infixL (:=:) "=="
      , infixL (:<:) "<"
      ]
    , [ infixL (:&&:) "&&" ]
    , [ infixL (:||:) "||" ]
    ]
  where
    infixL op sym = InfixL (op <$ symbol sym)

expP :: Parser Exp
expP = makeExprParser atomP opTable

atomP :: Parser Exp
atomP
    =   parens expP
    <|> EBool True  <$ rword "true"
    <|> EBool False <$ rword "false"
    <|> EString     <$> strLit
    <|> EInt        <$> intLit
    <|> EVar        <$> identifier
