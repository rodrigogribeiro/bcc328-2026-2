module MiniML.Frontend.TypeInference.ElabGen where

import Control.Monad.State

import MiniML.Frontend.Syntax.Exp
import MiniML.Frontend.Syntax.Type
import MiniML.Frontend.Syntax.TyExp
import MiniML.Frontend.TypeInference.Constraint

-- Elaboration monad

type ElabM = State Int

freshVar :: ElabM Type
freshVar = do
    n <- get
    modify (+1)
    return (TVar ("a" ++ show n))

-- Simultaneous constraint generation and elaboration

elaborate :: Exp -> Type -> ElabM (Constraint, TyExp)
elaborate (Var n) ty
  = return (CInst n ty, TEVar n ty)
elaborate (Lit l) ty
  = return (ty :=: typeOfLit l, TELit l ty)
elaborate (App e1 e2) ty
  = do
      ty' <- freshVar
      (c1, te1) <- elaborate e1 (TFun ty' ty)
      (c2, te2) <- elaborate e2 ty'
      return (c1 :&: c2, TEApp te1 te2 ty)
elaborate (Lam x mt body) ty
  = do
      t1 <- freshVar
      t2 <- freshVar
      (cBody, teBody) <- elaborate body t2
      let cBase = CDef x t1 cBody :&: (ty :=: TFun t1 t2)
          cAnn  = maybe cBase (\t -> cBase :&: (t :=: t1)) mt
      return (cAnn, TELam x t1 teBody ty)
elaborate (Let n mAnn e body) ty
  = do
      t1 <- freshVar
      (c1, te1)       <- elaborate e t1
      let c1Ann = maybe c1 (\sch -> c1 :&: CInstScheme sch t1) mAnn
      (cBody, teBody) <- elaborate body ty
      return (CLet n t1 c1Ann cBody, TELet n te1 teBody ty)

typeOfLit :: Lit -> Type
typeOfLit (LInt _)  = TInt
typeOfLit (LBool _) = TBool
