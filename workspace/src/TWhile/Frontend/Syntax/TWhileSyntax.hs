module TWhile.Frontend.Syntax.TWhileSyntax where

data TWhile
  = TWhile [Stmt]
    deriving (Eq, Ord, Show)

type Var = String

data Ty = TInt | TBool | TString
  deriving (Eq, Ord, Show)

type Block = [Stmt]

data Stmt
  = SDecl Var Ty Exp
  | SAssign Var Exp
  | SWhile Exp Block
  | SIf Exp Block Block
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
  | Exp :&&: Exp
  | Exp :||: Exp
  deriving (Eq, Ord, Show)
