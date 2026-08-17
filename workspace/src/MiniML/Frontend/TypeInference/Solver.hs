module MiniML.Frontend.TypeInference.Solver where

import Control.Monad
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Control.Monad.Except
import Control.Monad.State
import MiniML.Frontend.Syntax.Type
import MiniML.Frontend.Pretty.PrettyPrint
import MiniML.Frontend.TypeInference.Constraint
import MiniML.Frontend.TypeInference.SolverMonad

-- main constraint solver function

solver :: Constraint -> Either String (Env, Type)
solver c = runSolve (solve c)

-- constraint solver core logic

solve :: Constraint -> Solve ()
solve CTrue = pure ()
solve (t1 :=: t2)
  = do
      -- equalities must be unified
      s <- unify t1 t2
      info ["Unifying", pretty t1, "with", pretty t2, ":", pretty s]
solve (c1 :&: c2)
  = do
      -- solve each component of the conjunction
      solve c1
      solve c2
solve (CDef x t c)
    -- include a local definition into context
  = withLocalCtx x (Forall [] t) (solve c)
solve (CLet x t c1 c2)
  = do
      -- solve the constraint for the binding
      solve c1
      -- generate the type scheme
      scheme <- generalize t
      addInferedType x scheme
      -- type the let body using the infered scheme
      -- as an additional assumption
      withLocalCtx x scheme (solve c2)
solve (CInst x t)
  = do
      -- get type for x in the context
      -- and instantiate it.
      t' <- lookupVar x
      solve (t :=: t')
solve (CExists c)
  = do
      -- existentials create new type variables.
      v <- freshTyVar
      solve (c v)
solve (CInstScheme sigma inf)
  = do
      s      <- askSubst
      sigInf <- generalize (apply s inf)
      subsumes sigInf sigma

-- | Checks sigma1 <= sigma2: sigma1 is at least as general as sigma2.
-- Uses Skolem (rigid) variables for the quantifiers of sigma2 so the
-- unifier cannot accidentally instantiate them.
subsumes :: Scheme -> Scheme -> Solve ()
subsumes (Forall as t1) (Forall bs t2)
  = do
      -- Step 1: replace quantifiers of sigma2 with rigid (Skolem) variables
      rigidTs <- mapM (\_ -> freshTyVar) bs
      let rigidMap = Map.fromList (zip bs rigidTs)
          t2'      = apply rigidMap t2
          rigidNms = Set.fromList [v | TVar v <- rigidTs]
      -- Step 2: replace quantifiers of sigma1 with fresh flexible variables
      flexTs <- mapM (\_ -> freshTyVar) as
      let t1' = apply (Map.fromList (zip as flexTs)) t1
      -- Step 3: unify (local; does NOT extend the global substitution)
      s <- mgu t1' t2'
      -- Step 4: no rigid variable may have been instantiated
      let constrained = Map.keysSet s `Set.intersection` rigidNms
      unless (Set.null constrained) $
          throwError $ unlines
            [ "Type annotation error:"
            , "  inferred : " ++ pretty (Forall as t1)
            , "  annotated: " ++ pretty (Forall bs t2)
            , "The inferred type does not subsume the annotation."
            ]

generalize :: Type -> Solve Scheme
generalize t
  = do
      env <- askEnv
      s <- askSubst
      modify (\ c -> c{ctx = apply s (ctx c)})
      let
        t1 = apply s t
        vars = Set.toList $ Set.difference (ftv t1) (free env)
      pure (Forall vars t1)

free :: Ctx -> Set Name
free env
  = let
      schs = Map.elems env
      sets = map (\ (Forall vs t) ->
                      Set.difference (ftv t)
                                     (Set.fromList vs))
                 schs
    in foldr Set.union Set.empty sets

instantiate :: Scheme -> Solve Type
instantiate (Forall vars t)
  = do
      s <- Map.fromList <$> mapM (\v -> (,) v <$> freshTyVar) vars
      return $ apply s t

lookupVar :: Name -> Solve Type
lookupVar n
  = do
      env <- gets ctx
      case Map.lookup n env of
        Just ty -> instantiate ty
        Nothing -> throwError $ "Undefined variable:" ++ n


unify :: Type -> Type -> Solve Subst
unify t t' = do
  s <- askSubst
  s' <- mgu (apply s t) (apply s t')
  extSubst s'
  askSubst

mgu :: Type -> Type -> Solve Subst
mgu t1@(TVar v) t
  | t1 == t = pure Map.empty
  | occurs v t
    = throwError $ unlines [ "Occurs check error! Variable:"
                           , v
                           , "occurs in:"
                           , pretty t
                           ]
  | otherwise = pure (Map.singleton v t)
mgu t (TVar v) = mgu (TVar v) t
mgu (TFun l r) (TFun l' r')
  = do
      s1 <- mgu l l'
      s2 <- mgu (apply s1 r) (apply s1 r')
      return (s2 @@ s1)
mgu t1 t2
  | t1 == t2 = pure Map.empty
  | otherwise = throwError $ unlines ["Error! Cannot unify:"
                                     , show t1
                                     , " != "
                                     , show t2
                                     ]

occurs :: Name -> Type -> Bool
occurs n t = Set.member n (ftv t)



