module MiniML.Frontend.Syntax.TyExp where

import qualified Data.Set as Set

import MiniML.Frontend.Syntax.Exp (Lit)
import MiniML.Frontend.Syntax.Type

-- Annotated expression: every node carries a type annotation.
-- Immediately after elaboration the annotations are type variables;
-- applying the final unifier (Subst) resolves them to concrete types.

data TyExp
  = TEVar  Name  Type               -- x : T
  | TELit  Lit   Type               -- l : T
  | TEApp  TyExp TyExp  Type        -- (e1 e2) : T
  | TELam  Name  Type   TyExp  Type -- (λx:T1. e) : T  (T = T1 → T2)
  | TELet  Name  TyExp  TyExp  Type -- let x = e1 in e2 : T
  deriving (Show)

-- | Return the (possibly not yet resolved) type at the root of a TyExp.
typeOf :: TyExp -> Type
typeOf (TEVar _ t)       = t
typeOf (TELit _ t)       = t
typeOf (TEApp _ _ t)     = t
typeOf (TELam _ _ _ t)   = t
typeOf (TELet _ _ _ t)   = t

-- | Apply a substitution to all type annotations in a TyExp.
-- This is the final step that turns placeholder type variables into
-- concrete types once the constraint solver has produced a unifier.
instance Apply TyExp where
  ftv (TEVar _ t)         = ftv t
  ftv (TELit _ t)         = ftv t
  ftv (TEApp e1 e2 t)     = ftv e1 `Set.union` ftv e2 `Set.union` ftv t
  ftv (TELam _ t1 e t)    = ftv t1 `Set.union` ftv e  `Set.union` ftv t
  ftv (TELet _ e1 e2 t)   = ftv e1 `Set.union` ftv e2 `Set.union` ftv t

  apply s (TEVar n t)         = TEVar n (apply s t)
  apply s (TELit l t)         = TELit l (apply s t)
  apply s (TEApp e1 e2 t)     = TEApp (apply s e1) (apply s e2) (apply s t)
  apply s (TELam x t1 e t)    = TELam x (apply s t1) (apply s e) (apply s t)
  apply s (TELet n e1 e2 t)   = TELet n (apply s e1) (apply s e2) (apply s t)
