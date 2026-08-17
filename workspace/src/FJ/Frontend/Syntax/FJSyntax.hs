module FJ.Frontend.Syntax.FJSyntax where

type ClassName  = String
type FieldName  = String
type MethodName = String
type VarName    = String

-- In FJ every type is identified by a class name.
newtype FJType = FJType { unFJType :: ClassName }
  deriving (Show, Eq, Ord)

-- A complete FJ program: class declarations + main expression.
data Program = Program
  { progClasses :: [ClassDecl]
  , progMain    :: Expr
  } deriving (Show)

data ClassDecl = ClassDecl
  { cdName    :: ClassName
  , cdSuper   :: ClassName
  , cdFields  :: [(FJType, FieldName)]
  , cdCtor    :: Constructor
  , cdMethods :: [MethodDecl]
  } deriving (Show)

data Constructor = Constructor
  { ctorClass  :: ClassName
  , ctorParams :: [(FJType, VarName)]
  , ctorSuper  :: [VarName] 
  , ctorInits  :: [(FieldName, VarName)]
  } deriving (Show)

data MethodDecl = MethodDecl
  { mdRetType :: FJType
  , mdName    :: MethodName
  , mdParams  :: [(FJType, VarName)]
  , mdBody    :: Expr
  } deriving (Show)

data Expr
  = EVar    VarName
  | EField  Expr FieldName
  | EInvk   Expr MethodName [Expr]
  | ENew    ClassName [Expr]
  | ECast   ClassName Expr
  deriving (Show, Eq)
