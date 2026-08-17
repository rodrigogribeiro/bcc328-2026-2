module FJ.Frontend.Parser.FJParser
  ( parseProgram
  , parseExpr
  ) where

import Data.Void
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

import FJ.Frontend.Syntax.FJSyntax

type Parser = Parsec Void String

-- Lexer

sc :: Parser ()
sc = L.space space1 (L.skipLineComment "//") (L.skipBlockComment "/*" "*/")

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: String -> Parser String
symbol = L.symbol sc

parens :: Parser a -> Parser a
parens p = symbol "(" *> p <* symbol ")"

braces :: Parser a -> Parser a
braces p = symbol "{" *> p <* symbol "}"

semi :: Parser String
semi = symbol ";"

comma :: Parser String
comma = symbol ","

reservedWords :: [String]
reservedWords = ["class","extends","new","return","super","this"]

pClassName :: Parser ClassName
pClassName = (lexeme . try) p
  where p = (:) <$> upperChar <*> many alphaNumChar

pVarName :: Parser String
pVarName = (lexeme . try) (p >>= check)
  where
    p     = (:) <$> (lowerChar <|> char '_') <*> many (alphaNumChar <|> char '_')
    check s
      | s `elem` reservedWords = fail ("reserved word: " ++ s)
      | otherwise              = return s

pType :: Parser FJType
pType = FJType <$> pClassName

parseProgram :: String -> Either String Program
parseProgram s =
  case runParser (sc *> pProgram <* eof) "" s of
    Left  err -> Left (errorBundlePretty err)
    Right p   -> Right p

parseExpr :: String -> Either String Expr
parseExpr s =
  case runParser (sc *> pExpr <* eof) "" s of
    Left  err -> Left (errorBundlePretty err)
    Right e   -> Right e

pProgram :: Parser Program
pProgram = do
    cls  <- many (try pClassDecl)
    main <- pExpr
    return (Program cls main)

pClassDecl :: Parser ClassDecl
pClassDecl = do
    _     <- symbol "class"
    cname <- pClassName
    _     <- symbol "extends"
    sname <- pClassName
    braces $ do
      fs   <- many (try pFieldDecl)
      ctor <- pConstructor cname
      ms   <- many pMethodDecl
      return (ClassDecl cname sname fs ctor ms)

pFieldDecl :: Parser (FJType, FieldName)
pFieldDecl = do
    t <- pType
    f <- pVarName
    _ <- semi
    return (t, f)

pConstructor :: ClassName -> Parser Constructor
pConstructor cname = do
    _      <- lexeme (string cname)
    params <- parens (pParam `sepBy` comma)
    braces $ do
      sArgs <- pSuperCall
      inits <- many (try pThisInit)
      return (Constructor cname params sArgs inits)

pParam :: Parser (FJType, VarName)
pParam = (,) <$> pType <*> pVarName

pSuperCall :: Parser [VarName]
pSuperCall = do
    _ <- symbol "super"
    args <- parens (pVarName `sepBy` comma)
    _ <- semi
    return args

pThisInit :: Parser (FieldName, VarName)
pThisInit = do
    _ <- symbol "this"
    _ <- symbol "."
    f <- pVarName
    _ <- symbol "="
    x <- pVarName
    _ <- semi
    return (f, x)

pMethodDecl :: Parser MethodDecl
pMethodDecl = do
    ret    <- pType
    mname  <- pVarName
    params <- parens (pParam `sepBy` comma)
    braces $ do
      _ <- symbol "return"
      e <- pExpr
      _ <- semi
      return (MethodDecl ret mname params e)

pExpr :: Parser Expr
pExpr = do
    e <- pAtom
    pChain e
  where
    pChain e = do
        r <- optional (try (symbol "." *> pSuffix e))
        case r of
          Nothing -> return e
          Just e' -> pChain e'

    pSuffix obj = do
        name <- pVarName
        mArgs <- optional (parens (pExpr `sepBy` comma))
        case mArgs of
          Just args -> return (EInvk obj name args)
          Nothing   -> return (EField obj name)

pAtom :: Parser Expr
pAtom
    =   pNew
    <|> try pCast
    <|> pParens
    <|> pThis
    <|> (EVar <$> pVarName)

pNew :: Parser Expr
pNew = do
    _ <- symbol "new"
    c <- pClassName
    args <- parens (pExpr `sepBy` comma)
    return (ENew c args)

pCast :: Parser Expr
pCast = do
    c <- parens pClassName
    e <- pAtom
    return (ECast c e)

pParens :: Parser Expr
pParens = parens pExpr

pThis :: Parser Expr
pThis = EVar "this" <$ symbol "this"
