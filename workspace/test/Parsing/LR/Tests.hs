module Parsing.LR.Tests (tests) where

import qualified Data.Map as Map

import Test.Tasty
import Test.Tasty.HUnit

import Parsing.Grammar
import Parsing.LR.LRParser
import Parsing.LR.LR0.BuildTable
import Parsing.LR.SLR.BuildTable  (constructSLRTable, parseSLR, checkConflicts)
import qualified Parsing.LR.LR1.BuildTable  as LR1
import qualified Parsing.LR.LALR.BuildTable as LALR


-- ---------------------------------------------------------------------------
-- Example grammars
-- ---------------------------------------------------------------------------

-- Grammar 1: S → a
-- Language: { "a" }
-- States (by BFS order in buildLR0States):
--   0: { S' → .S, S → .a }
--   1: { S → a. }             (goto 0 on "a")
--   2: { S' → S. }            (goto 0 on S)
simpleGrammar :: Grammar
simpleGrammar = Map.fromList
  [ ("S", [ [Terminal "a"] ]) ]

-- Grammar 2: S → (S) | a
-- Language: balanced parentheses with 'a' at the leaves
-- States:
--   0: { S' → .S, S → .(S), S → .a }
--   1: { S → (.S), S → .(S), S → .a }    (goto 0 on "(")
--   2: { S → a. }                          (goto 0/1 on "a")
--   3: { S' → S. }                         (goto 0 on S)
--   4: { S → (S.) }                        (goto 1 on S)
--   5: { S → (S). }                        (goto 4 on ")")
parenGrammar :: Grammar
parenGrammar = Map.fromList
  [ ("S", [ [Terminal "(", NonTerminal "S", Terminal ")"]
          , [Terminal "a"] ]) ]

-- Grammar 3: S → Sa | a    (left-recursive, language = a+)
-- States:
--   0: { S' → .S, S → .Sa, S → .a }
--   1: { S → a. }                           (goto 0 on "a")
--   2: { S' → S., S → S.a }                (goto 0 on S)
--   3: { S → Sa. }                          (goto 2 on "a")
leftRecGrammar :: Grammar
leftRecGrammar = Map.fromList
  [ ("S", [ [NonTerminal "S", Terminal "a"]
          , [Terminal "a"] ]) ]

-- Grammar 5: Right-recursive expressions (LR(1) and SLR, but NOT LR(0))
--   E → T + E | T
--   T → n | ( E )
--
-- In LR(0), the state {E → T. , E → T.+E} has a shift-reduce conflict on '+'.
-- Both SLR and LR(1) resolve it: '+' ∉ FOLLOW(E) = {$, )}, and in LR(1)
-- the item [E → T., $] and [E → T., )] have lookaheads that exclude '+'.
-- Start symbol: "E" (alphabetically first among E, T).
rightRecGrammar :: Grammar
rightRecGrammar = Map.fromList
  [ ("E", [ [NonTerminal "T", Terminal "+", NonTerminal "E"]
          , [NonTerminal "T"] ])
  , ("T", [ [Terminal "n"]
          , [Terminal "(", NonTerminal "E", Terminal ")"] ])
  ]

-- Grammar 4: Arithmetic expressions (SLR(1) but NOT LR(0))
--   E → E + T | T
--   F → ( E ) | n
--   T → T * F | F
--
-- LR(0) has a shift-reduce conflict in the state {E → T., T → T.*F}:
-- on '*', both Shift (from T → T.*F) and Reduce E→T (for all tokens) apply.
-- SLR resolves it: FOLLOW(E) = {+, ), $}, and '*' ∉ FOLLOW(E).
arithGrammar :: Grammar
arithGrammar = Map.fromList
  [ ("E", [ [NonTerminal "E", Terminal "+", NonTerminal "T"]
          , [NonTerminal "T"] ])
  , ("F", [ [Terminal "(", NonTerminal "E", Terminal ")"]
          , [Terminal "n"] ])
  , ("T", [ [NonTerminal "T", Terminal "*", NonTerminal "F"]
          , [NonTerminal "F"] ])
  ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkTable :: Grammar -> ParsingTable
mkTable = constructLR0Table

assertSuccess :: Grammar -> ParsingTable -> [String] -> Assertion
assertSuccess g tbl toks = parseLR g tbl toks @?= ParseSuccess

assertError :: Grammar -> ParsingTable -> [String] -> Assertion
assertError g tbl toks =
    case parseLR g tbl toks of
        ParseError _ -> return ()
        ParseSuccess -> assertFailure $
            "Expected parse error for input " ++ show toks
            ++ " but got ParseSuccess"

assertAction :: ParsingTable -> (Int, String) -> Action -> Assertion
assertAction tbl key expected =
    Map.lookup key (actionTable tbl) @?= Just expected

assertGoto :: ParsingTable -> (Int, String) -> Int -> Assertion
assertGoto tbl key expected =
    Map.lookup key (gotoTable tbl) @?= Just expected

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Parsing.LR"
    [ testGroup "LR(0) - simpleGrammar (S -> a)"
        [ testGroup "States"
            [ testCase "builds 3 states" $
                length (buildLR0States simpleGrammar) @?= 3
            ]

        , testGroup "Action table"
            [ testCase "state 0: Shift 1 on 'a'" $
                assertAction (mkTable simpleGrammar) (0, "a") (Shift 1)

            , testCase "state 1: Reduce S -> a on '$'" $
                assertAction (mkTable simpleGrammar) (1, "$")
                    (Reduce "S" [Terminal "a"])

            , testCase "state 1: Reduce S -> a on 'a'" $
                assertAction (mkTable simpleGrammar) (1, "a")
                    (Reduce "S" [Terminal "a"])

            , testCase "state 2: Accept on '$'" $
                assertAction (mkTable simpleGrammar) (2, "$") Accept
            ]

        , testGroup "Goto table"
            [ testCase "state 0 on S -> state 2" $
                assertGoto (mkTable simpleGrammar) (0, "S") 2
            ]

        , testGroup "Parser - acceptance"
            [ testCase "accepts [a]" $
                assertSuccess simpleGrammar (mkTable simpleGrammar) ["a"]
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                assertError simpleGrammar (mkTable simpleGrammar) []
            , testCase "rejects [b]" $
                assertError simpleGrammar (mkTable simpleGrammar) ["b"]
            , testCase "rejects [a, a]" $
                assertError simpleGrammar (mkTable simpleGrammar) ["a", "a"]
            ]
        ]

    , testGroup "LR(0) - parenGrammar (S -> (S) | a)"
        [ testGroup "States"
            [ testCase "builds 6 states" $
                length (buildLR0States parenGrammar) @?= 6
            ]

        , testGroup "Action table"
            [ testCase "state 0: Shift on '('" $
                assertAction (mkTable parenGrammar) (0, "(") (Shift 1)

            , testCase "state 0: Shift on 'a'" $
                assertAction (mkTable parenGrammar) (0, "a") (Shift 2)

            , testCase "state 1: Shift on '(' (loop)" $
                assertAction (mkTable parenGrammar) (1, "(") (Shift 1)

            , testCase "state 1: Shift on 'a'" $
                assertAction (mkTable parenGrammar) (1, "a") (Shift 2)

            , testCase "state 2: Reduce S -> a on '$'" $
                assertAction (mkTable parenGrammar) (2, "$")
                    (Reduce "S" [Terminal "a"])

            , testCase "state 2: Reduce S -> a on ')'" $
                assertAction (mkTable parenGrammar) (2, ")")
                    (Reduce "S" [Terminal "a"])

            , testCase "state 3: Accept on '$'" $
                assertAction (mkTable parenGrammar) (3, "$") Accept

            , testCase "state 4: Shift on ')'" $
                assertAction (mkTable parenGrammar) (4, ")") (Shift 5)

            , testCase "state 5: Reduce S -> (S) on '$'" $
                assertAction (mkTable parenGrammar) (5, "$")
                    (Reduce "S" [Terminal "(", NonTerminal "S", Terminal ")"])

            , testCase "state 5: Reduce S -> (S) on ')'" $
                assertAction (mkTable parenGrammar) (5, ")")
                    (Reduce "S" [Terminal "(", NonTerminal "S", Terminal ")"])
            ]

        , testGroup "Goto table"
            [ testCase "state 0 on S -> state 3" $
                assertGoto (mkTable parenGrammar) (0, "S") 3

            , testCase "state 1 on S -> state 4" $
                assertGoto (mkTable parenGrammar) (1, "S") 4
            ]

        , testGroup "Parser - acceptance"
            [ testCase "accepts [a]" $
                assertSuccess parenGrammar (mkTable parenGrammar) ["a"]
            , testCase "accepts [(, a, )]" $
                assertSuccess parenGrammar (mkTable parenGrammar) ["(", "a", ")"]
            , testCase "accepts [(, (, a, ), )]" $
                assertSuccess parenGrammar (mkTable parenGrammar) ["(", "(", "a", ")", ")"]
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                assertError parenGrammar (mkTable parenGrammar) []
            , testCase "rejects [)]" $
                assertError parenGrammar (mkTable parenGrammar) [")"]
            , testCase "rejects [(]" $
                assertError parenGrammar (mkTable parenGrammar) ["("]
            , testCase "rejects [(, )]  (no leaf)" $
                assertError parenGrammar (mkTable parenGrammar) ["(", ")"]
            , testCase "rejects [a, a]" $
                assertError parenGrammar (mkTable parenGrammar) ["a", "a"]
            , testCase "rejects [(, a]  (missing ')')" $
                assertError parenGrammar (mkTable parenGrammar) ["(", "a"]
            ]
        ]

    , testGroup "LR(0) - leftRecGrammar (S -> Sa | a)"
        [ testGroup "States"
            [ testCase "builds 4 states" $
                length (buildLR0States leftRecGrammar) @?= 4
            ]

        , testGroup "Action table"
            [ testCase "state 0: Shift on 'a'" $
                assertAction (mkTable leftRecGrammar) (0, "a") (Shift 1)

            , testCase "state 1: Reduce S -> a on '$'" $
                assertAction (mkTable leftRecGrammar) (1, "$")
                    (Reduce "S" [Terminal "a"])

            , testCase "state 1: Reduce S -> a on 'a'" $
                assertAction (mkTable leftRecGrammar) (1, "a")
                    (Reduce "S" [Terminal "a"])

            , testCase "state 2: Shift on 'a'" $
                assertAction (mkTable leftRecGrammar) (2, "a") (Shift 3)

            , testCase "state 2: Accept on '$'" $
                assertAction (mkTable leftRecGrammar) (2, "$") Accept

            , testCase "state 3: Reduce S -> Sa on '$'" $
                assertAction (mkTable leftRecGrammar) (3, "$")
                    (Reduce "S" [NonTerminal "S", Terminal "a"])

            , testCase "state 3: Reduce S -> Sa on 'a'" $
                assertAction (mkTable leftRecGrammar) (3, "a")
                    (Reduce "S" [NonTerminal "S", Terminal "a"])
            ]

        , testGroup "Goto table"
            [ testCase "state 0 on S -> state 2" $
                assertGoto (mkTable leftRecGrammar) (0, "S") 2
            ]

        , testGroup "Parser - acceptance"
            [ testCase "accepts [a]" $
                assertSuccess leftRecGrammar (mkTable leftRecGrammar) ["a"]
            , testCase "accepts [a, a]" $
                assertSuccess leftRecGrammar (mkTable leftRecGrammar) ["a", "a"]
            , testCase "accepts [a, a, a]" $
                assertSuccess leftRecGrammar (mkTable leftRecGrammar) ["a", "a", "a"]
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                assertError leftRecGrammar (mkTable leftRecGrammar) []
            , testCase "rejects [b]" $
                assertError leftRecGrammar (mkTable leftRecGrammar) ["b"]
            , testCase "rejects [a, b]" $
                assertError leftRecGrammar (mkTable leftRecGrammar) ["a", "b"]
            ]
        ]

    -- -----------------------------------------------------------------------
    -- SLR tests
    -- -----------------------------------------------------------------------

    , testGroup "SLR - simpleGrammar (S -> a)"
        [ testGroup "Parser - acceptance"
            [ testCase "accepts [a]" $
                parseSLR simpleGrammar (constructSLRTable simpleGrammar) ["a"]
                    @?= ParseSuccess
            ]
        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case parseSLR simpleGrammar (constructSLRTable simpleGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [a, a]" $
                case parseSLR simpleGrammar (constructSLRTable simpleGrammar) ["a", "a"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]
        , testCase "no conflicts" $
            checkConflicts (constructSLRTable simpleGrammar) @?= []
        ]

    , testGroup "SLR - parenGrammar (S -> (S) | a)"
        [ testGroup "Parser - acceptance"
            [ testCase "accepts [a]" $
                parseSLR parenGrammar (constructSLRTable parenGrammar) ["a"]
                    @?= ParseSuccess
            , testCase "accepts [(, a, )]" $
                parseSLR parenGrammar (constructSLRTable parenGrammar) ["(", "a", ")"]
                    @?= ParseSuccess
            , testCase "accepts [(, (, a, ), )]" $
                parseSLR parenGrammar (constructSLRTable parenGrammar)
                    ["(", "(", "a", ")", ")"]
                    @?= ParseSuccess
            ]
        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case parseSLR parenGrammar (constructSLRTable parenGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [(, a]" $
                case parseSLR parenGrammar (constructSLRTable parenGrammar) ["(", "a"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]
        , testCase "no conflicts" $
            checkConflicts (constructSLRTable parenGrammar) @?= []
        ]

    , testGroup "SLR - arithGrammar (E -> E+T | T, T -> T*F | F, F -> (E) | n)"
        [ testCase "no SLR conflicts" $
            checkConflicts (constructSLRTable arithGrammar) @?= []

        , testGroup "Parser - acceptance"
            [ testCase "accepts [n]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar) ["n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar) ["n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, *, n]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar) ["n", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n, *, n]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar)
                    ["n", "+", "n", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, +, n, ), *, n]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar)
                    ["(", "n", "+", "n", ")", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n, +, n]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar)
                    ["n", "+", "n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, )]" $
                parseSLR arithGrammar (constructSLRTable arithGrammar)
                    ["(", "n", ")"]
                    @?= ParseSuccess
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case parseSLR arithGrammar (constructSLRTable arithGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [+]" $
                case parseSLR arithGrammar (constructSLRTable arithGrammar) ["+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, +]" $
                case parseSLR arithGrammar (constructSLRTable arithGrammar) ["n", "+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, n]" $
                case parseSLR arithGrammar (constructSLRTable arithGrammar) ["n", "n"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [(, n]  (missing ')')" $
                case parseSLR arithGrammar (constructSLRTable arithGrammar) ["(", "n"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]
        ]

    -- -----------------------------------------------------------------------
    -- LR(1) tests
    -- -----------------------------------------------------------------------

    , testGroup "LR(1) - arithGrammar (E -> E+T | T, T -> T*F | F, F -> (E) | n)"
        [ testCase "no conflicts" $
            LR1.checkConflicts (LR1.constructLR1Table arithGrammar) @?= []

        , testGroup "Parser - acceptance"
            [ testCase "accepts [n]" $
                LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) ["n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n]" $
                LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) ["n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, *, n]" $
                LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) ["n", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n, *, n]" $
                LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar)
                    ["n", "+", "n", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, +, n, ), *, n]" $
                LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar)
                    ["(", "n", "+", "n", ")", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, )]" $
                LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar)
                    ["(", "n", ")"]
                    @?= ParseSuccess
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [+]" $
                case LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) ["+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, +]" $
                case LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) ["n", "+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, n]" $
                case LR1.parseLR1 arithGrammar (LR1.constructLR1Table arithGrammar) ["n", "n"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]

        , testGroup "States"
            [ testCase "LR(1) builds more states than LALR for arithGrammar" $
                assertBool "LR(1) state count should be >= LALR state count" $
                    length (LR1.buildLR1States arithGrammar)
                        >= length (LALR.buildLALRStates arithGrammar)
            ]
        ]

    , testGroup "LR(1) - rightRecGrammar (E -> T+E | T, T -> n | (E))"
        [ testCase "no conflicts" $
            LR1.checkConflicts (LR1.constructLR1Table rightRecGrammar) @?= []

        , testGroup "Parser - acceptance"
            [ testCase "accepts [n]" $
                LR1.parseLR1 rightRecGrammar (LR1.constructLR1Table rightRecGrammar) ["n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n]" $
                LR1.parseLR1 rightRecGrammar (LR1.constructLR1Table rightRecGrammar)
                    ["n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n, +, n]  (right-assoc)" $
                LR1.parseLR1 rightRecGrammar (LR1.constructLR1Table rightRecGrammar)
                    ["n", "+", "n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, )]" $
                LR1.parseLR1 rightRecGrammar (LR1.constructLR1Table rightRecGrammar)
                    ["(", "n", ")"]
                    @?= ParseSuccess
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case LR1.parseLR1 rightRecGrammar (LR1.constructLR1Table rightRecGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, +]" $
                case LR1.parseLR1 rightRecGrammar (LR1.constructLR1Table rightRecGrammar)
                        ["n", "+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]
        ]

    -- -----------------------------------------------------------------------
    -- LALR tests
    -- -----------------------------------------------------------------------

    , testGroup "LALR - arithGrammar (E -> E+T | T, T -> T*F | F, F -> (E) | n)"
        [ testCase "no conflicts" $
            LALR.checkConflicts (LALR.constructLALRTable arithGrammar) @?= []

        , testGroup "Parser - acceptance"
            [ testCase "accepts [n]" $
                LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar) ["n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n]" $
                LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar) ["n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, *, n]" $
                LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar) ["n", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n, *, n]" $
                LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar)
                    ["n", "+", "n", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, +, n, ), *, n]" $
                LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar)
                    ["(", "n", "+", "n", ")", "*", "n"]
                    @?= ParseSuccess
            , testCase "accepts [(, n, )]" $
                LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar)
                    ["(", "n", ")"]
                    @?= ParseSuccess
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [+]" $
                case LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar) ["+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, +]" $
                case LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar)
                        ["n", "+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, n]" $
                case LALR.parseLALR arithGrammar (LALR.constructLALRTable arithGrammar)
                        ["n", "n"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]

        , testGroup "States"
            [ testCase "LALR has fewer states than LR(1) for arithGrammar" $
                assertBool "LALR state count should be < LR(1) state count" $
                    length (LALR.buildLALRStates arithGrammar)
                        < length (LR1.buildLR1States arithGrammar)

            , testCase "LALR has same number of states as SLR for arithGrammar" $
                length (LALR.buildLALRStates arithGrammar)
                    @?= length (buildLR0States arithGrammar)
            ]
        ]

    , testGroup "LALR - rightRecGrammar (E -> T+E | T, T -> n | (E))"
        [ testCase "no conflicts" $
            LALR.checkConflicts (LALR.constructLALRTable rightRecGrammar) @?= []

        , testGroup "Parser - acceptance"
            [ testCase "accepts [n]" $
                LALR.parseLALR rightRecGrammar (LALR.constructLALRTable rightRecGrammar) ["n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n]" $
                LALR.parseLALR rightRecGrammar (LALR.constructLALRTable rightRecGrammar)
                    ["n", "+", "n"]
                    @?= ParseSuccess
            , testCase "accepts [n, +, n, +, n]" $
                LALR.parseLALR rightRecGrammar (LALR.constructLALRTable rightRecGrammar)
                    ["n", "+", "n", "+", "n"]
                    @?= ParseSuccess
            ]

        , testGroup "Parser - rejection"
            [ testCase "rejects []" $
                case LALR.parseLALR rightRecGrammar (LALR.constructLALRTable rightRecGrammar) [] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            , testCase "rejects [n, +]" $
                case LALR.parseLALR rightRecGrammar (LALR.constructLALRTable rightRecGrammar)
                        ["n", "+"] of
                    ParseError _ -> return ()
                    ParseSuccess -> assertFailure "expected error"
            ]
        ]
    ]
