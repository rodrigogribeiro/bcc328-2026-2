module Parsing.Earley.Tests (tests) where

import qualified Data.Map as Map

import Test.Tasty
import Test.Tasty.HUnit

import Parsing.Grammar
import Parsing.Earley.EarleyParser

-- ---------------------------------------------------------------------------
-- Example grammars
-- ---------------------------------------------------------------------------

-- Grammar 1: LL(1) arithmetic (no left recursion, fatorada à esquerda)
--
--   E  -> T E'
--   E' -> + T E'  |  λ
--   T  -> F T'
--   T' -> * F T'  |  λ
--   F  -> ( E )   |  n
--
-- Start symbol: "E"  (alphabetically first key)
ll1Grammar :: Grammar
ll1Grammar = Map.fromList
  [ ("E",  [ [NonTerminal "T", NonTerminal "E'"] ])
  , ("E'", [ [Terminal "+", NonTerminal "T", NonTerminal "E'"]
           , [Terminal "λ"] ])
  , ("T",  [ [NonTerminal "F", NonTerminal "T'"] ])
  , ("T'", [ [Terminal "*", NonTerminal "F", NonTerminal "T'"]
           , [Terminal "λ"] ])
  , ("F",  [ [Terminal "(", NonTerminal "E", Terminal ")"]
           , [Terminal "n"] ])
  ]

-- Grammar 2: Left-recursive arithmetic
--   (Earley handles left recursion; LL cannot)
--
--   E -> E + T  |  T
--   F -> n  |  ( E )
--   T -> T * F  |  F
--
-- Start symbol: "E"
leftRecGrammar :: Grammar
leftRecGrammar = Map.fromList
  [ ("E", [ [NonTerminal "E", Terminal "+", NonTerminal "T"]
          , [NonTerminal "T"] ])
  , ("F", [ [Terminal "n"]
          , [Terminal "(", NonTerminal "E", Terminal ")"] ])
  , ("T", [ [NonTerminal "T", Terminal "*", NonTerminal "F"]
          , [NonTerminal "F"] ])
  ]

-- Grammar 3: Ambiguous grammar
--   E -> E + E  |  n
--
-- Earley accepts the input but may produce multiple completed items in S(n).
-- Start symbol: "E"
ambiguousGrammar :: Grammar
ambiguousGrammar = Map.fromList
  [ ("E", [ [NonTerminal "E", Terminal "+", NonTerminal "E"]
          , [Terminal "n"] ])
  ]

-- Grammar 4: Epsilon productions
--   A -> B C     (start)
--   B -> b  |  λ
--   C -> c  |  λ
--
-- Language: { ε, "b", "c", "b c" }
-- Start symbol: "A"
epsilonGrammar :: Grammar
epsilonGrammar = Map.fromList
  [ ("A", [ [NonTerminal "B", NonTerminal "C"] ])
  , ("B", [ [Terminal "b"], [Terminal "λ"] ])
  , ("C", [ [Terminal "c"], [Terminal "λ"] ])
  ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

assertAccept :: String -> Grammar -> [String] -> Assertion
assertAccept label g toks =
    earleyParse g toks @?= EarleyAccept
  where _ = label   -- suppress unused warning

assertReject :: String -> Grammar -> [String] -> Assertion
assertReject label g toks =
    earleyParse g toks @?= EarleyReject
  where _ = label

-- | Check that the Earley chart for the given input has exactly (n+1) sets.
assertChartLength :: Grammar -> [String] -> Assertion
assertChartLength g toks =
    length (buildChart g toks) @?= length toks + 1

-- ---------------------------------------------------------------------------
-- Test groups
-- ---------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Parsing.Earley"
    [ testGroup "LL(1) grammar - acceptance"
        [ testCase "single literal"           $ assertAccept "n"           ll1Grammar ["n"]
        , testCase "addition"                 $ assertAccept "n+n"         ll1Grammar ["n", "+", "n"]
        , testCase "multiplication"           $ assertAccept "n*n"         ll1Grammar ["n", "*", "n"]
        , testCase "left-assoc addition"      $ assertAccept "n+n+n"       ll1Grammar ["n", "+", "n", "+", "n"]
        , testCase "mixed operators"          $ assertAccept "n+n*n"       ll1Grammar ["n", "+", "n", "*", "n"]
        , testCase "parenthesised expr"       $ assertAccept "(n+n)*n"     ll1Grammar ["(", "n", "+", "n", ")", "*", "n"]
        , testCase "nested parentheses"       $ assertAccept "((n))"       ll1Grammar ["(", "(", "n", ")", ")"]
        ]

    , testGroup "LL(1) grammar - rejection"
        [ testCase "empty input"              $ assertReject "empty"       ll1Grammar []
        , testCase "operator only"            $ assertReject "+"           ll1Grammar ["+"]
        , testCase "trailing operator"        $ assertReject "n+"          ll1Grammar ["n", "+"]
        , testCase "leading operator"         $ assertReject "+n"          ll1Grammar ["+", "n"]
        , testCase "double operator"          $ assertReject "n++n"        ll1Grammar ["n", "+", "+", "n"]
        , testCase "unmatched open paren"     $ assertReject "(n"          ll1Grammar ["(", "n"]
        , testCase "unmatched close paren"    $ assertReject "n)"          ll1Grammar ["n", ")"]
        ]

    , testGroup "Left-recursive grammar - acceptance"
        [ testCase "single literal"           $ assertAccept "n"           leftRecGrammar ["n"]
        , testCase "addition"                 $ assertAccept "n+n"         leftRecGrammar ["n", "+", "n"]
        , testCase "multiplication"           $ assertAccept "n*n"         leftRecGrammar ["n", "*", "n"]
        , testCase "left-assoc: n+n+n"        $ assertAccept "n+n+n"       leftRecGrammar ["n", "+", "n", "+", "n"]
        , testCase "mixed operators"          $ assertAccept "n+n*n"       leftRecGrammar ["n", "+", "n", "*", "n"]
        , testCase "parenthesised expr"       $ assertAccept "(n+n)"       leftRecGrammar ["(", "n", "+", "n", ")"]
        ]

    , testGroup "Left-recursive grammar - rejection"
        [ testCase "empty input"              $ assertReject "empty"       leftRecGrammar []
        , testCase "leading operator"         $ assertReject "+n"          leftRecGrammar ["+", "n"]
        , testCase "trailing operator"        $ assertReject "n+"          leftRecGrammar ["n", "+"]
        , testCase "unmatched open paren"     $ assertReject "(n"          leftRecGrammar ["(", "n"]
        ]

    , testGroup "Ambiguous grammar - acceptance"
        [ testCase "single literal"           $ assertAccept "n"           ambiguousGrammar ["n"]
        , testCase "two operands"             $ assertAccept "n+n"         ambiguousGrammar ["n", "+", "n"]
        , testCase "three operands (ambig)"   $ assertAccept "n+n+n"       ambiguousGrammar ["n", "+", "n", "+", "n"]
        ]

    , testGroup "Ambiguous grammar - rejection"
        [ testCase "empty input"              $ assertReject "empty"       ambiguousGrammar []
        , testCase "operator only"            $ assertReject "+"           ambiguousGrammar ["+"]
        , testCase "trailing operator"        $ assertReject "n+"          ambiguousGrammar ["n", "+"]
        ]

    , testGroup "Epsilon productions - acceptance"
        [ testCase "both A and B"             $ assertAccept "b c"         epsilonGrammar ["b", "c"]
        , testCase "only B present"           $ assertAccept "b"           epsilonGrammar ["b"]
        , testCase "only C present"           $ assertAccept "c"           epsilonGrammar ["c"]
        , testCase "both epsilon"             $ assertAccept "empty"       epsilonGrammar []
        ]

    , testGroup "Epsilon productions - rejection"
        [ testCase "wrong token"              $ assertReject "a"           epsilonGrammar ["a"]
        , testCase "wrong order: c b"         $ assertReject "c b"         epsilonGrammar ["c", "b"]
        , testCase "repeated token"           $ assertReject "b b"         epsilonGrammar ["b", "b"]
        ]

    , testGroup "Chart invariants"
        [ testCase "chart length = n+1 (n=0)" $
            assertChartLength ll1Grammar []
        , testCase "chart length = n+1 (n=1)" $
            assertChartLength ll1Grammar ["n"]
        , testCase "chart length = n+1 (n=3)" $
            assertChartLength ll1Grammar ["n", "+", "n"]
        , testCase "chart length = n+1 for left-rec (n=3)" $
            assertChartLength leftRecGrammar ["n", "+", "n"]
        , testCase "S(0) is non-empty for ll1Grammar" $
            assertBool "S(0) should be non-empty"
                       (not (null (buildChart ll1Grammar ["n"] !! 0)))
        , testCase "S(0) is non-empty for leftRecGrammar" $
            assertBool "S(0) should be non-empty"
                       (not (null (buildChart leftRecGrammar ["n"] !! 0)))
        ]
    ]
