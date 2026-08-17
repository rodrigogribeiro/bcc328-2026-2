module IR.Frontend.Pretty.IRPretty where

import Prelude hiding ((<>))
import IR.Frontend.Syntax.IRSyntax
import Utils.Pretty

-- Pretty instances

instance Pretty BinOp where
  ppr BAdd  = text "ADD"
  ppr BSub  = text "SUB"
  ppr BMul  = text "MUL"
  ppr BDiv  = text "DIV"
  ppr BMod  = text "MOD"
  ppr BAnd  = text "AND"
  ppr BOr   = text "OR"
  ppr BXor  = text "XOR"
  ppr BLsh  = text "LSHIFT"
  ppr BRsh  = text "RSHIFT"
  ppr BArsh = text "ARSHIFT"
  ppr BEq   = text "EQ"
  ppr BNe   = text "NEQ"
  ppr BLt   = text "LT"
  ppr BLe   = text "LEQ"
  ppr BGt   = text "GT"
  ppr BGe   = text "GEQ"

instance Pretty Expr where
  ppr (CONST n)         = text "CONST" <> parens (int n)
  ppr (TEMP t)          = text "TEMP"  <> parens (text t)
  ppr (NAME l)          = text "NAME"  <> parens (text l)
  ppr (BINOP op e1 e2)  =
    text "BINOP" <> parens (ppr op <> comma <+> ppr e1 <> comma <+> ppr e2)
  ppr (MEM e)           = text "MEM"   <> parens (ppr e)
  ppr (CALL ef [])      = text "CALL"  <> parens (ppr ef)
  ppr (CALL ef args)    =
    text "CALL" <> parens (ppr ef <> comma <+> hsep (punctuate comma (map ppr args)))
  ppr (ESEQ s e)        =
    text "ESEQ" <> parens (ppr s <> comma $+$ nest 2 (ppr e))

instance Pretty Stmt where
  ppr (MOVE dst src)    =
    text "MOVE" <> parens (ppr dst <> comma <+> ppr src)
  ppr (EXP e)           = text "EXP"  <> parens (ppr e)
  ppr (SEQ s1 s2)       =
    text "SEQ" <> parens (ppr s1 <> comma $+$ nest 2 (ppr s2))
  ppr (JUMP e)          = text "JUMP"  <> parens (ppr e)
  ppr (CJUMP e lt lf)   =
    text "CJUMP" <> parens (ppr e <> comma <+> text lt <> comma <+> text lf)
  ppr (LABEL l)         = text "LABEL" <> parens (text l)
  ppr (RETURN [])       = text "RETURN()"
  ppr (RETURN es)       =
    text "RETURN" <> parens (hsep (punctuate comma (map ppr es)))

instance Pretty FuncDef where
  ppr (FuncDef name params body) =
    text "func" <+> text name <>
    parens (hsep (punctuate comma (map text params))) <+>
    lbrace $+$
    nest 2 (ppr body) $+$
    rbrace

instance Pretty Program where
  ppr prog = vcat (map ppr prog)
