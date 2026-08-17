module TImp.Frontend.Pretty.TImpPretty () where

import Utils.Pretty hiding ((<>))
import TImp.Frontend.Syntax.TImpSyntax

-- Types

instance Pretty Ty where
  ppr TInt        = text "int"
  ppr TBool       = text "bool"
  ppr TString     = text "string"
  ppr (TRecord n) = text n

instance Pretty RetTy where
  ppr RTVoid    = text "void"
  ppr (RTTy ty) = ppr ty

-- Declarations

instance Pretty FieldDecl where
  ppr (FieldDecl f ty) = (text f <> colon) <+> (ppr ty <> semi)

instance Pretty RecordDecl where
  ppr (RecordDecl name fields) =
    text "record" <+> text name <+>
    braces (nest 2 (vcat (map ppr fields)))

instance Pretty Param where
  ppr (Param v ty) = (text v <> colon) <+> ppr ty

instance Pretty FuncDecl where
  ppr (FuncDecl name params rt body) =
    text "fn" <+> ((text name <> parens args) <> colon) <+> (ppr rt <+>
    braces (nest 2 (vcat (map ppr body))))
    where
      args = hcat (punctuate (comma <> space) (map ppr params))

instance Pretty Decl where
  ppr (DRecord r) = ppr r
  ppr (DFunc   f) = ppr f

-- Expressions

instance Pretty Exp where
  ppr (EInt n)      = int n
  ppr (EBool True)  = text "true"
  ppr (EBool False) = text "false"
  ppr (EString s)   = doubleQuotes (text s)
  ppr (EVar v)      = text v
  ppr (EField e f)  = ppr e <> (char '.' <> text f)
  ppr (ECall n es)  = text n <> parens (hcat (punctuate (comma <> space) (map ppr es)))
  ppr (ENew n fs)   =
    text "new" <+> text n <+>
    braces (hcat (punctuate (comma <> space) (map pprField fs)))
    where pprField (f, e) = text f <+> (equals <+> ppr e)
  ppr (e1 :+:  e2) = pprBin "+"  e1 e2
  ppr (e1 :-:  e2) = pprBin "-"  e1 e2
  ppr (e1 :*:  e2) = pprBin "*"  e1 e2
  ppr (e1 :/:  e2) = pprBin "/"  e1 e2
  ppr (e1 :<:  e2) = pprBin "<"  e1 e2
  ppr (e1 :>:  e2) = pprBin ">"  e1 e2
  ppr (e1 :=:  e2) = pprBin "==" e1 e2
  ppr (e1 :!=: e2) = pprBin "!=" e1 e2
  ppr (e1 :<=: e2) = pprBin "<=" e1 e2
  ppr (e1 :>=: e2) = pprBin ">=" e1 e2
  ppr (Not e)      = text "not" <+> pprAtom e
  ppr (e1 :&&: e2) = pprBin "&&" e1 e2
  ppr (e1 :||: e2) = pprBin "||" e1 e2

pprBin :: String -> Exp -> Exp -> Doc
pprBin op e1 e2 = pprAtom e1 <+> (text op <+> pprAtom e2)

pprAtom :: Exp -> Doc
pprAtom e@(EInt _)    = ppr e
pprAtom e@(EBool _)   = ppr e
pprAtom e@(EString _) = ppr e
pprAtom e@(EVar _)    = ppr e
pprAtom e@(EField _ _)= ppr e
pprAtom e@(ECall _ _) = ppr e
pprAtom e@(ENew _ _)  = ppr e
pprAtom e             = parens (ppr e)

-- Statements

instance Pretty Stmt where
  ppr (SDecl v ty e) =
    text "var" <+> text v <+> colon <+> ppr ty <+> (equals <+> (ppr e <> semi))
  ppr (SAssign v e) =
    text v <+> (text ":=" <+> (ppr e <> semi))
  ppr (SFieldAssign v f e) =
    (text v <> (char '.' <> text f)) <+> (text ":=" <+> (ppr e <> semi))
  ppr (SWhile e body) =
    text "while" <+> ppr e <+> braces (nest 2 (vcat (map ppr body)))
  ppr (SIf e th el) =
    text "if" <+> ppr e <+>
    braces (nest 2 (vcat (map ppr th))) <+>
    text "else" <+>
    braces (nest 2 (vcat (map ppr el)))
  ppr (SRead e v) =
    text "read" <+> ppr e <+> (text v <> semi)
  ppr (SPrint e) =
    text "print" <+> (ppr e <> semi)
  ppr (SReturn Nothing) =
    text "return" <> semi
  ppr (SReturn (Just e)) =
    text "return" <+> (ppr e <> semi)
  ppr (SCall n es) =
    (text n <> parens (hcat (punctuate (comma <> space) (map ppr es)))) <> semi

-- Program

instance Pretty TImp where
  ppr (TImp decls stmts) =
    vcat (map ppr decls) $+$ vcat (map ppr stmts)
