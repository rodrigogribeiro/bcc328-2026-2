module Parsing.LL.Parser
  ( parse
  , ParseResult (..)
  , printDerivation
  ) where

import qualified Data.Map as Map

import Parsing.Grammar
import Parsing.LL.BuildTable

-- Result type

-- The result of LL(1) parsing.
-- On success, carries the productions applied in leftmost-derivation order.
data ParseResult
  = ParseOk [Production]
  | ParseError String
  deriving (Show)

-- Parser

-- Table-driven LL(1) parser.
--
-- Arguments:
--   * grammar   – the grammar (used only to find the start symbol)
--   * table     – the LL(1) parse table built by 'buildParseTable'
--   * tokens    – the input as a list of terminal strings (without "$")
--
-- Returns 'ParseOk ps' where 'ps' is the list of productions applied in
-- leftmost-derivation order, or 'ParseError msg'.
parse :: Grammar -> ParseTable -> [String] -> ParseResult
parse grammar table tokens =
    go initialStack (tokens ++ ["$"]) []
  where
    startSym     = head (nonTerminals grammar)
    initialStack = [NonTerminal startSym, Terminal "$"]
    go (Terminal "$" : _) ("$" : _) acc =
        ParseOk (reverse acc)
    go (Terminal t : stack') (a : inp') acc
        | t == a    = go stack' inp' acc
        | otherwise = ParseError $
            "Syntax error: expected '" ++ t ++ "', found '" ++ a ++ "'"
    go (NonTerminal nt : stack') inp@(a : _) acc =
        case Map.lookup (nt, a) table of
            Just (Derive prod) ->
                let pushed = filter (not . isLambda) prod
                in go (pushed ++ stack') inp (prod : acc)
            Just Accept ->
                ParseOk (reverse acc)
            _ ->
                ParseError $
                    "Syntax error: no rule for (" ++ nt ++ ", " ++ a ++ ")"

    go stack' inp' _ =
        ParseError $
            "Syntax error: unexpected state"
            ++ "\n  stack: " ++ show stack'
            ++ "\n  input: " ++ show inp'

printDerivation :: String -> [Production] -> IO ()
printDerivation start prods = do
    putStrLn $ "  " ++ start
    go [NonTerminal start] prods
  where
    go _           []           = return ()
    go sentential  (prod : ps)  = do
        let sentential' = applyProd sentential prod
        putStrLn $ "  => " ++ showSentential sentential'
        go sentential' ps

    applyProd :: [Symbol] -> Production -> [Symbol]
    applyProd sentential prod =
        let (prefix, rest) = break (not . isTerminal) sentential
            body           = filter (not . isLambda) prod
        in case rest of
            []         -> prefix
            (_ : rest') -> prefix ++ body ++ rest'

    showSentential [] = "λ"
    showSentential ss = unwords (map symbolString ss)
