module TLine.Frontend.Syntax.TLineSyntax where

data TLine
  = TLine [Stmt]
    deriving (Eq, Ord, Show)

type Var = String

data Ty = TInt | TBool | TString
  deriving (Eq, Ord, Show)

data Stmt
  = SDecl Var Ty Exp
  | SAssign Var Exp
  | SRead Exp Var
  | SPrint Exp
  deriving (Eq, Ord, Show)

data Exp
  = EInt Int
  | EBool Bool
  | EString String
  | EVar Var
  | Exp :+: Exp
  | Exp :*: Exp
  | Exp :-: Exp
  | Exp :/: Exp
  | Exp :<: Exp
  | Exp :=: Exp
  | Not Exp
  deriving (Eq, Ord, Show)
