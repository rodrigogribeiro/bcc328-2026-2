module IR.Backend.X86.CFG
  ( -- * Core types
    SArr
  , LabelMap
    -- * CFG bundle
  , FuncCFG (..)
  , buildCFG
    -- * Construction helpers
  , canonicalize
  , linearize
  , buildSArr
  , buildLabelMap
    -- * Graph queries
  , succs
  , cfgIndices
  , cfgStmtAt
  ) where

import Data.Array        (Array, (!), bounds, listArray)
import Data.Map.Strict   (Map)
import qualified Data.Map.Strict as Map

import IR.Frontend.Syntax.IRSyntax

-- ── Core types ──────────────────────────────────────────────────────────────

-- | Statements indexed by their position in the linearised sequence.
type SArr = Array Int Stmt

-- | Maps each label name to the index of the LABEL statement that defines it.
type LabelMap = Map Label Int

-- ── CFG bundle ──────────────────────────────────────────────────────────────

-- | All static control-flow information for a single function body.
--   Downstream phases (liveness, interference graph, code generation) carry
--   one 'FuncCFG' instead of three separate arguments.
data FuncCFG = FuncCFG
  { cfgStmts    :: SArr      -- ^ linearised statement array
  , cfgLabelMap :: LabelMap  -- ^ label → index map
  } deriving Show

-- | Build the CFG for a function body.  Canonicalises (removes ESEQ nodes),
--   linearises the nested 'SEQ' tree, stores the result in an array, and
--   builds the label map in one pass.
buildCFG :: Stmt -> FuncCFG
buildCFG body =
  let stmts = linearize (canonicalize body)
  in FuncCFG { cfgStmts    = buildSArr     stmts
             , cfgLabelMap = buildLabelMap stmts }

-- ── ESEQ canonicalization ────────────────────────────────────────────────────

-- | Remove all 'ESEQ' nodes from a statement tree by hoisting their statement
--   parts to the enclosing statement level (Tiger book ch. 8 canonicalization).
--
--   After 'canonicalize' no 'ESEQ' node remains anywhere in the tree; every
--   'ESEQ(s, e)' has been replaced by a preceding sequence of statements (the
--   canonicalised form of @s@) followed by the bare expression @e@.
canonicalize :: Stmt -> Stmt
canonicalize s = mkSeq (canonList s)
  where
    mkSeq []     = EXP (CONST 0)  -- degenerate; should not occur in practice
    mkSeq [x]    = x
    mkSeq (x:xs) = SEQ x (mkSeq xs)

-- | Flatten and ESEQ-eliminate a statement into a primitive list.
canonList :: Stmt -> [Stmt]
canonList (SEQ s1 s2) = canonList s1 ++ canonList s2
canonList (MOVE (TEMP t) src) =
  let (ss, src') = pullESeqs src
  in ss ++ [MOVE (TEMP t) src']
canonList (MOVE (MEM addr) val) =
  let (ss1, addr') = pullESeqs addr
      (ss2, val')  = pullESeqs val
  in ss1 ++ ss2 ++ [MOVE (MEM addr') val']
canonList (MOVE dst _) = [dst `seq` LABEL "_bad_move"]  -- malformed
canonList (EXP e) =
  let (ss, e') = pullESeqs e in ss ++ [EXP e']
canonList (CJUMP e lt lf) =
  let (ss, e') = pullESeqs e in ss ++ [CJUMP e' lt lf]
canonList (JUMP e) =
  let (ss, e') = pullESeqs e in ss ++ [JUMP e']
canonList (RETURN es) =
  let pairs = map pullESeqs es
  in concatMap fst pairs ++ [RETURN (map snd pairs)]
canonList s = [s]  -- LABEL (no sub-expressions)

-- | Extract all 'ESEQ' nodes from an expression, returning the list of hoisted
--   statements (in evaluation order) and the resulting ESEQ-free expression.
pullESeqs :: Expr -> ([Stmt], Expr)
pullESeqs (ESEQ s e) =
  let (ss, e') = pullESeqs e
  in (canonList s ++ ss, e')
pullESeqs (BINOP op e1 e2) =
  let (ss1, e1') = pullESeqs e1
      (ss2, e2') = pullESeqs e2
  in (ss1 ++ ss2, BINOP op e1' e2')
pullESeqs (MEM e) =
  let (ss, e') = pullESeqs e in (ss, MEM e')
pullESeqs (CALL ef args) =
  let (ssf, ef') = pullESeqs ef
      pairs      = map pullESeqs args
  in (ssf ++ concatMap fst pairs, CALL ef' (map snd pairs))
pullESeqs e = ([], e)   -- CONST, TEMP, NAME

-- ── Construction helpers ─────────────────────────────────────────────────────

-- | Flatten a nested 'SEQ' tree into a left-to-right list of primitive
--   statements.  The result contains no 'SEQ' nodes.
linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s           = [s]

-- | Pack a statement list into a 0-based array.
buildSArr :: [Stmt] -> SArr
buildSArr stmts = listArray (0, length stmts - 1) stmts

-- | Collect every @LABEL l@ and record its index.
buildLabelMap :: [Stmt] -> LabelMap
buildLabelMap stmts =
  Map.fromList [ (l, i) | (i, LABEL l) <- zip [0 ..] stmts ]

-- ── Graph queries ────────────────────────────────────────────────────────────

-- | Direct successors of statement at index @i@ in a linearised function.
--
--   Control-flow rules:
--
--   * 'RETURN'        → no successors (function exit).
--   * @JUMP (NAME l)@ → one successor, the statement at label @l@.
--   * @JUMP _@        → no successors (indirect jump; target unknown statically).
--   * @CJUMP _ lt lf@ → up to two successors: the true label @lt@ and the
--                        false label @lf@.  A label absent from 'cfgLabelMap'
--                        is silently dropped (guards against malformed IR).
--   * Everything else → fall-through to @i + 1@, unless @i@ is the last
--                        statement.
succs :: FuncCFG -> Int -> [Int]
succs cfg i
  | i < lo || i > hi = []
  | otherwise = case cfgStmts cfg ! i of
      RETURN _       -> []
      JUMP (NAME l)  -> resolve [l]
      JUMP _         -> []
      CJUMP _ lt lf  -> resolve [lt, lf]
      _              -> [ i + 1 | i + 1 <= hi ]
  where
    (lo, hi) = bounds (cfgStmts cfg)
    resolve ls = [ j | l <- ls, Just j <- [Map.lookup l (cfgLabelMap cfg)] ]

-- | All valid statement indices in the CFG, in order.
cfgIndices :: FuncCFG -> [Int]
cfgIndices cfg = let (lo, hi) = bounds (cfgStmts cfg) in [lo .. hi]

-- | Look up the statement at a given index.
cfgStmtAt :: FuncCFG -> Int -> Stmt
cfgStmtAt cfg i = cfgStmts cfg ! i
