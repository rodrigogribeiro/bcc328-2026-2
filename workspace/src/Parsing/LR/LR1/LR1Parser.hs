module Parsing.LR.LR1.LR1Parser
  ( ParserState (..)
  , parseStep
  , parseLR1
  ) where

import qualified Data.Map as Map

import Parsing.Grammar
import Parsing.LR.LR0.BuildTable  (Action (..))
import Parsing.LR.LR0.LR0Parser   (ParseResult (..))
import Parsing.LR.LR1.BuildTable  (LR1Table (..))


-- LR(1) Parsing Algorithm
-- The parsing algorithm is identical to LR(0): it maintains a stack of states
-- and consults the action/goto tables at each step. The only difference is that
-- the table was built with local lookaheads, so reduce actions are more precise.

data ParserState = ParserState
    { stateStack  :: [Int]
    , symbolStack :: [Symbol]
    , inputBuffer :: [String]
    } deriving (Eq, Ord, Show)

parseStep :: Grammar -> LR1Table -> ParserState -> Either String ParserState
parseStep g table (ParserState states syms input) =
    case input of
        [] -> Left "Unexpected end of input"
        (token : rest) ->
            let currentState = head states
                action       = Map.lookup (currentState, token) (lr1ActionTable table)
            in case action of
                Nothing ->
                    Left $ "No action for state " ++ show currentState
                         ++ " and token " ++ token

                Just (Shift n) ->
                    Right $ ParserState
                        (n : states)
                        (Terminal token : syms)
                        rest

                Just (Reduce lhs rhs) ->
                    let k            = length rhs
                        states'      = drop k states
                        syms'        = drop k syms
                        topState     = head states'
                        gotoState    = Map.lookup (topState, lhs) (lr1GotoTable table)
                    in case gotoState of
                        Nothing ->
                            Left $ "No goto for state " ++ show topState
                                 ++ " and non-terminal " ++ lhs
                        Just n ->
                            parseStep g table $ ParserState
                                (n : states')
                                (NonTerminal lhs : syms')
                                input

                Just Accept -> Right $ ParserState states syms input

parseLR1 :: Grammar -> LR1Table -> [String] -> ParseResult
parseLR1 g table tokens = go initialState
  where
    initialState = ParserState [0] [] (tokens ++ ["$"])

    go ps = case parseStep g table ps of
        Left err -> ParseError err
        Right ps'@(ParserState states _ input) ->
            case (input, Map.lookup (head states, head input) (lr1ActionTable table)) of
                (["$"], Just Accept) -> ParseSuccess
                _                   -> go ps'
