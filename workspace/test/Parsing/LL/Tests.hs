module Parsing.LL.Tests (tests) where

import qualified Data.Map as Map

import Test.Tasty
import Test.Tasty.HUnit

import Parsing.Grammar
import Parsing.LL.BuildTable
import Parsing.LL.Parser

-- ---------------------------------------------------------------------------
-- Example grammar (LL(1) arithmetic expressions without left recursion)
--
--   E  -> T E'
--   E' -> + T E'  |  λ
--   T  -> F T'
--   T' -> * F T'  |  λ
--   F  -> ( E )   |  n
-- ---------------------------------------------------------------------------

grammar :: Grammar
grammar = Map.fromList
  [ ("E",  [ [NonTerminal "T", NonTerminal "E'"] ])
  , ("E'", [ [Terminal "+", NonTerminal "T", NonTerminal "E'"]
           , [Terminal "λ"] ])
  , ("T",  [ [NonTerminal "F", NonTerminal "T'"] ])
  , ("T'", [ [Terminal "*", NonTerminal "F", NonTerminal "T'"]
           , [Terminal "λ"] ])
  , ("F",  [ [Terminal "(", NonTerminal "E", Terminal ")"]
           , [Terminal "n"] ])
  ]

table :: ParseTable
table = buildParseTable grammar

-- | Helper: run the parser and check that it succeeded.
assertOk :: String -> [String] -> Assertion
assertOk msg tokens =
    case parse grammar table tokens of
        ParseOk _      -> return ()
        ParseError err -> assertFailure (msg ++ ": unexpected error: " ++ err)

-- | Helper: run the parser and check that it failed.
assertErr :: String -> [String] -> Assertion
assertErr msg tokens =
    case parse grammar table tokens of
        ParseOk _      -> assertFailure (msg ++ ": expected error but parsing succeeded")
        ParseError _   -> return ()

-- | Helper: check that the leftmost derivation has the expected length
--   (i.e., the expected number of production steps).
assertSteps :: String -> [String] -> Int -> Assertion
assertSteps msg tokens expected =
    case parse grammar table tokens of
        ParseError err -> assertFailure (msg ++ ": unexpected error: " ++ err)
        ParseOk prods  ->
            length prods @?= expected

-- ---------------------------------------------------------------------------
-- Test groups
-- ---------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Parsing.LL"
    [ testGroup "BuildTable"
        [ testCase "table has no error on (E, n)"  $
            Map.lookup ("E", "n")  table @?= Just (Derive [NonTerminal "T", NonTerminal "E'"])

        , testCase "table has no error on (E, ()"  $
            Map.lookup ("E", "(")  table @?= Just (Derive [NonTerminal "T", NonTerminal "E'"])

        , testCase "E' derives lambda on $"        $
            Map.lookup ("E'", "$") table @?= Just (Derive [Terminal "λ"])

        , testCase "E' derives lambda on )"        $
            Map.lookup ("E'", ")") table @?= Just (Derive [Terminal "λ"])

        , testCase "T' derives lambda on +"        $
            Map.lookup ("T'", "+") table @?= Just (Derive [Terminal "λ"])

        , testCase "F derives n on n"              $
            Map.lookup ("F", "n")  table @?= Just (Derive [Terminal "n"])

        , testCase "F derives parens on ("         $
            Map.lookup ("F", "(")  table @?= Just (Derive [ Terminal "("
                                                           , NonTerminal "E"
                                                           , Terminal ")" ])
        ]

    , testGroup "Parser - acceptance"
        [ testCase "single literal"             $ assertOk "n"             ["n"]
        , testCase "addition"                   $ assertOk "n + n"         ["n", "+", "n"]
        , testCase "multiplication"             $ assertOk "n * n"         ["n", "*", "n"]
        , testCase "addition and multiplication"$ assertOk "n + n * n"     ["n", "+", "n", "*", "n"]
        , testCase "parenthesised expression"   $ assertOk "(n + n) * n"   ["(", "n", "+", "n", ")", "*", "n"]
        , testCase "nested parentheses"         $ assertOk "((n))"         ["(", "(", "n", ")", ")"]
        , testCase "left-assoc addition"        $ assertOk "n + n + n"     ["n", "+", "n", "+", "n"]
        ]

    , testGroup "Parser - rejection"
        [ testCase "empty input"                $ assertErr "empty"        []
        , testCase "missing right operand"      $ assertErr "n +"          ["n", "+"]
        , testCase "leading operator"           $ assertErr "+ n"          ["+", "n"]
        , testCase "double operator"            $ assertErr "n + + n"      ["n", "+", "+", "n"]
        , testCase "unmatched open paren"       $ assertErr "(n"           ["(", "n"]
        , testCase "unmatched close paren"      $ assertErr "n)"           ["n", ")"]
        ]

    , testGroup "Parser - derivation steps"
        -- The number of steps equals the number of non-terminals expanded,
        -- which for this grammar equals the number of productions applied.
        [ testCase "n uses 5 steps"           $ assertSteps "n"     ["n"]             5
        , testCase "n + n uses 9 steps"       $ assertSteps "n + n" ["n", "+", "n"]  9
        ]
    ]
