module IR.Interp.IRInterp
  ( MachineState (..),
    FuncResult (..),
    Interp,
    ProgMap,
    emptyState,
    buildProgMap,
    evalExpr,
    interpFunc,
    runFunc,
    applyBinOp,
  )
where

import Control.Monad.Except
import Control.Monad.State
import Data.Bits (shiftL, shiftR, xor, (.&.), (.|.))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import IR.Frontend.Syntax.IRSyntax

-- Machine state

type TempStore = Map Temp Int

type MemStore = Map Int Int

data MachineState = MachineState
  { tempStore :: TempStore,
    memStore :: MemStore,
    heapPtr :: Int
  }
  deriving (Show)

emptyState :: MachineState
emptyState = MachineState Map.empty Map.empty 1000000

-- Interpretation result

data FuncResult
  = FNormal
  | FReturn [Int]
  deriving (Show)

-- Interpreter monad

-- The interpreter carries the machine state and can raise runtime errors.
type Interp a = ExceptT String (StateT MachineState IO) a

-- Program map

type ProgMap = Map Label FuncDef

buildProgMap :: Program -> ProgMap
buildProgMap = Map.fromList . map (\fd -> (funcName fd, fd))

-- Linearisation and label index

linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s = [s]

buildLabelIndex :: [Stmt] -> Map Label Int
buildLabelIndex stmts =
  Map.fromList [(l, i) | (i, LABEL l) <- zip [0 ..] stmts]

-- Expression evaluator

evalExpr :: ProgMap -> Expr -> Interp Int
evalExpr _ (CONST n) =
  return n
evalExpr _ (TEMP t) = do
  ts <- gets tempStore
  return $ fromMaybe 0 (Map.lookup t ts)
evalExpr _ (NAME _) =
  throwError "NAME used as a value expression (must appear inside CALL or JUMP)"
evalExpr prog (BINOP op e1 e2) = do
  v1 <- evalExpr prog e1
  v2 <- evalExpr prog e2
  return (applyBinOp op v1 v2)
evalExpr prog (MEM e) = do
  addr <- evalExpr prog e
  ms <- gets memStore
  return $ fromMaybe 0 (Map.lookup addr ms)
evalExpr prog (CALL ef args) = do
  argVals <- mapM (evalExpr prog) args
  callFunc prog ef argVals
evalExpr prog (ESEQ s e) = do
  _ <- interpFunc prog s
  evalExpr prog e

-- Function call dispatch

callFunc :: ProgMap -> Expr -> [Int] -> Interp Int
callFunc _ (NAME "alloc") [n] = do
  ptr <- gets heapPtr
  modify (\s -> s {heapPtr = ptr + n * 8})
  return ptr
callFunc _ (NAME "alloc") _ =
  throwError "alloc requires exactly one argument (number of words)"
callFunc _ (NAME "print") args = do
  liftIO $ mapM_ (\v -> putStrLn ("print: " ++ show v)) args
  return 0
callFunc _ (NAME "read_int") _ = do
  line <- liftIO getLine
  case reads line of
    [(n, "")] -> return n
    _ -> throwError ("read_int: not a valid integer: " ++ show line)
callFunc prog (NAME l) args =
  case Map.lookup l prog of
    Nothing -> throwError ("Undefined function: " ++ l)
    Just fd -> do
      callerState <- get
      let callState =
            MachineState
              { tempStore = Map.fromList (zip (funcParams fd) args),
                memStore = memStore callerState,
                heapPtr = heapPtr callerState
              }
      put callState
      result <- interpFunc prog (funcBody fd)
      calleeState <- get
      put
        callerState
          { memStore = memStore calleeState,
            heapPtr = heapPtr calleeState
          }
      return $ case result of
        FReturn (v : _) -> v
        _ -> 0
callFunc _ ef _ =
  throwError ("CALL target must be NAME(label), got: " ++ show ef)

-- Binary operator application

applyBinOp :: BinOp -> Int -> Int -> Int
applyBinOp BAdd v1 v2 = v1 + v2
applyBinOp BSub v1 v2 = v1 - v2
applyBinOp BMul v1 v2 = v1 * v2
applyBinOp BDiv v1 v2 = v1 `div` v2
applyBinOp BMod v1 v2 = v1 `mod` v2
applyBinOp BAnd v1 v2 = v1 .&. v2
applyBinOp BOr v1 v2 = v1 .|. v2
applyBinOp BXor v1 v2 = v1 `xor` v2
applyBinOp BLsh v1 v2 = v1 `shiftL` v2
applyBinOp BRsh v1 v2 = v1 `shiftR` v2
applyBinOp BArsh v1 v2 = v1 `shiftR` v2 -- Haskell shiftR is arithmetic for Int
applyBinOp BEq v1 v2 = if v1 == v2 then 1 else 0
applyBinOp BNe v1 v2 = if v1 /= v2 then 1 else 0
applyBinOp BLt v1 v2 = if v1 < v2 then 1 else 0
applyBinOp BLe v1 v2 = if v1 <= v2 then 1 else 0
applyBinOp BGt v1 v2 = if v1 > v2 then 1 else 0
applyBinOp BGe v1 v2 = if v1 >= v2 then 1 else 0

-- Statement interpreter

-- Interpret a function body (Stmt tree).
interpFunc :: ProgMap -> Stmt -> Interp FuncResult
interpFunc prog body =
  let stmts = linearize body
      labelIdx = buildLabelIndex stmts
   in interpLinear prog stmts labelIdx 0

-- Interpret a linearised statement list from the given program counter.
interpLinear :: ProgMap -> [Stmt] -> Map Label Int -> Int -> Interp FuncResult
interpLinear _ stmts _ pc | pc >= length stmts = return FNormal
interpLinear prog stmts labelIdx pc =
  case stmts !! pc of
    LABEL _ ->
      interpLinear prog stmts labelIdx (pc + 1)
    MOVE (TEMP t) e -> do
      v <- evalExpr prog e
      modify (\s -> s {tempStore = Map.insert t v (tempStore s)})
      interpLinear prog stmts labelIdx (pc + 1)
    MOVE (MEM addrExpr) e -> do
      addr <- evalExpr prog addrExpr
      v <- evalExpr prog e
      modify (\s -> s {memStore = Map.insert addr v (memStore s)})
      interpLinear prog stmts labelIdx (pc + 1)
    MOVE dst _ ->
      throwError ("MOVE destination must be TEMP or MEM, got: " ++ show dst)
    EXP e -> do
      _ <- evalExpr prog e
      interpLinear prog stmts labelIdx (pc + 1)
    SEQ _ _ ->
      throwError "SEQ must not appear in linearised code (internal error)"
    JUMP (NAME l) ->
      case Map.lookup l labelIdx of
        Just pc' -> interpLinear prog stmts labelIdx pc'
        Nothing -> throwError ("JUMP to undefined label: " ++ l)
    JUMP _ ->
      throwError "Indirect JUMP is not supported by this interpreter"
    CJUMP e lt lf -> do
      v <- evalExpr prog e
      let target = if v /= 0 then lt else lf
      case Map.lookup target labelIdx of
        Just pc' -> interpLinear prog stmts labelIdx pc'
        Nothing -> throwError ("CJUMP to undefined label: " ++ target)
    RETURN es -> do
      vs <- mapM (evalExpr prog) es
      return (FReturn vs)

-- Top-level runner

-- Run the interpreter for a single function, returning either a runtime
--   error or the function's result.
runFunc :: ProgMap -> MachineState -> Stmt -> IO (Either String FuncResult)
runFunc prog state' body = do
  (result, _) <- runStateT (runExceptT (interpFunc prog body)) state'
  return result
