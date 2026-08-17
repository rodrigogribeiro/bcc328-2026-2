module TExp.Frontend.Parser.TExpParser (termParser) where

import Text.Megaparsec

import TExp.Frontend.Syntax.TExpSyntax
import TExp.Frontend.Lexer.TExpLexer

-- Top-level entry point.
-- Parses a complete term from a string, consuming all input.

termParser :: String -> Either String Term
termParser s = case parse (sc *> termP <* eof) "" s of
    Left err -> Left (errorBundlePretty err)
    Right t  -> Right t

-- Parser for terms.
--
-- The grammar is:
--
--   t ::= true
--       | false
--       | if t then t else t
--       | 0
--       | succ t
--       | pred t
--       | iszero t
--       | ( t )
--
-- All constructs are prefix or atomic, so no precedence table is needed.

termP :: Parser Term
termP
    =   trueP
    <|> falseP
    <|> ifP
    <|> zeroP
    <|> succP
    <|> predP
    <|> iszeroP
    <|> parens termP

-- Atomic terms

trueP :: Parser Term
trueP = TTrue <$ rword "true"

falseP :: Parser Term
falseP = TFalse <$ rword "false"

zeroP :: Parser Term
zeroP = TZero <$ symbol "0"

-- Prefix terms: each reads one keyword then recurses into termP

-- succ t
succP :: Parser Term
succP = TSucc <$> (rword "succ" *> termP)

-- pred t
predP :: Parser Term
predP = TPred <$> (rword "pred" *> termP)

-- iszero t
iszeroP :: Parser Term
iszeroP = TIsZero <$> (rword "iszero" *> termP)

-- if t1 then t2 else t3
ifP :: Parser Term
ifP = do
    rword "if"
    t1 <- termP
    rword "then"
    t2 <- termP
    rword "else"
    t3 <- termP
    pure (TIf t1 t2 t3)
