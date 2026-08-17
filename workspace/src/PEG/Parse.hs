{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module PEG.Parse
  ( Result (..)
  , parse
  , parseWith
  , eval
  , Opts (..)
  , defaultOpts
  , Input
  , PState (..)
  , columns
  ) where

import PEG.Grammar
import PEG.Indent
import PEG.Member
import PEG.Syntax
import PEG.Type
import PEG.TyLevel (Lookup)

data Result a
  = OK a String String
  | Fail
  deriving (Show, Eq)

type Input = [(Char, Int)]

data PState = PState
  { stInput :: Input
  , stCands :: !Interval
  , stAlign :: !Bool
  }

columns :: Int -> String -> Input
columns tabWidth = go 0
  where
    go _ []     = []
    go c (x:xs) = (x, c) : go (next c x) xs

    next _ '\n' = 0
    next c '\t'
      | tabWidth > 1 = ((c `div` tabWidth) + 1) * tabWidth
      | otherwise    = c + 1
    next c _    = c + 1

data Opts = Opts
  { optTokenMode :: RelD
  , optCands     :: Interval
  , optTabWidth  :: Int
  }

defaultOpts :: Opts
defaultOpts = Opts
  { optTokenMode = relD anyR
  , optCands     = fullI
  , optTabWidth  = 8
  }

parse :: Grammar env ty a -> String -> Result a
parse = parseWith defaultOpts

parseWith :: Opts -> Grammar env ty a -> String -> Result a
parseWith opts (Grammar rules start) input =
  case eval rules start (optTokenMode opts) st0 of
    Nothing      -> Fail
    Just (a, st) ->
      let n = length input - length (stInput st)
      in OK a (take n input) (drop n input)
  where
    st0 = PState
      { stInput = columns (optTabWidth opts) input
      , stCands = optCands opts
      , stAlign = False
      }

eval :: forall env ty a
      . Rules env env
     -> PExp env ty a
     -> RelD
     -> PState
     -> Maybe (a, PState)
eval rules = go
  where
    go :: forall t b. PExp env t b -> RelD -> PState -> Maybe (b, PState)
    go (Pure x) _ st = Just (x, st)

    go (Term c) tau st = do
      (x, st') <- terminal tau st
      if x == c then Just (c, st') else Nothing

    go AnyChar tau st = terminal tau st

    go (NT (_ :: Name s)) tau st =
      go (ruleFor (member :: Member s env (TyOf (Lookup s env))
                                          (ResOf (Lookup s env)))
                  rules)
         tau st

    go (Seq ef ex) tau st = do
      (f, st')  <- go ef tau st
      (x, st'') <- go ex tau st'
      pure (f x, st'')

    go (Choice e1 e2) tau st = case go e1 tau st of
      Just r  -> Just r
      Nothing -> go e2 tau st

    go (Star e) tau st = Just (starLoop (go e tau) st)

    go (Not e) tau st = case go e tau st of
      Just _  -> Nothing
      Nothing -> Just ((), st)

    go (Map f e) tau st = do
      (x, st') <- go e tau st
      pure (f x, st')

    go (Indent rho e) tau st = do
      (x, st') <- go e tau st { stCands = preimage rd (stCands st) }
      pure ( x
           , st' { stCands = interI (stCands st) (image rd (stCands st')) } )
      where
        rd = relD rho

    go (Position sigma e) _ st = go e (relD sigma) st

    go (Align e) tau st = do
      (x, st') <- go e tau st { stAlign = True }
      pure (x, st' { stAlign = stAlign st && stAlign st' })

terminal :: RelD -> PState -> Maybe (Char, PState)
terminal tau (PState input cands aligned) = case input of
  []            -> Nothing
  ((x, i) : xs)
    | aligned   ->
        if memberI i cands
          then Just (x, PState xs (singletonI i) False)
          else Nothing
    | otherwise ->
        if memberI i (preimage tau cands)
          then Just (x, PState xs (interI cands (image tau (singletonI i))) False)
          else Nothing

starLoop :: (PState -> Maybe (a, PState)) -> PState -> ([a], PState)
starLoop step = loop
  where
    loop st = case step st of
      Nothing       -> ([], st)
      Just (x, st') -> let (xs, rest) = loop st' in (x : xs, rest)

ruleFor :: Member s defs ty a -> Rules env defs -> PExp env ty a
ruleFor Here      (RCons _ body _)    = body
ruleFor (There m) (RCons _ _    rest) = ruleFor m rest
