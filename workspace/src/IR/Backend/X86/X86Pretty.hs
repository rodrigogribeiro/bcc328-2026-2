module IR.Backend.X86.X86Pretty where

import Prelude hiding ((<>))

import IR.Backend.X86.X86Syntax
import Utils.Pretty

-- ── Registers ──────────────────────────────────────────────────────────────

ppReg :: Reg -> Doc
ppReg RAX = text "%rax"
ppReg RBX = text "%rbx"
ppReg RCX = text "%rcx"
ppReg RDX = text "%rdx"
ppReg RSI = text "%rsi"
ppReg RDI = text "%rdi"
ppReg R8  = text "%r8"
ppReg R9  = text "%r9"
ppReg R10 = text "%r10"
ppReg R11 = text "%r11"
ppReg R12 = text "%r12"
ppReg R13 = text "%r13"
ppReg R14 = text "%r14"
ppReg R15 = text "%r15"
ppReg RBP = text "%rbp"
ppReg RSP = text "%rsp"

-- ── Condition codes ─────────────────────────────────────────────────────────

-- Returns the AT&T mnemonic suffix for a condition code.
showCc :: Cc -> String
showCc E  = "e"
showCc NE = "ne"
showCc L  = "l"
showCc LE = "le"
showCc G  = "g"
showCc GE = "ge"

-- ── Operands ────────────────────────────────────────────────────────────────

ppOp :: Operand -> Doc
ppOp (Imm n)     = char '$' <> int n
ppOp (Reg r)     = ppReg r
ppOp AL          = text "%al"
ppOp (Mem 0 r)   = parens (ppReg r)           -- (%reg)
ppOp (Mem off r) = int off <> parens (ppReg r) -- n(%reg), n may be negative
ppOp (RipRel l)  = text l <> text "(%rip)"

-- ── Instructions ────────────────────────────────────────────────────────────

-- Emit a two-operand instruction in AT&T order: mnemonic src, dst
bin :: String -> Operand -> Operand -> Doc
bin mnem src dst = text mnem <+> ppOp src <> comma <+> ppOp dst

ppInstr :: Instr -> Doc
-- Data movement
ppInstr (Movq   src dst)  = bin "movq"   src dst
ppInstr (Movzbq src dst)  = bin "movzbq" src dst
ppInstr (Leaq   src dst)  = bin "leaq"   src dst
-- Arithmetic
ppInstr (Addq  src dst)   = bin "addq"  src dst
ppInstr (Subq  src dst)   = bin "subq"  src dst
ppInstr (Imulq src dst)   = bin "imulq" src dst
ppInstr (Idivq src)       = text "idivq" <+> ppOp src
ppInstr  Cqo              = text "cqo"
ppInstr (Negq  dst)       = text "negq"  <+> ppOp dst
-- Bitwise
ppInstr (Andq src dst)    = bin "andq" src dst
ppInstr (Orq  src dst)    = bin "orq"  src dst
ppInstr (Xorq src dst)    = bin "xorq" src dst
-- Shifts
ppInstr (Salq src dst)    = bin "salq" src dst
ppInstr (Shrq src dst)    = bin "shrq" src dst
ppInstr (Sarq src dst)    = bin "sarq" src dst
-- Comparison
ppInstr (Cmpq  src dst)   = bin "cmpq"  src dst
ppInstr (Testq src dst)   = bin "testq" src dst
ppInstr (Setcc cc dst)    = text ("set" ++ showCc cc) <+> ppOp dst
-- Stack
ppInstr (Pushq src)       = text "pushq" <+> ppOp src
ppInstr (Popq  dst)       = text "popq"  <+> ppOp dst
-- Control flow
ppInstr (Callq tgt)       = text "callq" <+> text tgt
ppInstr  Retq             = text "retq"
ppInstr (Jmp  lbl)        = text "jmp"                    <+> text (locLbl lbl)
ppInstr (Jcc cc lbl)      = text ("j" ++ showCc cc)       <+> text (locLbl lbl)
-- Labels
ppInstr (GlobLabel name)  = text name <> colon
ppInstr (LocLabel  name)  = text (locLbl name) <> colon
-- Directives
ppInstr (Dir d)           = text d

-- Local labels use the ".L_" prefix to avoid collisions with global symbols.
locLbl :: String -> String
locLbl l
  | take 3 l == ".L_" = l           -- already formatted
  | otherwise          = ".L_" ++ l

-- ── Pretty instances ─────────────────────────────────────────────────────────

-- Labels and directives are flush left; all other instructions are indented.
instance Pretty Instr where
  ppr instr = case instr of
    GlobLabel {} -> ppInstr instr
    LocLabel  {} -> ppInstr instr
    Dir       {} -> ppInstr instr
    _            -> nest 4 (ppInstr instr)

instance Pretty X86Program where
  ppr (X86Program instrs) = vcat (map ppr instrs)
