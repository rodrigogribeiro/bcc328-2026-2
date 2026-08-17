module IR.Frontend.Syntax.IRSyntax where

-- A temporary variable (pseudo-register).
type Temp  = String

-- A code label.
type Label = String

-- Binary operators.
data BinOp
  = BAdd  -- ADD
  | BSub  -- SUB
  | BMul  -- MUL
  | BDiv  -- DIV
  | BMod  -- MOD
  | BAnd  -- AND  (bitwise)
  | BOr   -- OR   (bitwise)
  | BXor  -- XOR  (bitwise)
  | BLsh  -- LSHIFT
  | BRsh  -- RSHIFT  (logical)
  | BArsh -- ARSHIFT (arithmetic)
  | BEq   -- EQ  (1 if equal,    0 otherwise)
  | BNe   -- NEQ (1 if not equal)
  | BLt   -- LT
  | BLe   -- LEQ
  | BGt   -- GT
  | BGe   -- GEQ
  deriving (Eq, Ord, Show)

-- IRT expressions (produce a word-sized value).
data Expr
  = CONST  Int             -- integer constant
  | TEMP   Temp            -- temporary variable
  | NAME   Label           -- address of a label
  | BINOP  BinOp Expr Expr -- binary operation
  | MEM    Expr            -- memory read at address
  | CALL   Expr [Expr]     -- function call (first arg is callee address)
  | ESEQ   Stmt Expr       -- execute statement for effect, then evaluate expression
  deriving (Eq, Ord, Show)

-- IRT statements (produce side effects).
data Stmt
  = MOVE   Expr Expr       -- write value to TEMP or MEM destination
  | EXP    Expr            -- evaluate expression, discard result
  | SEQ    Stmt Stmt       -- sequential composition
  | JUMP   Expr            -- unconditional jump to address
  | CJUMP  Expr Label Label --conditional jump: if expr /= 0, jump to first label; else second
  | LABEL  Label           -- define a label at this point
  | RETURN [Expr]          -- return zero or more values from the current function
  deriving (Eq, Ord, Show)

-- A function definition: name, parameter temporaries, and body statement.
data FuncDef = FuncDef
  { funcName   :: Label
  , funcParams :: [Temp]
  , funcBody   :: Stmt
  } deriving (Eq, Ord, Show)

-- A program is a list of function definitions.
type Program = [FuncDef]
