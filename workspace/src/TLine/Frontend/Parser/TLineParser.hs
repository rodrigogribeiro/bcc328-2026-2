module TLine.Frontend.Parser.TLineParser (tlineParser) where

import Control.Monad.Combinators.Expr
import Text.Megaparsec

import TLine.Frontend.Lexer.TLineLexer
import TLine.Frontend.Syntax.TLineSyntax

-- Top-level entry point.
-- Parses a complete TLine program from a string.

tlineParser :: String -> Either String TLine
tlineParser s = case parse (sc *> programP <* eof) "" s of
    Left err -> Left (errorBundlePretty err)
    Right p  -> Right p

-- Program: a sequence of statements

programP :: Parser TLine
programP = TLine <$> many stmtP

-- Statements
--
-- Syntax:
--   var x : ty = exp ;       (declaration)
--   x := exp ;               (assignment)
--   read exp x ;             (read: prompt exp, store in x)
--   print exp ;              (print)

stmtP :: Parser Stmt
stmtP
    =   declP
    <|> assignP
    <|> readP
    <|> printP

-- var x : ty = exp ;
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

-- x := exp ;
assignP :: Parser Stmt
assignP = do
    v <- try (identifier <* symbol ":=")
    e <- expP
    _ <- semi
    pure (SAssign v e)

-- read exp x ;
readP :: Parser Stmt
readP = do
    rword "read"
    e <- expP
    v <- identifier
    _ <- semi
    pure (SRead e v)

-- print exp ;
printP :: Parser Stmt
printP = do
    rword "print"
    e <- expP
    _ <- semi
    pure (SPrint e)

-- Types

tyP :: Parser Ty
tyP
    =   TInt    <$ rword "int"
    <|> TBool   <$ rword "bool"
    <|> TString <$ rword "string"

-- Expressions with operator precedence (highest to lowest):
--   1. not           (prefix, highest)
--   2. *, /          (multiplicative, left-associative)
--   3. +, -          (additive, left-associative)
--   4. ==, <         (comparison, left-associative, lowest)

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
    ]
  where
    infixL op sym = InfixL (op <$ symbol sym)

expP :: Parser Exp
expP = makeExprParser atomP opTable

-- Atomic expressions

atomP :: Parser Exp
atomP
    =   parens expP
    <|> EBool True  <$ rword "true"
    <|> EBool False <$ rword "false"
    <|> EString     <$> strLit
    <|> EInt        <$> intLit
    <|> EVar        <$> identifier
