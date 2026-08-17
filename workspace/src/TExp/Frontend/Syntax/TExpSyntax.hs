module TExp.Frontend.Syntax.TExpSyntax where


data Ty
  = TBool
  | TNat
  deriving (Eq, Ord, Show)

data Term
  = TTrue
  | TFalse
  | TIf Term Term Term
  | TZero
  | TSucc Term
  | TPred Term
  | TIsZero Term
  deriving (Eq, Ord, Show)
