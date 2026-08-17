module IR.Backend.X86.IRToX86
  ( irToX86
  ) where

import Control.Monad       (when)
import Control.Monad.State
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set

import IR.Frontend.Syntax.IRSyntax
import IR.Backend.X86.X86Syntax
import IR.Backend.X86.CFG      (canonicalize, linearize)
import IR.Backend.X86.GraphColor

-- ── Code generation monad ────────────────────────────────────────────────────

-- | Monad state: instructions (reversed) and extra stack bytes pushed by
--   BINOP scratch saves (not counting caller-save or frame pushes).
--   This parity is needed to compute 16-byte call alignment correctly.
data MState = MState [Instr] Int

type X86M = State MState

emit :: Instr -> X86M ()
emit i = modify (\(MState is d) -> MState (i : is) d)

-- | Push a register and record the 8-byte depth increase.
pushScratch :: Reg -> X86M ()
pushScratch r = do
  emit (Pushq (Reg r))
  modify (\(MState is d) -> MState is (d + 8))

-- | Pop into a register and record the 8-byte depth decrease.
popScratch :: Reg -> X86M ()
popScratch r = do
  emit (Popq (Reg r))
  modify (\(MState is d) -> MState is (d - 8))

getExtraDepth :: X86M Int
getExtraDepth = gets (\(MState _ d) -> d)

run :: X86M () -> [Instr]
run m = let MState is _ = execState m (MState [] 0) in reverse is

-- ── Per-function environment ─────────────────────────────────────────────────

data Env = Env
  { envCol     :: Coloring  -- temp → register or stack slot
  , envCSaved  :: [Reg]     -- callee-saved regs pushed in prologue (for epilogue)
  , envFAdj    :: Int       -- subq frame amount (0 = no subq)
  , envCSRegs  :: [Reg]     -- caller-saved pool regs in use (saved around calls)
  }

-- ── Entry point ──────────────────────────────────────────────────────────────

-- | Compile an IRT program to an X86-64 assembly program.
--   Prepends the libc-based runtime (print, read_int, alloc).
irToX86 :: Program -> X86Program
irToX86 prog =
  X86Program (runtimeInstrs ++ concatMap compileFunc prog)

-- ── Libc runtime ─────────────────────────────────────────────────────────────

runtimeInstrs :: [Instr]
runtimeInstrs = concat
  [ [ Dir ".section .note.GNU-stack,\"\",@progbits"
    , Dir ""
    , Dir ".section .rodata"
    , Dir ".fmt_out:  .string \"%d\\n\""
    , Dir ".fmt_in:   .string \"%d\""
    , Dir ""
    , Dir ".section .bss"
    , Dir ".scan_buf: .quad 0"
    , Dir ""
    , Dir ".section .text"
    , Dir ""
    ]

    -- print(val) → void   [val in %rdi]
  , [ Dir "# print(val) -> void  [val in %rdi]"
    , GlobLabel "print"
    , Pushq (Reg RBP), Movq (Reg RSP) (Reg RBP)
    , Movq  (Reg RDI) (Reg RSI)
    , Leaq  (RipRel ".fmt_out") (Reg RDI)
    , Xorq  (Reg RAX) (Reg RAX)
    , Callq "printf"
    , Popq  (Reg RBP), Retq
    , Dir ""
    ]

    -- read_int() → int   [result in %rax]
  , [ Dir "# read_int() -> int  [result in %rax]"
    , GlobLabel "read_int"
    , Pushq (Reg RBP), Movq (Reg RSP) (Reg RBP)
    , Leaq  (RipRel ".fmt_in")   (Reg RDI)
    , Leaq  (RipRel ".scan_buf") (Reg RSI)
    , Xorq  (Reg RAX) (Reg RAX)
    , Callq "scanf"
    , Movq  (RipRel ".scan_buf") (Reg RAX)
    , Popq  (Reg RBP), Retq
    , Dir ""
    ]

    -- alloc(n) → ptr   [n in %rdi, result in %rax]
  , [ Dir "# alloc(n) -> ptr  [n in %rdi]"
    , GlobLabel "alloc"
    , Pushq (Reg RBP), Movq (Reg RSP) (Reg RBP)
    , Imulq (Imm 8) (Reg RDI)
    , Callq "malloc"
    , Popq  (Reg RBP), Retq
    , Dir ""
    ]
  ]

-- ── Function compilation ──────────────────────────────────────────────────────

compileFunc :: FuncDef -> [Instr]
compileFunc fd =
  let body0             = canonicalize (funcBody fd)
      (col, spillBytes) = colorFunc (funcParams fd) body0
      csSaved           = calleeSavedInCol col
      fAdj              = frameAdj (length csSaved) spillBytes
      csRegs            = callerSavedInCol col
      env               = Env col csSaved fAdj csRegs
      stmts             = linearize body0
      body              = run (mapM_ (compileStmt env) stmts)
  in Dir "" :
     Dir (".globl " ++ funcName fd) :
     GlobLabel (funcName fd) :
     prologue csSaved fAdj ++
     loadParams (funcParams fd) col ++
     body ++
     epilogue env  -- fallthrough path (dead code when all paths end with RETURN)

-- Caller-saved pool regs present in the coloring (saved around every CALL).
callerSavedInCol :: Coloring -> [Reg]
callerSavedInCol col =
  [ r | r <- allocPool
      , r `Set.member` callerSaved
      , InReg r `elem` Map.elems col ]

-- ── Prologue and epilogue ─────────────────────────────────────────────────────

prologue :: [Reg] -> Int -> [Instr]
prologue csSaved fAdj =
  [ Pushq (Reg RBP)
  , Movq  (Reg RSP) (Reg RBP)
  ]
  ++ map (Pushq . Reg) csSaved
  ++ [ Subq (Imm fAdj) (Reg RSP) | fAdj > 0 ]

epilogue :: Env -> [Instr]
epilogue env =
  [ Addq (Imm (envFAdj env)) (Reg RSP) | envFAdj env > 0 ]
  ++ map (Popq . Reg) (reverse (envCSaved env))
  ++ [ Popq (Reg RBP), Retq ]

-- Copy parameters from ABI registers into their allocated locations.
loadParams :: [Temp] -> Coloring -> [Instr]
loadParams params col = concat $ zipWith load params argRegs
  where
    load t r = case Map.lookup t col of
      Just (InReg dr) | dr /= r -> [Movq (Reg r) (Reg dr)]
      Just (InReg _)             -> []          -- already in the right reg
      Just (InMem off)           -> [Movq (Reg r) (Mem off RBP)]
      Nothing                    -> []          -- unused param

-- ── Temporary access ─────────────────────────────────────────────────────────

-- Load temporary t into %rax (scratchAcc).
loadTemp :: Temp -> Coloring -> X86M ()
loadTemp t col = case Map.lookup t col of
  Just (InReg r)   -> when (r /= scratchAcc) $ emit (Movq (Reg r) (Reg scratchAcc))
  Just (InMem off) -> emit (Movq (Mem off RBP) (Reg scratchAcc))
  Nothing          -> error ("loadTemp: unknown temp " ++ t)

-- Store %rax (scratchAcc) into temporary t.
storeTemp :: Temp -> Coloring -> X86M ()
storeTemp t col = case Map.lookup t col of
  Just (InReg r)   -> when (r /= scratchAcc) $ emit (Movq (Reg scratchAcc) (Reg r))
  Just (InMem off) -> emit (Movq (Reg scratchAcc) (Mem off RBP))
  Nothing          -> error ("storeTemp: unknown temp " ++ t)

-- ── Expression compilation  (result always in %rax = scratchAcc) ─────────────

compileExpr :: Env -> Expr -> X86M ()

compileExpr _   (CONST n)  = emit (Movq (Imm n) (Reg scratchAcc))

compileExpr env (TEMP t)   = loadTemp t (envCol env)

compileExpr _   (NAME _)   = error "NAME cannot appear standalone"

compileExpr env (BINOP op e1 e2) = do
  compileExpr env e1
  pushScratch scratchAcc          -- push e1; survives any call inside e2
  compileExpr env e2              -- rax = e2
  popScratch  scratchBinop        -- pop e1 → r11
  compileBinOp op

compileExpr env (MEM e) = do
  compileExpr env e
  emit (Movq (Mem 0 scratchAcc) (Reg scratchAcc))   -- rax = *rax

compileExpr env (CALL (NAME f) args) = compileCall env f args

compileExpr _   (CALL _ _) = error "only direct calls supported"

compileExpr env (ESEQ s e) = do
  compileStmt env s
  compileExpr env e

-- ── BinOp translation ────────────────────────────────────────────────────────
-- At entry: r11 = e1 (scratchBinop),  rax = e2 (scratchAcc).

compileBinOp :: BinOp -> X86M ()

-- Commutative arithmetic: rax = rax OP r11
compileBinOp BAdd = emit (Addq  (Reg scratchBinop) (Reg scratchAcc))
compileBinOp BMul = emit (Imulq (Reg scratchBinop) (Reg scratchAcc))

-- Subtraction: rax = e1 - e2 = r11 - rax  →  negate rax, then add r11
compileBinOp BSub = do
  emit (Negq (Reg scratchAcc))
  emit (Addq (Reg scratchBinop) (Reg scratchAcc))

-- Division / modulo: rax = e1 ÷ e2
-- We have r11 = e1, rax = e2 (divisor).
-- Swap so rax = e1 and use r10 (scratchMem) to hold the divisor.
compileBinOp BDiv = do
  emit (Movq (Reg scratchAcc)   (Reg scratchMem))   -- r10 = e2 (divisor)
  emit (Movq (Reg scratchBinop) (Reg scratchAcc))   -- rax = e1 (dividend)
  emit Cqo                                           -- sign-extend rax → rdx:rax
  emit (Idivq (Reg scratchMem))                      -- rax = rax ÷ r10
compileBinOp BMod = do
  emit (Movq (Reg scratchAcc)   (Reg scratchMem))
  emit (Movq (Reg scratchBinop) (Reg scratchAcc))
  emit Cqo
  emit (Idivq (Reg scratchMem))
  emit (Movq (Reg scratchDiv) (Reg scratchAcc))     -- rax = rdx (remainder)

-- Bitwise: commutative, same pattern as BAdd
compileBinOp BAnd = emit (Andq (Reg scratchBinop) (Reg scratchAcc))
compileBinOp BOr  = emit (Orq  (Reg scratchBinop) (Reg scratchAcc))
compileBinOp BXor = emit (Xorq (Reg scratchBinop) (Reg scratchAcc))

-- Shifts: value = r11 = e1, count = rax = e2.
-- Note: x86 requires the count in %cl; this temporarily uses %rcx.
-- If %rcx holds a live temporary, its allocated register/slot is the
-- canonical location; the value in %rcx here is stale and will be
-- reloaded on the next use of that temporary.
compileBinOp BLsh = do
  emit (Movq (Reg scratchAcc)   (Reg RCX))          -- cl = count
  emit (Movq (Reg scratchBinop) (Reg scratchAcc))   -- rax = value
  emit (Salq (Reg RCX) (Reg scratchAcc))
compileBinOp BRsh = do
  emit (Movq (Reg scratchAcc)   (Reg RCX))
  emit (Movq (Reg scratchBinop) (Reg scratchAcc))
  emit (Shrq (Reg RCX) (Reg scratchAcc))
compileBinOp BArsh = do
  emit (Movq (Reg scratchAcc)   (Reg RCX))
  emit (Movq (Reg scratchBinop) (Reg scratchAcc))
  emit (Sarq (Reg RCX) (Reg scratchAcc))

-- Comparisons: flags from e1 - e2 = r11 - rax
--   cmpq src, dst  ≡  dst − src  ∴ cmpq rax, r11  ≡  r11 − rax  ✓
compileBinOp BEq = cmpAndSet E
compileBinOp BNe = cmpAndSet NE
compileBinOp BLt = cmpAndSet L
compileBinOp BLe = cmpAndSet LE
compileBinOp BGt = cmpAndSet G
compileBinOp BGe = cmpAndSet GE

cmpAndSet :: Cc -> X86M ()
cmpAndSet cc = do
  emit (Cmpq (Reg scratchAcc) (Reg scratchBinop))   -- flags ← r11 − rax
  emit (Setcc cc AL)                                 -- %al ← cc result
  emit (Movzbq AL (Reg scratchAcc))                  -- zero-extend to rax

-- ── Statement compilation ────────────────────────────────────────────────────

compileStmt :: Env -> Stmt -> X86M ()

compileStmt env (MOVE (TEMP t) e) = do
  compileExpr env e
  storeTemp t (envCol env)

compileStmt env (MOVE (MEM addrE) valE) = do
  compileExpr env addrE
  emit (Movq (Reg scratchAcc) (Reg scratchMem))    -- r10 = address
  compileExpr env valE
  emit (Movq (Reg scratchAcc) (Mem 0 scratchMem)) -- *r10 = rax

compileStmt _   (MOVE _ _) = error "MOVE: invalid destination"

compileStmt env (EXP e) = compileExpr env e        -- result discarded

compileStmt _   (LABEL l) = emit (LocLabel l)

compileStmt _   (JUMP (NAME l)) = emit (Jmp l)

compileStmt _   (JUMP _) = error "indirect JUMP not supported"

compileStmt env (CJUMP cond lt lf) = do
  compileExpr env cond
  emit (Testq (Reg scratchAcc) (Reg scratchAcc))
  emit (Jcc NE lt)
  emit (Jmp lf)

compileStmt env (RETURN []) = mapM_ emit (epilogue env)

compileStmt env (RETURN (e:_)) = do
  compileExpr env e                                  -- result → rax
  mapM_ emit (epilogue env)                          -- teardown + retq

compileStmt env (SEQ s1 s2) = do                   -- shouldn't appear after linearise
  compileStmt env s1
  compileStmt env s2

-- ── Function calls ────────────────────────────────────────────────────────────

compileCall :: Env -> String -> [Expr] -> X86M ()
compileCall env f args = do
  -- 1. Save caller-saved pool registers that hold live temporaries.
  extra <- getExtraDepth
  let saved  = envCSRegs env
      nSaved = length saved
      -- RSP is currently offset by (extra + 8*nSaved) from the frame base.
      -- The call instruction pushes 8 more; total must be 0 (mod 16).
      needPad = (extra + 8 * nSaved) `mod` 16 /= 0
  mapM_ (emit . Pushq . Reg) saved
  when needPad $ emit (Subq (Imm 8) (Reg RSP))

  -- 2. Evaluate each argument and place it in the ABI register.
  --    Evaluate left-to-right; each result lands in %rax then is moved.
  mapM_ (uncurry loadArg) (zip args argRegs)

  -- 3. For variadic functions (printf etc.) %eax must be 0.
  emit (Xorq (Reg RAX) (Reg RAX))

  -- 4. Call.
  emit (Callq f)

  -- 5. Remove alignment padding and restore caller-saved registers.
  when needPad $ emit (Addq (Imm 8) (Reg RSP))
  mapM_ (emit . Popq . Reg) (reverse saved)
  where
    loadArg e r = do
      compileExpr env e
      when (r /= scratchAcc) $ emit (Movq (Reg scratchAcc) (Reg r))
