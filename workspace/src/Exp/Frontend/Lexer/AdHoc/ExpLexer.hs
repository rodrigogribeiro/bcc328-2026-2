module Exp.Frontend.Lexer.AdHoc.ExpLexer where

import Data.Char
import Exp.Frontend.Lexer.Token

-- basic type definitions for the lexer

type Line = Int
type Column = Int
type State = (Line, Column, String, [Token])

-- lexer main function

lexer :: String -> Either String [Token]
lexer = finish . foldl step base
  where
    base = Right (1, 1, "", [])

    finish = either Left (Right . extract)

    step ac@(Left _) _ = ac
    step (Right state) c = transition state c

    extract (l, col, s, ts)
      | null s = reverse ts
      | otherwise = let n = read (reverse s)
                        t = Token (l, col - (length s))
                                  (TNumber n)
                    in reverse (t : ts)

-- transition between lexer states

transition :: State -> Char -> Either String State
transition state@(l, col, t, ts) c
  | c == '\n' = mkDigits state c
  | isSpace c = mkDigits state c
  | c == '+' = Right (l, col + 1, "", mkToken state (Token (l,col) TPlus) ++ ts)
  | c == '*' = Right (l, col + 1, "", mkToken state (Token (l,col) TTimes) ++ ts)
  | c == '(' = Right (l, col + 1, "", mkToken state (Token (l,col) TLParen) ++ ts)
  | c == ')' = Right (l, col + 1, "", mkToken state (Token (l,col) TRParen) ++ ts)
  | isDigit c = Right (l, col + 1, c : t, ts)
  | otherwise = unexpectedCharError l col c

-- function for creating token

mkToken :: State -> Token -> [Token]
mkToken (l,c, s@(_ : _), _) t
  | all isDigit s = [t, Token (l,c) (TNumber (read $ reverse s))]
  | otherwise = [t]
mkToken _ t = [t]

-- creating a token for numbers

mkDigits :: State -> Char -> Either String State
mkDigits (l, col, s, ts) c
  | null s = let l' = if c == '\n' then l + 1 else l 
                 col' = if isSpace c then col + 1 else col 
             in Right (l', col', s, ts)
  | all isDigit s = let t = Token (l,col) (TNumber (read $ reverse s))
                        l' = if c == '\n' then l + 1 else l
                        col' = if c /= '\n' && isSpace c then col + 1 else col
                    in Right (l', col', "", t : ts)
  | otherwise = unexpectedCharError l col c

-- error message for the lexer

unexpectedCharError :: Line -> Column -> Char -> Either String State
unexpectedCharError l col c
  = Left (unwords [ "Unexpected character at line"
                              , show l
                              , "column"
                              , show col
                              , ":"
                              , [c]
                              ])

