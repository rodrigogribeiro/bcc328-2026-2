module TImp.Frontend.Syntax.TImpSyntax where

type Var   = String
type Name  = String
type Field = String

-- Types

data Ty
  = TInt
  | TBool
  | TString
  | TRecord Name  -- record type identified by name
  deriving (Eq, Ord, Show)

-- Return type of a function (extends Ty with void)
data RetTy
  = RTVoid
  | RTTy Ty
  deriving (Eq, Ord, Show)

-- Declarations

data FieldDecl = FieldDecl Field Ty
  deriving (Eq, Ord, Show)

data RecordDecl = RecordDecl Name [FieldDecl]
  deriving (Eq, Ord, Show)

data Param = Param Var Ty
  deriving (Eq, Ord, Show)

data FuncDecl = FuncDecl Name [Param] RetTy Block
  deriving (Eq, Ord, Show)

data Decl
  = DRecord RecordDecl
  | DFunc   FuncDecl
  deriving (Eq, Ord, Show)

-- Statements

type Block = [Stmt]

data Stmt
  = SDecl        Var Ty Exp        -- var x : T = e;
  | SAssign      Var Exp           -- x := e;
  | SFieldAssign Var Field Exp     -- x.f := e;
  | SWhile       Exp Block         -- while e { ... }
  | SIf          Exp Block Block   -- if e { ... } else { ... }
  | SRead        Exp Var           -- read "prompt" x;
  | SPrint       Exp               -- print e;
  | SReturn      (Maybe Exp)       -- return e; | return;
  | SCall        Name [Exp]        -- f(args);  (discards return value)
  deriving (Eq, Ord, Show)

-- Expressions

data Exp
  = EInt    Int
  | EBool   Bool
  | EString String
  | EVar    Var
  | EField  Exp Field              -- e.f   (field access)
  | ECall   Name [Exp]             -- f(args)
  | ENew    Name [(Field, Exp)]    -- new R { f1 = e1, ... }
  | Exp :+:  Exp
  | Exp :*:  Exp
  | Exp :-:  Exp
  | Exp :/:  Exp
  | Exp :<:  Exp                   -- <
  | Exp :>:  Exp                   -- >
  | Exp :=:  Exp                   -- ==
  | Exp :!=: Exp                   -- !=
  | Exp :<=: Exp                   -- <=
  | Exp :>=: Exp                   -- >=
  | Not      Exp
  | Exp :&&: Exp
  | Exp :||: Exp
  deriving (Eq, Ord, Show)

-- Program

-- A TImp program: declarations (records and functions) followed by
-- top-level statements (the implicit main body).
data TImp = TImp [Decl] Block
  deriving (Eq, Ord, Show)
