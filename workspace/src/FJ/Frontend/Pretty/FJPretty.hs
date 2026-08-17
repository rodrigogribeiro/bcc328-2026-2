module FJ.Frontend.Pretty.FJPretty
  ( prettyExpr
  , prettyType
  , prettyProgram
  ) where

import Data.List (intercalate)
import FJ.Frontend.Syntax.FJSyntax

prettyType :: FJType -> String
prettyType (FJType c) = c

prettyExpr :: Expr -> String
prettyExpr (EVar x)       = x
prettyExpr (EField e f)   = prettyAtom e ++ "." ++ f
prettyExpr (EInvk e m as) = prettyAtom e ++ "." ++ m ++
                             "(" ++ intercalate ", " (map prettyExpr as) ++ ")"
prettyExpr (ENew c as)    = "new " ++ c ++
                             "(" ++ intercalate ", " (map prettyExpr as) ++ ")"
prettyExpr (ECast c e)    = "(" ++ c ++ ") " ++ prettyAtom e

-- Wrap in parens if the expression is not an atom.
prettyAtom :: Expr -> String
prettyAtom e@(EVar _)   = prettyExpr e
prettyAtom e@(ENew _ _) = prettyExpr e
prettyAtom e            = "(" ++ prettyExpr e ++ ")"

prettyProgram :: Program -> String
prettyProgram (Program cls main) =
    unlines (map prettyClass cls) ++ prettyExpr main

prettyClass :: ClassDecl -> String
prettyClass cd = unlines
  [ "class " ++ cdName cd ++ " extends " ++ cdSuper cd ++ " {"
  , unlines (map prettyField (cdFields cd))
  , prettyCtor (cdCtor cd)
  , unlines (map prettyMethod (cdMethods cd))
  , "}"
  ]

prettyField :: (FJType, FieldName) -> String
prettyField (t, f) = "    " ++ prettyType t ++ " " ++ f ++ ";"

prettyCtor :: Constructor -> String
prettyCtor c =
    "    " ++ ctorClass c ++ "(" ++ prettyParams (ctorParams c) ++ ") {\n" ++
    "        super(" ++ intercalate ", " (ctorSuper c) ++ ");\n" ++
    concatMap prettyInit (ctorInits c) ++
    "    }"
  where
    prettyInit (f, x) = "        this." ++ f ++ " = " ++ x ++ ";\n"

prettyMethod :: MethodDecl -> String
prettyMethod m =
    "    " ++ prettyType (mdRetType m) ++
    " " ++ mdName m ++
    "(" ++ prettyParams (mdParams m) ++ ") {\n" ++
    "        return " ++ prettyExpr (mdBody m) ++ ";\n" ++
    "    }"

prettyParams :: [(FJType, VarName)] -> String
prettyParams = intercalate ", " . map (\(t,x) -> prettyType t ++ " " ++ x)
