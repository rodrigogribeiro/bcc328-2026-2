module IR.Backend.X86.X86Syntax where

import Data.Set (Set)
import qualified Data.Set as Set

-- 64-bit general-purpose registers.
data Reg
  = RAX | RBX | RCX | RDX
  | RSI | RDI
  | R8  | R9  | R10 | R11
  | R12 | R13 | R14 | R15
  | RBP | RSP
  deriving (Eq, Ord, Show, Enum, Bounded)

-- Condition codes for conditional jumps (Jcc) and set-on-condition (Setcc).
data Cc = E | NE | L | LE | G | GE
  deriving (Eq, Ord, Show)

-- Instruction operand.
data Operand
  = Imm    Int        -- immediate:            $n
  | Reg    Reg        -- 64-bit register:      %rax
  | AL                -- 8-bit accumulator:    %al  (Setcc target only)
  | Mem    Int Reg    -- memory (offset+base): n(%reg)
  | RipRel String     -- RIP-relative label:   label(%rip)
  deriving (Eq, Show)

-- X86-64 instructions in AT&T syntax with explicit 64-bit size suffixes.
data Instr
  -- Data movement
  = Movq    Operand Operand   -- movq  src, dst
  | Movzbq  Operand Operand   -- movzbq src, dst   (zero-extend byte → quad)
  | Leaq    Operand Operand   -- leaq  src, dst    (load effective address)
  -- Arithmetic
  | Addq    Operand Operand   -- addq  src, dst    (dst += src)
  | Subq    Operand Operand   -- subq  src, dst    (dst -= src)
  | Imulq   Operand Operand   -- imulq src, dst    (dst *= src, signed)
  | Idivq   Operand           -- idivq src         (rdx:rax ÷ src → rax rem rdx)
  | Cqo                       -- cqo               (sign-extend rax → rdx:rax)
  | Negq    Operand           -- negq  dst         (dst = -dst, two's complement)
  -- Bitwise
  | Andq    Operand Operand   -- andq  src, dst
  | Orq     Operand Operand   -- orq   src, dst
  | Xorq    Operand Operand   -- xorq  src, dst
  -- Shifts
  | Salq    Operand Operand   -- salq  src, dst    (arithmetic left;  src = imm or %cl)
  | Shrq    Operand Operand   -- shrq  src, dst    (logical right shift)
  | Sarq    Operand Operand   -- sarq  src, dst    (arithmetic right shift)
  -- Comparison and flags
  | Cmpq    Operand Operand   -- cmpq  src, dst    (flags ← dst − src; result discarded)
  | Testq   Operand Operand   -- testq src, dst    (flags ← dst & src; result discarded)
  | Setcc   Cc Operand        -- setX  dst         (dst must be an 8-bit register, e.g. %al)
  -- Stack
  | Pushq   Operand           -- pushq src
  | Popq    Operand           -- popq  dst
  -- Control flow
  | Callq   String            -- callq target      (direct call by name)
  | Retq                      -- retq
  | Jmp     String            -- jmp   label       (unconditional)
  | Jcc     Cc String         -- jXX   label       (conditional)
  -- Labels and directives
  | GlobLabel String          -- name:             (function entry; requires .globl)
  | LocLabel  String          -- .L_name:          (local control-flow label)
  | Dir       String          -- verbatim directive (.text, .globl foo, .string "...", …)
  deriving (Eq, Show)

-- ── Register roles ─────────────────────────────────────────────────────────

-- Registers available to the graph-colouring allocator (K = 10).
--
-- Excluded from the pool:
--   RAX — expression accumulator and function return value
--   RDX — sign-extension target (cqo) and idivq remainder output
--   R10 — scratch for address in MOVE(MEM _, _)
--   R11 — scratch for the first operand held during BINOP evaluation
--   RBP — frame pointer
--   RSP — stack pointer
allocPool :: [Reg]
allocPool = [RBX, RCX, RSI, RDI, R8, R9, R12, R13, R14, R15]

-- Scratch registers reserved for the code generator.
scratchAcc   :: Reg; scratchAcc   = RAX  -- expression accumulator / return value
scratchDiv   :: Reg; scratchDiv   = RDX  -- idivq remainder; cqo sign-extension target
scratchMem   :: Reg; scratchMem   = R10  -- address scratch in MOVE(MEM _, _)
scratchBinop :: Reg; scratchBinop = R11  -- operand scratch during BINOP evaluation

-- Caller-saved registers: may be freely clobbered by any CALL.
-- Temporaries live across a CALL must be assigned callee-saved registers (or spilled).
callerSaved :: Set Reg
callerSaved = Set.fromList [RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11]

-- Callee-saved registers: the callee must preserve their values across a CALL.
calleeSaved :: Set Reg
calleeSaved = Set.fromList [RBX, R12, R13, R14, R15]

-- Argument-passing registers in the System V AMD64 ABI (in order).
argRegs :: [Reg]
argRegs = [RDI, RSI, RDX, RCX, R8, R9]

-- A complete X86-64 assembly program (flat sequence of instructions and directives).
newtype X86Program = X86Program { x86Instrs :: [Instr] }
  deriving (Eq, Show)
