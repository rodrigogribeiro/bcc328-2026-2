module IR.Frontend.Parser.IRParser
  ( parseProgram
  , parseStmt
  , parseExpr
  ) where

import Text.Megaparsec

import IR.Frontend.Syntax.IRSyntax
import IR.Frontend.Lexer.IRLexer

-- Top-level entry points

parseProgram :: String -> Either String Program
parseProgram src = case parse (sc *> many funcDefP <* eof) "" src of
  Left  err  -> Left (errorBundlePretty err)
  Right prog -> Right prog

parseStmt :: String -> Either String Stmt
parseStmt src = case parse (sc *> stmtP <* eof) "" src of
  Left  err  -> Left (errorBundlePretty err)
  Right stmt -> Right stmt

parseExpr :: String -> Either String Expr
parseExpr src = case parse (sc *> exprP <* eof) "" src of
  Left  err  -> Left (errorBundlePretty err)
  Right expr -> Right expr

-- Function definition

funcDefP :: Parser FuncDef
funcDefP = do
  kw "func"
  name   <- identifier
  params <- parens (identifier `sepBy` comma)
  body   <- braces stmtP
  return (FuncDef name params body)

-- Statement parsers

stmtP :: Parser Stmt
stmtP = choice
  [ moveP
  , expStmtP
  , seqP
  , jumpP
  , cjumpP
  , labelStmtP
  , returnP
  ]

moveP :: Parser Stmt
moveP = do
  kw "MOVE"
  (dst, src) <- parens ((,) <$> exprP <* comma <*> exprP)
  return (MOVE dst src)

expStmtP :: Parser Stmt
expStmtP = do
  kw "EXP"
  e <- parens exprP
  return (EXP e)

seqP :: Parser Stmt
seqP = do
  kw "SEQ"
  (s1, s2) <- parens ((,) <$> stmtP <* comma <*> stmtP)
  return (SEQ s1 s2)

jumpP :: Parser Stmt
jumpP = do
  kw "JUMP"
  e <- parens exprP
  return (JUMP e)

cjumpP :: Parser Stmt
cjumpP = do
  kw "CJUMP"
  (e, lt, lf) <- parens ((,,) <$> exprP <* comma <*> identifier <* comma <*> identifier)
  return (CJUMP e lt lf)

labelStmtP :: Parser Stmt
labelStmtP = do
  kw "LABEL"
  l <- parens identifier
  return (LABEL l)

returnP :: Parser Stmt
returnP = do
  kw "RETURN"
  es <- parens (exprP `sepBy` comma)
  return (RETURN es)

-- Expression parsers

exprP :: Parser Expr
exprP = choice
  [ constP
  , tempP
  , nameP
  , binopP
  , memP
  , callP
  , eseqP
  ]

constP :: Parser Expr
constP = do
  kw "CONST"
  n <- parens integer
  return (CONST n)

tempP :: Parser Expr
tempP = do
  kw "TEMP"
  t <- parens identifier
  return (TEMP t)

nameP :: Parser Expr
nameP = do
  kw "NAME"
  l <- parens identifier
  return (NAME l)

binopP :: Parser Expr
binopP = do
  kw "BINOP"
  (op, e1, e2) <- parens ((,,) <$> binOpP <* comma <*> exprP <* comma <*> exprP)
  return (BINOP op e1 e2)

memP :: Parser Expr
memP = do
  kw "MEM"
  e <- parens exprP
  return (MEM e)

callP :: Parser Expr
callP = do
  kw "CALL"
  (ef, args) <- parens ((,) <$> exprP <*> many (comma *> exprP))
  return (CALL ef args)

eseqP :: Parser Expr
eseqP = do
  kw "ESEQ"
  (s, e) <- parens ((,) <$> stmtP <* comma <*> exprP)
  return (ESEQ s e)

-- Binary operator parser

-- Operators must be tried longest-first to avoid prefix ambiguity
-- (e.g. "NEQ" before "EQ", "ARSHIFT" before "RSHIFT").

binOpP :: Parser BinOp
binOpP = choice $ map try
  [ BArsh <$ kw "ARSHIFT"
  , BLsh  <$ kw "LSHIFT"
  , BRsh  <$ kw "RSHIFT"
  , BAdd  <$ kw "ADD"
  , BSub  <$ kw "SUB"
  , BMul  <$ kw "MUL"
  , BDiv  <$ kw "DIV"
  , BMod  <$ kw "MOD"
  , BAnd  <$ kw "AND"
  , BXor  <$ kw "XOR"
  , BOr   <$ kw "OR"
  , BNe   <$ kw "NEQ"
  , BEq   <$ kw "EQ"
  , BLe   <$ kw "LEQ"
  , BLt   <$ kw "LT"
  , BGe   <$ kw "GEQ"
  , BGt   <$ kw "GT"
  ]
