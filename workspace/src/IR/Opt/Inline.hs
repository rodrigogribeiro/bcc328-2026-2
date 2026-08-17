module IR.Opt.Inline
  ( InlineConfig (..)
  , defaultInlineConfig
  , inlineProgram
  , removeDeadFuncs
  ) where

import Control.Monad.State
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import Data.Map.Strict (Map)
import Data.Set        (Set)

import IR.Frontend.Syntax.IRSyntax

-- Configuration

data InlineConfig = InlineConfig
  { inlineThreshold :: Int   -- maximum linearised-statement count to inline
  } deriving (Eq, Show)

defaultInlineConfig :: InlineConfig
defaultInlineConfig = InlineConfig { inlineThreshold = 10 }

-- Entry points

-- Inline small non-recursive functions throughout the program, then remove
--   function definitions that are no longer called.
inlineProgram :: InlineConfig -> Program -> Program
inlineProgram cfg prog =
  removeDeadFuncs $
    map (inlineFuncDef funcMap inlineable) prog
  where
    funcMap    = Map.fromList [(funcName fd, fd) | fd <- prog]
    inlineable = Set.fromList
      [ funcName fd
      | fd <- prog
      , funcName fd /= "main"
      , funcSize fd <= inlineThreshold cfg
      , not (isSelfRecursive fd)
      ]

-- Remove function definitions that are never called anywhere in the program.
--   "main" is always kept as the program entry point.
removeDeadFuncs :: Program -> Program
removeDeadFuncs prog =
  filter (\fd -> funcName fd == "main" || funcName fd `Set.member` calledFuncs) prog
  where
    calledFuncs = foldMap (collectCallsStmt . funcBody) prog

-- Eligibility helpers

funcSize :: FuncDef -> Int
funcSize = length . linearize . funcBody

-- True if the function directly calls itself.
isSelfRecursive :: FuncDef -> Bool
isSelfRecursive fd = funcName fd `Set.member` collectCallsStmt (funcBody fd)

collectCallsStmt :: Stmt -> Set Label
collectCallsStmt (MOVE _ e)     
   = collectCallsExpr e
collectCallsStmt (EXP e)        
   = collectCallsExpr e
collectCallsStmt (SEQ s1 s2)    
   = collectCallsStmt s1 `Set.union` collectCallsStmt s2
collectCallsStmt (JUMP e)       
   = collectCallsExpr e
collectCallsStmt (CJUMP e _ _)  
   = collectCallsExpr e
collectCallsStmt (RETURN es)    
   = foldMap collectCallsExpr es
collectCallsStmt (LABEL _)      
   = Set.empty

collectCallsExpr :: Expr -> Set Label
collectCallsExpr (CALL (NAME f) args) 
   = Set.insert f (foldMap collectCallsExpr args)
collectCallsExpr (CALL ef args) 
   = collectCallsExpr ef `Set.union` foldMap collectCallsExpr args
collectCallsExpr (BINOP _ e1 e2) 
   = collectCallsExpr e1 `Set.union` collectCallsExpr e2
collectCallsExpr (MEM e)              
   = collectCallsExpr e
collectCallsExpr (ESEQ s e)           
   = collectCallsStmt s `Set.union` collectCallsExpr e
collectCallsExpr _                    
   = Set.empty

-- Per-function inlining

inlineFuncDef :: Map Label FuncDef -> Set Label -> FuncDef -> FuncDef
inlineFuncDef funcMap inlineable fd =
  fd { funcBody = evalState (rewriteStmt funcMap inlineable (funcBody fd)) 0 }

-- Rewriting monad

type InlineM = State Int

freshId :: InlineM Int
freshId = do { n <- get; put (n + 1); return n }

rewriteStmt :: Map Label FuncDef -> Set Label -> Stmt -> InlineM Stmt
rewriteStmt fm il (MOVE d e)      
   = MOVE <$> rewriteExpr fm il d <*> rewriteExpr fm il e
rewriteStmt fm il (SEQ s1 s2)     
   = SEQ <$> rewriteStmt fm il s1 <*> rewriteStmt fm il s2
rewriteStmt fm il (JUMP e)        
   = JUMP <$> rewriteExpr fm il e
rewriteStmt fm il (CJUMP e l1 l2) 
   = (\e' -> CJUMP e' l1 l2) <$> rewriteExpr fm il e
rewriteStmt fm il (RETURN es)     
   = RETURN <$> mapM (rewriteExpr fm il) es
rewriteStmt fm il (EXP e) =
  case e of
    -- Void call at statement level: inline body directly (avoids ESEQ wrapper).
    CALL (NAME f) args | f `Set.member` il ->
      inlineVoidCall fm il f args
    _ -> EXP <$> rewriteExpr fm il e
rewriteStmt _  _  s               = return s  -- LABEL

rewriteExpr :: Map Label FuncDef -> Set Label -> Expr -> InlineM Expr
rewriteExpr fm il (CALL (NAME f) args) | f `Set.member` il =
  inlineValueCall fm il f args
rewriteExpr fm il (BINOP op e1 e2)
  = BINOP op <$> rewriteExpr fm il e1 <*> rewriteExpr fm il e2
rewriteExpr fm il (MEM e)          
  = MEM  <$> rewriteExpr fm il e
rewriteExpr fm il (CALL ef args)
  = CALL <$> rewriteExpr fm il ef <*> mapM (rewriteExpr fm il) args
rewriteExpr fm il (ESEQ s e) 
  = ESEQ <$> rewriteStmt fm il s <*> rewriteExpr fm il e
rewriteExpr _  _  e = return e

-- Inline a value-returning call  →  ESEQ(body, TEMP retTemp)

inlineValueCall :: Map Label FuncDef -> Set Label -> Label -> [Expr] -> InlineM Expr
inlineValueCall fm il f args = do
  n <- freshId
  let suf = "_il" ++ show n
      fd = fm Map.! f
      locals = localLabels (funcBody fd)
      body0 = renameLocals suf locals (funcBody fd)
      retTemp = "_il_ret" ++ suf
      exitLbl = "L_il_exit" ++ suf
      body1 = transformReturns retTemp exitLbl body0
      -- Remove f from the inlineable set to prevent re-inlining f within its
      -- own expanded body, which would cause infinite rewriting for mutual or
      -- indirect recursion.
      il'     = Set.delete f il
  args'  <- mapM (rewriteExpr fm il)  args   -- args evaluated in caller context
  body2  <- rewriteStmt fm il'         body1  -- body may inline other functions
  let pMoves = paramMoveList (map (++ suf) (funcParams fd)) args'
      full = seqStmts (pMoves ++ [body2, LABEL exitLbl])
  return (ESEQ full (TEMP retTemp))

-- Inline a void call at statement level  →  body as Stmt

inlineVoidCall :: Map Label FuncDef -> Set Label -> Label -> [Expr] -> InlineM Stmt
inlineVoidCall fm il f args = do
  n <- freshId
  let suf = "_il" ++ show n
      fd = fm Map.! f
      locals = localLabels (funcBody fd)
      body0 = renameLocals suf locals (funcBody fd)
      retTemp = "_il_ret" ++ suf   -- scratch temp (used if callee has RETURN [e])
      exitLbl = "L_il_exit" ++ suf
      body1 = transformReturns retTemp exitLbl body0
      il' = Set.delete f il
  args'  <- mapM (rewriteExpr fm il) args
  body2  <- rewriteStmt fm il'        body1
  let pMoves = paramMoveList (map (++ suf) (funcParams fd)) args'
  return (seqStmts (pMoves ++ [body2, LABEL exitLbl]))

-- Helpers

-- All labels DEFINED (by LABEL) inside a statement, including those nested
--   inside ESEQ expressions (which carry a Stmt in expression position).
localLabels :: Stmt -> Set Label
localLabels (LABEL l) = Set.singleton l
localLabels (SEQ s1 s2) = localLabels s1 `Set.union` localLabels s2
localLabels (MOVE _ e) = localLabelsExpr e
localLabels (EXP e) = localLabelsExpr e
localLabels (JUMP e) = localLabelsExpr e
localLabels (CJUMP e _ _) = localLabelsExpr e
localLabels (RETURN es) = foldMap localLabelsExpr es

localLabelsExpr :: Expr -> Set Label
localLabelsExpr (ESEQ s e) 
   = localLabels s `Set.union` localLabelsExpr e
localLabelsExpr (BINOP _ e1 e2) 
   = localLabelsExpr e1 `Set.union` localLabelsExpr e2
localLabelsExpr (MEM e)         
   = localLabelsExpr e
localLabelsExpr (CALL ef args)  
   = foldMap localLabelsExpr (ef : args)
localLabelsExpr _               
   = Set.empty

-- Append suf to every temp and every locally-defined label in a statement.
--   External function names in CALL(NAME g, ...) are left unchanged because
--   g is not in the local-label set.
renameLocals :: String -> Set Label -> Stmt -> Stmt
renameLocals suf locals = goStmt
  where
    renL l = if l `Set.member` locals then l ++ suf else l

    goStmt (LABEL l) = LABEL (l ++ suf)
    goStmt (JUMP e) = JUMP (goExpr e)
    goStmt (CJUMP e l1 l2) = CJUMP (goExpr e) (renL l1) (renL l2)
    goStmt (MOVE d s) = MOVE (goExpr d) (goExpr s)
    goStmt (EXP e) = EXP (goExpr e)
    goStmt (SEQ s1 s2) = SEQ (goStmt s1) (goStmt s2)
    goStmt (RETURN es) = RETURN (map goExpr es)

    goExpr (TEMP t) = TEMP (t ++ suf)
    goExpr (NAME l) = NAME (renL l)
    goExpr (BINOP op e1 e2) = BINOP op (goExpr e1) (goExpr e2)
    goExpr (MEM e) = MEM (goExpr e)
    goExpr (CALL ef args) = CALL (goExpr ef) (map goExpr args)
    goExpr (ESEQ s e) = ESEQ (goStmt s) (goExpr e)
    goExpr e = e

-- Replace every RETURN in the inlined body with an assignment to retTemp
--   followed by a jump to exitLbl, so control always flows to the exit point.
transformReturns :: Temp -> Label -> Stmt -> Stmt
transformReturns retTemp exitLbl = go
  where
    go (RETURN [e]) = SEQ (MOVE (TEMP retTemp) e) (JUMP (NAME exitLbl))
    go (RETURN _) = JUMP (NAME exitLbl)
    go (SEQ s1 s2) = SEQ (go s1) (go s2)
    go s = s

-- Build parameter-assignment statements.
paramMoveList :: [Temp] -> [Expr] -> [Stmt]
paramMoveList ps es = zipWith (\p e -> MOVE (TEMP p) e) ps es

-- Fold a list of statements into a right-nested SEQ.
seqStmts :: [Stmt] -> Stmt
seqStmts [] = EXP (CONST 0)
seqStmts [s] = s
seqStmts (s:ss) = SEQ s (seqStmts ss)

linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s = [s]
