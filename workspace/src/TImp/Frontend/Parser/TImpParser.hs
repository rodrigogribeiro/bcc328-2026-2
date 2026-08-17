module TImp.Frontend.Parser.TImpParser (timpParser) where

import Control.Monad.Combinators.Expr
import Text.Megaparsec

import TImp.Frontend.Lexer.TImpLexer
import TImp.Frontend.Syntax.TImpSyntax

-- Entry point

timpParser :: String -> Either String TImp
timpParser s = case parse (sc *> programP <* eof) "" s of
  Left err -> Left (errorBundlePretty err)
  Right p  -> Right p

-- Program and declarations

programP :: Parser TImp
programP = TImp <$> many declP <*> many stmtP

declP :: Parser Decl
declP = DRecord <$> recordDeclP
    <|> DFunc   <$> funcDeclP

recordDeclP :: Parser RecordDecl
recordDeclP = do
  rword "record"
  name   <- identifier
  fields <- braces (many fieldDeclP)
  pure (RecordDecl name fields)

fieldDeclP :: Parser FieldDecl
fieldDeclP = do
  f <- identifier
  _ <- symbol ":"
  t <- tyP
  _ <- semi
  pure (FieldDecl f t)

funcDeclP :: Parser FuncDecl
funcDeclP = do
  rword "fn"
  name   <- identifier
  params <- parens (sepBy paramP comma)
  _      <- symbol ":"
  rt     <- retTyP
  body   <- braces (many stmtP)
  pure (FuncDecl name params rt body)

paramP :: Parser Param
paramP = Param <$> identifier <* symbol ":" <*> tyP

retTyP :: Parser RetTy
retTyP = RTVoid <$  rword "void"
     <|> RTTy   <$> tyP

tyP :: Parser Ty
tyP = TInt     <$  rword "int"
  <|> TBool    <$  rword "bool"
  <|> TString  <$  rword "string"
  <|> TRecord  <$> identifier   -- user-defined record type

-- Statements

stmtP :: Parser Stmt
stmtP
  =   declStmtP
  <|> try identStmtP   -- x := e;  |  x.f := e;  |  f(args);
  <|> readP
  <|> printP
  <|> ifP
  <|> whileP
  <|> returnP

declStmtP :: Parser Stmt
declStmtP = do
  rword "var"
  v <- identifier
  _ <- symbol ":"
  t <- tyP
  _ <- symbol "="
  e <- expP
  _ <- semi
  pure (SDecl v t e)

-- Statements that start with an identifier: assignment, field assignment,
-- or void function call.
identStmtP :: Parser Stmt
identStmtP = do
  v <- identifier
  fieldAssignTail v <|> callTail v <|> assignTail v
  where
    fieldAssignTail v = try $ do
      _ <- symbol "."
      f <- identifier
      _ <- symbol ":="
      e <- expP
      _ <- semi
      pure (SFieldAssign v f e)
    callTail v = try $ do
      args <- parens (sepBy expP comma)
      _    <- semi
      pure (SCall v args)
    assignTail v = do
      _ <- symbol ":="
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
  b1 <- braces (many stmtP)
  rword "else"
  b2 <- braces (many stmtP)
  pure (SIf e b1 b2)

whileP :: Parser Stmt
whileP = do
  rword "while"
  e <- expP
  b <- braces (many stmtP)
  pure (SWhile e b)

returnP :: Parser Stmt
returnP = do
  rword "return"
  me <- optional (try expP)
  _  <- semi
  pure (SReturn me)

-- Expressions

-- Operator table (highest to lowest precedence).
opTable :: [[Operator Parser Exp]]
opTable =
  [ [ Prefix (Not <$ rword "not") ]
  , [ infixL (:*:)  "*"
    , infixL (:/:)  "/"
    ]
  , [ infixL (:+:)  "+"
    , infixL (:-:)  "-"
    ]
  , [ InfixL ((:<=:) <$ try (symbol "<="))
    , InfixL ((:>=:) <$ try (symbol ">="))
    , InfixL ((:!=:) <$ try (symbol "!="))
    , InfixL ((:=:)  <$ try (symbol "=="))
    , InfixL (((:<:)) <$ symbol "<")
    , InfixL ((:>:)  <$ symbol ">")
    ]
  , [ infixL (:&&:) "&&" ]
  , [ infixL (:||:) "||" ]
  ]
  where
    infixL op sym = InfixL (op <$ symbol sym)

expP :: Parser Exp
expP = makeExprParser atomP opTable

-- An atom followed by zero or more ".field" suffixes.
atomP :: Parser Exp
atomP = do
  base   <- baseAtomP
  fields <- many (symbol "." *> identifier)
  pure (foldl EField base fields)

baseAtomP :: Parser Exp
baseAtomP
  =   parens expP
  <|> EBool True  <$  rword "true"
  <|> EBool False <$  rword "false"
  <|> EString     <$> strLit
  <|> EInt        <$> intLit
  <|> try newP
  <|> try callExprP   -- f(args) — must precede EVar
  <|> EVar        <$> identifier

newP :: Parser Exp
newP = do
  rword "new"
  name   <- identifier
  fields <- braces (sepBy fieldInitP comma)
  pure (ENew name fields)

fieldInitP :: Parser (Field, Exp)
fieldInitP = do
  f <- identifier
  _ <- symbol "="
  e <- expP
  pure (f, e)

callExprP :: Parser Exp
callExprP = do
  name <- identifier
  args <- parens (sepBy expP comma)
  pure (ECall name args)
