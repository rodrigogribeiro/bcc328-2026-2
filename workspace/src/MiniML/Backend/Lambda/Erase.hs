module MiniML.Backend.Lambda.Erase (erase) where

import qualified Lambda.Frontend.Syntax.Term as L
import MiniML.Frontend.Syntax.Exp (Lit (..))
import MiniML.Frontend.Syntax.TyExp

-- | Erase type annotations from an elaborated MiniML term, producing an
-- untyped lambda-calculus term.  Let-bindings become beta-redexes:
--   let x = e1 in e2  →  (λx. e2) e1
erase :: TyExp -> L.Term
erase (TEVar x _)        = L.Var x
erase (TELit l _)        = L.Lit (eraseLit l)
erase (TEApp e1 e2 _)    = L.App (erase e1) (erase e2)
erase (TELam x _ e _)    = L.Lam x (erase e)
erase (TELet n e1 e2 _)  = L.App (L.Lam n (erase e2)) (erase e1)

eraseLit :: Lit -> L.Lit
eraseLit (LInt n)  = L.LInt n
eraseLit (LBool b) = L.LBool b
