module Parsing.LR.LRParser
  ( Action (..)
  , ParsingTable (..)
  , ParseResult (..)
  , ParserState (..)
  , parseStep
  , parseLR
  ) where

import qualified Data.Map as Map

import Parsing.Grammar


-- ============================================================================
-- Shared Types
-- ============================================================================

data Action
    = Shift Int
    | Reduce String [Symbol]
    | Accept
    deriving (Eq, Ord, Show)

-- Parsing table shared by LR(0), SLR, and LR(1).
-- The table is built differently by each algorithm, but the parsing loop
-- only reads actionTable and gotoTable, so the structure is identical.
data ParsingTable = ParsingTable
    { actionTable :: Map.Map (Int, String) Action
    , gotoTable   :: Map.Map (Int, String) Int
    } deriving (Show)

data ParseResult
    = ParseSuccess
    | ParseError String
    deriving (Eq, Ord, Show)

data ParserState = ParserState
    { stateStack  :: [Int]
    , symbolStack :: [Symbol]
    , inputBuffer :: [String]
    } deriving (Eq, Ord, Show)


-- ============================================================================
-- Parsing Algorithm
-- ============================================================================

-- Perform one step of LR parsing.
parseStep :: Grammar -> ParsingTable -> ParserState -> Either String ParserState
parseStep g table (ParserState states syms input) =
    case input of
        [] -> Left "Unexpected end of input"
        (token : rest) ->
            let currentState = head states
                action       = Map.lookup (currentState, token) (actionTable table)
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
                    let k         = length rhs
                        states'   = drop k states
                        syms'     = drop k syms
                        topState  = head states'
                        gotoState = Map.lookup (topState, lhs) (gotoTable table)
                    in case gotoState of
                        Nothing ->
                            Left $ "No goto for state " ++ show topState
                                 ++ " and non-terminal " ++ lhs
                        Just n ->
                            parseStep g table $ ParserState
                                (n : states')
                                (NonTerminal lhs : syms')
                                input  -- input not consumed on reduce

                Just Accept -> Right $ ParserState states syms input

-- Parse a token sequence using any LR parsing table.
parseLR :: Grammar -> ParsingTable -> [String] -> ParseResult
parseLR g table tokens = go (ParserState [0] [] (tokens ++ ["$"]))
  where
    go ps = case parseStep g table ps of
        Left err -> ParseError err
        Right ps'@(ParserState states _ input) ->
            case (input, Map.lookup (head states, head input) (actionTable table)) of
                (["$"], Just Accept) -> ParseSuccess
                _                   -> go ps'
