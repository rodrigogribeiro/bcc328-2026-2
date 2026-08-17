module TWhile.Backend.WASM.Pretty where

import Prelude hiding ((<>))

import TWhile.Backend.WASM.Syntax
import Utils.Pretty hiding (isEmpty)

listCase :: b -> ([a] -> b) -> [a] -> b
listCase v _ [] = v
listCase _ f xs = f xs

prettyFuncSig :: [WasmType] -> [WasmType] -> Doc
prettyFuncSig params results = paramDoc <> resultDoc
  where
    paramDoc  = listCase empty (\ps -> space <> parens (text "param"  <+> hsep (map ppr ps))) params
    resultDoc = listCase empty (\rs -> space <> parens (text "result" <+> hsep (map ppr rs))) results

instance Pretty WasmType where
  ppr I32 = text "i32"

instance Pretty WasmInstr where
  -- numeric
  ppr (I32Const n) = text "i32.const" <+> int n
  ppr (LocalGet i) = text "local.get" <+> int i
  ppr (LocalSet i) = text "local.set" <+> int i
  ppr I32Add = text "i32.add"
  ppr I32Sub = text "i32.sub"
  ppr I32Mul = text "i32.mul"
  ppr I32DivS = text "i32.div_s"
  ppr I32LtS = text "i32.lt_s"
  ppr I32Eq = text "i32.eq"
  ppr I32Eqz = text "i32.eqz"
  ppr (Call f) = text "call" <+> text f
  ppr Drop = text "drop"
  ppr (BrIf n) = text "br_if" <+> int n
  ppr (Br    n) = text "br" <+> int n
  ppr (If mResult thenB elseB) =
    let header = case mResult of
          Nothing -> text "if"
          Just t  -> text "if" <+> parens (text "result" <+> ppr t)
    in header $$
       nest 2 (vcat (map ppr thenB)) $$
       (if null elseB then empty
        else text "else" $$ nest 2 (vcat (map ppr elseB))) $$
       text "end"
  ppr (Block instrs) =
    text "block" $$
    nest 2 (vcat (map ppr instrs)) $$
    text "end"
  ppr (Loop instrs) =
    text "loop" $$
    nest 2 (vcat (map ppr instrs)) $$
    text "end"

instance Pretty WasmImport where
  ppr (WasmImport mod' name (ImportFunc funcName' params results)) =
    parens $ hsep
      [ text "import"
      , doubleQuotes (text mod')
      , doubleQuotes (text name)
      , parens (text "func" <+> text funcName' <> prettyFuncSig params results)
      ]

instance Pretty WasmExport where
  ppr (WasmExport name (ExportFunc funcName')) =
    parens $ hsep
      [ text "export"
      , doubleQuotes (text name)
      , parens (text "func" <+> text funcName')
      ]

instance Pretty WasmFunc where
  ppr (WasmFunc name params results locals body) =
    parens (header $$ localsDoc $$ bodyDoc)
    where
      header    = text "func" <+> text name <> prettyFuncSig params results
      localsDoc = listCase empty
                    (\ls -> nest 2 (parens (text "local" <+> hsep (map ppr ls))))
                    locals
      bodyDoc   = listCase empty
                    (\instrs -> nest 2 (vcat (map ppr instrs)))
                    body

instance Pretty WasmModule where
  ppr (WasmModule imports exports funcs) =
    parens (text "module" $$ nest 2 body)
    where
      isEmpty = null . render
      sections = filter (not . isEmpty)
                   [ listCase empty (vcat . map ppr) imports
                   , listCase empty (vcat . map ppr) exports
                   , listCase empty (vcat . map ppr) funcs
                   ]
      body = listCase empty (vcat) sections
