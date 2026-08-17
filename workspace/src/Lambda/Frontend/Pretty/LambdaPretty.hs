module Lambda.Frontend.Pretty.LambdaPretty (prettyTerm) where

import Lambda.Frontend.Syntax.Term

prettyTerm :: Term -> String
prettyTerm t = ppTerm t

ppTerm :: Term -> String
ppTerm (Var x)     = x
ppTerm (Lit l)     = ppLit l
ppTerm (Lam x t)   = "λ" ++ x ++ ppLamTail t
ppTerm (App t1 t2) = ppFun t1 ++ " " ++ ppArg t2

ppLit :: Lit -> String
ppLit (LInt n)  = show n
ppLit (LBool b) = if b then "true" else "false"

-- Merge consecutive binders: λx. λy. t  →  λx y. t
ppLamTail :: Term -> String
ppLamTail (Lam x t) = " " ++ x ++ ppLamTail t
ppLamTail t         = ". " ++ ppTerm t

-- Left side of application: wrap only lambdas.
ppFun :: Term -> String
ppFun t@(Lam _ _) = "(" ++ ppTerm t ++ ")"
ppFun t           = ppTerm t

-- Right side of application: literals and variables are atomic.
ppArg :: Term -> String
ppArg (Var x)             = x
ppArg (Lit (LInt n))
  | n < 0                 = "(" ++ show n ++ ")"
  | otherwise             = show n
ppArg (Lit (LBool b))     = if b then "true" else "false"
ppArg t                   = "(" ++ ppTerm t ++ ")"
