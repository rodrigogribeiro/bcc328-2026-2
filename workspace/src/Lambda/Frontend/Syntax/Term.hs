module Lambda.Frontend.Syntax.Term where

type Name = String

data Lit
  = LInt  Int
  | LBool Bool
  deriving (Show, Eq)

data Term
  = Var Name
  | Lam Name Term
  | App Term Term
  | Lit Lit          -- integer or boolean constant
  deriving (Show, Eq)
