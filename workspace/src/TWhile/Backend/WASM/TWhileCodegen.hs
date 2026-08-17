module TWhile.Backend.WASM.TWhileCodegen where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State

import Data.Map (Map)
import qualified Data.Map as Map

import TWhile.Backend.WASM.Pretty ()
import TWhile.Backend.WASM.Syntax
import TWhile.Frontend.Syntax.TWhileSyntax

import Utils.Pretty

compileTWhile :: TWhile -> Either String String
compileTWhile = fmap pretty . twhileCodegen

twhileCodegen :: TWhile -> Either String WasmModule
twhileCodegen (TWhile stmts) =
  case runCodeGenM (mapM_ stmtCodegen stmts) of
    Left err         -> Left err
    Right finalState ->
      let numLocals = nextLocal finalState
          locals    = replicate numLocals I32
          mainFunc  = WasmFunc
            { funcName    = "$main"
            , funcParams  = []
            , funcResults = []
            , funcLocals  = locals
            , funcBody    = instructions finalState
            }
          imports =
            [ WasmImport "env" "print_int" (ImportFunc "$print_int" [I32] [])
            , WasmImport "env" "read_int"  (ImportFunc "$read_int"  []    [I32])
            ]
          exports = [ WasmExport "main" (ExportFunc "$main") ]
      in  Right $ WasmModule imports exports [mainFunc]

-- Code generation monad

data Conf = Conf
  { varMap      :: Map Var Int
  , nextLocal   :: Int   
  , instructions :: [WasmInstr]
  } deriving (Show)

type CodeGenM a = StateT Conf (ExceptT String Identity) a

runCodeGenM :: CodeGenM a -> Either String Conf
runCodeGenM m = runIdentity (runExceptT (execStateT m initConf))

initConf :: Conf
initConf = Conf Map.empty 0 []

addVar :: Var -> CodeGenM Int
addVar v = do
  conf <- get
  case Map.lookup v (varMap conf) of
    Just idx -> return idx
    Nothing  -> do
      let idx = nextLocal conf
      put conf { varMap    = Map.insert v idx (varMap conf)
               , nextLocal = idx + 1
               }
      return idx

getVarIndex :: Var -> CodeGenM Int
getVarIndex v = do
  conf <- get
  case Map.lookup v (varMap conf) of
    Just idx -> return idx
    Nothing  -> throwError $ "Undefined variable: " ++ v

emitInstr :: WasmInstr -> CodeGenM ()
emitInstr i = modify $ \s -> s { instructions = instructions s ++ [i] }

collectInstrs :: CodeGenM () -> CodeGenM [WasmInstr]
collectInstrs m = do
  prev <- gets instructions
  modify $ \s -> s { instructions = [] }
  m
  result <- gets instructions
  modify $ \s -> s { instructions = prev }
  return result

expCodegen :: Exp -> CodeGenM ()
expCodegen (EInt  n) = emitInstr (I32Const n)
expCodegen (EBool True) = emitInstr (I32Const 1)
expCodegen (EBool False) = emitInstr (I32Const 0)
expCodegen (EString _) = throwError "String literals are not supported in the WASM backend"
expCodegen (EVar  v) = getVarIndex v >>= emitInstr . LocalGet
expCodegen (e1 :+: e2) = binop e1 e2 I32Add
expCodegen (e1 :*: e2) = binop e1 e2 I32Mul
expCodegen (e1 :-: e2) = binop e1 e2 I32Sub
expCodegen (e1 :/: e2) = binop e1 e2 I32DivS
expCodegen (e1 :<: e2) = binop e1 e2 I32LtS
expCodegen (e1 :=: e2) = binop e1 e2 I32Eq
expCodegen (Not e) = expCodegen e >> emitInstr I32Eqz
expCodegen (e1 :&&: e2) = do
  thenInstrs <- collectInstrs (expCodegen e2)
  expCodegen e1
  emitInstr (If (Just I32) thenInstrs [I32Const 0])
expCodegen (e1 :||: e2) = do
  elseInstrs <- collectInstrs (expCodegen e2)
  expCodegen e1
  emitInstr (If (Just I32) [I32Const 1] elseInstrs)

binop :: Exp -> Exp -> WasmInstr -> CodeGenM ()
binop e1 e2 op = do 
  expCodegen e1
  expCodegen e2
  emitInstr op

stmtCodegen :: Stmt -> CodeGenM ()
stmtCodegen (SDecl v _ e) = do
  expCodegen e
  idx <- addVar v
  emitInstr (LocalSet idx)
stmtCodegen (SAssign v e) = do
  expCodegen e
  idx <- getVarIndex v
  emitInstr (LocalSet idx)
stmtCodegen (SPrint e) = do
  expCodegen e
  emitInstr (Call "$print_int")
stmtCodegen (SRead _fmt v) = do
  emitInstr (Call "$read_int")
  idx <- getVarIndex v
  emitInstr (LocalSet idx)
stmtCodegen (SIf cond b1 b2) = do
  expCodegen cond
  thenInstrs <- collectInstrs (mapM_ stmtCodegen b1)
  elseInstrs <- collectInstrs (mapM_ stmtCodegen b2)
  emitInstr (If Nothing thenInstrs elseInstrs)
stmtCodegen (SWhile cond body) = do
  condInstrs <- collectInstrs (expCodegen cond)
  bodyInstrs <- collectInstrs (mapM_ stmtCodegen body)
  emitInstr $ Block
    [ Loop $
        condInstrs
        ++ [I32Eqz, BrIf 1]
        ++ bodyInstrs
        ++ [Br 0]
    ]
