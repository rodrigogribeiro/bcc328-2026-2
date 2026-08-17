module Parsing.CYK.Tests (tests) where

import qualified Data.Map as Map
import qualified Data.Set as Set

import Test.Tasty
import Test.Tasty.HUnit

import Parsing.Grammar
import Parsing.CYK.CYKParser

anbn :: Grammar
anbn = Map.fromList
  [ ("S",   [ [NonTerminal "Na", NonTerminal "A1"]
             , [NonTerminal "Na", NonTerminal "Nb"] ])
  , ("A1",  [ [NonTerminal "S",  NonTerminal "Nb"] ])
  , ("Na",  [ [Terminal "a"] ])
  , ("Nb",  [ [Terminal "b"] ])
  ]

arith :: Grammar
arith = Map.fromList
  [ ("S",  [ [NonTerminal "S", NonTerminal "T1"]
           , [NonTerminal "S", NonTerminal "T2"]
           , [NonTerminal "T3", NonTerminal "T4"]
           , [Terminal "n"] ])
  , ("T1", [ [NonTerminal "Plus", NonTerminal "S"] ])
  , ("T2", [ [NonTerminal "Times", NonTerminal "S"] ])
  , ("T3", [ [Terminal "("] ])
  , ("T4", [ [NonTerminal "S", NonTerminal "RBr"] ])
  , ("Plus",  [ [Terminal "+"] ])
  , ("Times", [ [Terminal "*"] ])
  , ("RBr",   [ [Terminal ")"] ])
  ]

palindromes :: Grammar
palindromes = Map.fromList
  [ ("S", [ [NonTerminal "A", NonTerminal "Sa"]
          , [NonTerminal "B", NonTerminal "Sb"]
          , [NonTerminal "A", NonTerminal "A"]
          , [NonTerminal "B", NonTerminal "B"]
          , [Terminal "a"]
          , [Terminal "b"]
          ])
  , ("Sa", [ [NonTerminal "S", NonTerminal "A"] ])
  , ("Sb", [ [NonTerminal "S", NonTerminal "B"] ])
  , ("A",  [ [Terminal "a"] ])
  , ("B",  [ [Terminal "b"] ])
  ]

assertAccept :: String -> Grammar -> String -> [String] -> Assertion
assertAccept label g start toks =
    cykParse g start toks @?= CYKAccept
  where _ = label

assertReject :: String -> Grammar -> String -> [String] -> Assertion
assertReject label g start toks =
    cykParse g start toks @?= CYKReject
  where _ = label

tests :: TestTree
tests = testGroup "Parsing.CYK"
    [ testGroup "isCNF"
        [ testCase "anbn is CNF"       $ assertBool "anbn"    (isCNF anbn)
        , testCase "arith is CNF"      $ assertBool "arith"   (isCNF arith)
        , testCase "non-CNF detected"  $
            assertBool "not cnf" (not (isCNF
                (Map.fromList [("S", [[Terminal "a", Terminal "b", Terminal "c"]])])))
        ]

    , testGroup "a^n b^n - acceptance"
        [ testCase "ab"       $ assertAccept "ab"       anbn "S" ["a", "b"]
        , testCase "aabb"     $ assertAccept "aabb"     anbn "S" ["a", "a", "b", "b"]
        , testCase "aaabbb"   $ assertAccept "aaabbb"   anbn "S" ["a", "a", "a", "b", "b", "b"]
        , testCase "aaaabbbb" $ assertAccept "aaaabbbb" anbn "S" ["a","a","a","a","b","b","b","b"]
        ]

    , testGroup "a^n b^n - rejection"
        [ testCase "empty"  $ assertReject "empty" anbn "S" []
        , testCase "a"      $ assertReject "a"     anbn "S" ["a"]
        , testCase "b"      $ assertReject "b"     anbn "S" ["b"]
        , testCase "ba"     $ assertReject "ba"    anbn "S" ["b", "a"]
        , testCase "aab"    $ assertReject "aab"   anbn "S" ["a", "a", "b"]
        , testCase "abb"    $ assertReject "abb"   anbn "S" ["a", "b", "b"]
        , testCase "abba"   $ assertReject "abba"  anbn "S" ["a", "b", "b", "a"]
        ]

    , testGroup "arithmetic (CNF) - acceptance"
        [ testCase "n"         $ assertAccept "n"     arith "S" ["n"]
        , testCase "n+n"       $ assertAccept "n+n"   arith "S" ["n", "+", "n"]
        , testCase "n*n"       $ assertAccept "n*n"   arith "S" ["n", "*", "n"]
        , testCase "(n)"       $ assertAccept "(n)"   arith "S" ["(", "n", ")"]
        , testCase "n+n+n"     $ assertAccept "n+n+n" arith "S" ["n", "+", "n", "+", "n"]
        ]

    , testGroup "arithmetic (CNF) - rejection"
        [ testCase "empty"     $ assertReject "empty" arith "S" []
        , testCase "+"         $ assertReject "+"     arith "S" ["+"]
        , testCase "n+"        $ assertReject "n+"    arith "S" ["n", "+"]
        , testCase "+n"        $ assertReject "+n"    arith "S" ["+", "n"]
        ]

    , testGroup "palindromes - acceptance"
        [ testCase "a"      $ assertAccept "a"    palindromes "S" ["a"]
        , testCase "b"      $ assertAccept "b"    palindromes "S" ["b"]
        , testCase "aba"    $ assertAccept "aba"  palindromes "S" ["a", "b", "a"]
        , testCase "bab"    $ assertAccept "bab"  palindromes "S" ["b", "a", "b"]
        , testCase "abba"   $ assertAccept "abba" palindromes "S" ["a", "b", "b", "a"]
        , testCase "aa"     $ assertAccept "aa"   palindromes "S" ["a", "a"]
        ]

    , testGroup "palindromes - rejection"
        [ testCase "empty"  $ assertReject "empty" palindromes "S" []
        , testCase "ab"     $ assertReject "ab"    palindromes "S" ["a", "b"]
        , testCase "abc"    $ assertReject "abc"   palindromes "S" ["a", "b", "c"]
        , testCase "abab"   $ assertReject "abab"  palindromes "S" ["a", "b", "a", "b"]
        ]

    , testGroup "table invariants"
        [ testCase "table has at most n*(n+1)/2 cells for n=4" $
            let tbl = buildTable anbn ["a", "a", "b", "b"]
            in assertBool "cell count" (Map.size tbl <= 10)
        , testCase "(1,1) contains Na for input [a,b]" $
            let tbl = buildTable anbn ["a", "b"]
            in assertBool "(1,1) has Na"
                (maybe False (Set.member "Na") (Map.lookup (1,1) tbl))
        , testCase "(1,2) contains S for input [a,b]" $
            let tbl = buildTable anbn ["a", "b"]
            in assertBool "(1,2) has S"
                (maybe False (Set.member "S") (Map.lookup (1,2) tbl))
        ]
    ]
