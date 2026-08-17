module IR.Backend.WAT.WATPretty where

import Prelude hiding ((<>))

import IR.Backend.WAT.WATSyntax
import Utils.Pretty

-- Helpers

dollar :: WIdent -> Doc
dollar x = text ('$' : x)

ppValType :: WValType -> Doc
ppValType WI32 = text "i32"

ppBinOp :: WBinOp -> Doc
ppBinOp WAdd  = text "i32.add"
ppBinOp WSub  = text "i32.sub"
ppBinOp WMul  = text "i32.mul"
ppBinOp WDivS = text "i32.div_s"
ppBinOp WRemS = text "i32.rem_s"
ppBinOp WAnd  = text "i32.and"
ppBinOp WOr   = text "i32.or"
ppBinOp WXor  = text "i32.xor"
ppBinOp WShl  = text "i32.shl"
ppBinOp WShrS = text "i32.shr_s"
ppBinOp WShrU = text "i32.shr_u"
ppBinOp WEq   = text "i32.eq"
ppBinOp WNe   = text "i32.ne"
ppBinOp WLtS  = text "i32.lt_s"
ppBinOp WLeS  = text "i32.le_s"
ppBinOp WGtS  = text "i32.gt_s"
ppBinOp WGeS  = text "i32.ge_s"

-- Instructions

ppInstr :: WInstr -> Doc
ppInstr (WI32Const n)   = text "i32.const" <+> int n
ppInstr (WLocalGet  x)  = text "local.get"  <+> dollar x
ppInstr (WLocalSet  x)  = text "local.set"  <+> dollar x
ppInstr (WLocalTee  x)  = text "local.tee"  <+> dollar x
ppInstr (WGlobalGet g)  = text "global.get" <+> dollar g
ppInstr (WGlobalSet g)  = text "global.set" <+> dollar g
ppInstr (WI32BinOp op)  = ppBinOp op
ppInstr WI32Eqz         = text "i32.eqz"
ppInstr WI32Load        = text "i32.load"
ppInstr WI32Store       = text "i32.store"
ppInstr WDrop           = text "drop"
ppInstr WReturn         = text "return"
ppInstr WUnreachable    = text "unreachable"
ppInstr (WCall f)       = text "call" <+> dollar f
ppInstr (WBr   lbl)     = text "br"   <+> dollar lbl
ppInstr (WBrIf lbl)     = text "br_if" <+> dollar lbl
ppInstr (WBlock mlbl body) =
  let hdr = text "block" <> maybe empty (\l -> space <> dollar l) mlbl
  in parens (hdr $$ nest 2 (vcat (map ppInstr body)))
ppInstr (WLoop mlbl body) =
  let hdr = text "loop" <> maybe empty (\l -> space <> dollar l) mlbl
  in parens (hdr $$ nest 2 (vcat (map ppInstr body)))
ppInstr (WIf thenBranch mElse) =
  let thenDoc = parens (text "then" $$ nest 2 (vcat (map ppInstr thenBranch)))
      elseDoc = case mElse of
        Nothing -> empty
        Just eb -> parens (text "else" $$ nest 2 (vcat (map ppInstr eb)))
  in parens (text "if" $$ nest 2 (thenDoc $$ elseDoc))

-- Module-level declarations

ppFuncType :: WFuncType -> Doc
ppFuncType (WFuncType params mResult) =
  hsep $ map (\t -> parens (text "param"  <+> ppValType t)) params
       ++ maybe [] (\t -> [parens (text "result" <+> ppValType t)]) mResult

ppImport :: WImport -> Doc
ppImport (WImport modName field fname ftype) =
  parens $ hsep
    [ text "import"
    , doubleQuotes (text modName)
    , doubleQuotes (text field)
    , parens (text "func" <+> dollar fname <+> ppFuncType ftype)
    ]

ppGlobal :: WGlobal -> Doc
ppGlobal (WGlobal name typ mutable initVal) =
  parens $ hsep
    [ text "global"
    , dollar name
    , if mutable
        then parens (text "mut" <+> ppValType typ)
        else ppValType typ
    , parens (text "i32.const" <+> int initVal)
    ]

ppParam :: WParam -> Doc
ppParam (WParam x t) = parens (text "param" <+> dollar x <+> ppValType t)

ppLocal :: WLocal -> Doc
ppLocal (WLocal x t) = parens (text "local" <+> dollar x <+> ppValType t)

ppFunc :: WFunc -> Doc
ppFunc (WFunc name params mResult locals body) =
  parens (header $$ nest 2 (vcat (map ppLocal locals ++ map ppInstr body)))
  where
    header =
      text "func" <+> dollar name
      <> (if null params then empty else space <> hsep (map ppParam params))
      <> maybe empty (\t -> space <> parens (text "result" <+> ppValType t)) mResult

ppExport :: WExport -> Doc
ppExport (WExport name funcId) =
  parens $ hsep
    [ text "export"
    , doubleQuotes (text name)
    , parens (text "func" <+> dollar funcId)
    ]

ppMemory :: Maybe String -> Int -> Doc
ppMemory Nothing  pages = parens (text "memory" <+> int pages)
ppMemory (Just e) pages = parens (text "memory"
  <+> parens (text "export" <+> doubleQuotes (text e))
  <+> int pages)

-- Module

instance Pretty WModule where
  ppr (WModule imports mMem mMemExport globals funcs exports rawDecls) =
    parens (text "module" $$ nest 2 body)
    where
      sections =
           map ppImport imports
        ++ maybe [] (\p -> [ppMemory mMemExport p]) mMem
        ++ map ppGlobal globals
        ++ map ppFunc funcs
        ++ map ppExport exports
        ++ map text rawDecls
      body = vcat sections
