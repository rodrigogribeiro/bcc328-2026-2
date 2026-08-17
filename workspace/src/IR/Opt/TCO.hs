module IR.Opt.TCO
  ( tcoProgram
  , tcoFuncDef
  ) where

import IR.Frontend.Syntax.IRSyntax

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

tcoProgram :: Program -> Program
tcoProgram = map tcoFuncDef

-- | Transform self-tail-calls in one function into a loop.
tcoFuncDef :: FuncDef -> FuncDef
tcoFuncDef fd
  | not (anyTailCall (funcName fd) stmts) = fd
  | otherwise = fd { funcBody = rebuildSeq (LABEL lh : transformed) }
  where
    stmts       = linearize (funcBody fd)
    lh          = "L_tco_" ++ funcName fd
    transformed = transformStmts (funcName fd) (funcParams fd) lh stmts

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

-- | True if the linearised statement list contains a self-tail-call of f.
-- Two patterns are recognised:
--   (1) RETURN [CALL(NAME f, args)]          -- value-returning tail call
--   (2) EXP(CALL(NAME f, args)); RETURN []   -- void tail call
anyTailCall :: Label -> [Stmt] -> Bool
anyTailCall f stmts =
  any isTCO stmts ||
  any isVoidTCO (zip stmts (drop 1 stmts))
  where
    isTCO (RETURN [CALL (NAME g) _]) = f == g
    isTCO _                          = False

    isVoidTCO (EXP (CALL (NAME g) _), RETURN []) = f == g
    isVoidTCO _                                   = False

-- ---------------------------------------------------------------------------
-- Transformation
-- ---------------------------------------------------------------------------

-- | Replace self-tail-calls in a linearised list with parameter assignments
-- followed by a back-edge jump to the loop header lh.
transformStmts :: Label -> [Temp] -> Label -> [Stmt] -> [Stmt]
transformStmts f params lh = go
  where
    n        = length params
    tcoTemps = ["_tco_" ++ show i | i <- [0 .. n - 1]]

    -- Evaluate args into scratch temps first, then assign to params.
    -- The two-step avoids write-after-read hazards when args mention params
    -- (e.g. return f(b, a) with params (a, b)).
    makeTCO :: [Expr] -> [Stmt]
    makeTCO args =
      zipWith (\t e -> MOVE (TEMP t) e) tcoTemps args ++
      zipWith (\p t -> MOVE (TEMP p) (TEMP t)) params tcoTemps ++
      [JUMP (NAME lh)]

    go [] = []
    go (RETURN [CALL (NAME g) args] : rest)
      | g == f = makeTCO args ++ go rest
    go (EXP (CALL (NAME g) args) : RETURN [] : rest)
      | g == f = makeTCO args ++ go rest
    go (s : rest) = s : go rest

-- ---------------------------------------------------------------------------
-- Utilities (local copies to keep the module self-contained)
-- ---------------------------------------------------------------------------

linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s           = [s]

rebuildSeq :: [Stmt] -> Stmt
rebuildSeq []     = EXP (CONST 0)
rebuildSeq [s]    = s
rebuildSeq (s:ss) = SEQ s (rebuildSeq ss)
