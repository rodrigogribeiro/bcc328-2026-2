module MiniML.Frontend.TypeInference.Inference where

import Control.Monad.State

import MiniML.Frontend.Syntax.Exp
import MiniML.Frontend.Syntax.Type
import MiniML.Frontend.Syntax.TyExp
import MiniML.Frontend.TypeInference.Constraint
import MiniML.Frontend.TypeInference.ConstraintGen
import MiniML.Frontend.TypeInference.ElabGen
import MiniML.Frontend.TypeInference.Solver
import MiniML.Frontend.TypeInference.SolverMonad

-- Original inference (constraint generation only)

infer :: Exp -> Either String (Constraint, Env, Type)
infer e
  = let c = CExists (\ t -> generator e t)
    in case solver c of
         Left err -> Left err
         Right (env, t) -> Right (c, env, t)

-- Elaborating inference (produces an annotated syntax tree)

inferElab :: Exp -> Either String (Constraint, Env, TyExp, Type)
inferElab e
  = let rootVar        = TVar "a0"
        ((c, te), _)   = runState (elaborate e rootVar) 1
    in case runSolveOnly (solve c) of
         Left err  -> Left err
         Right env ->
           let s = subst env
           in Right (c, env, apply s te, apply s rootVar)
