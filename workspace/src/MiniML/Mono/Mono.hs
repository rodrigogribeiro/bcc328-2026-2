module MiniML.Mono.Mono
  ( MonoResult(..)
  , SpecKey
  , monomorphize
  ) where

import Control.Monad (guard)
import Data.List (intercalate)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)

import MiniML.Frontend.Syntax.Exp (Exp)
import MiniML.Frontend.Syntax.Type
import MiniML.Frontend.Syntax.TyExp
import MiniML.Frontend.TypeInference.Inference (inferElab)
import MiniML.Frontend.TypeInference.SolverMonad (infered)

-- Types

-- Identifies a monomorphic specialization: function name + concrete
-- instantiation of its quantified type variables (in declaration order).
type SpecKey = (Name, [Type])

-- Maps each polymorphic let-binding to its scheme and elaborated body.
type PolyEnv = Map Name (Scheme, TyExp)

-- Maps each SpecKey to the corresponding monomorphic TyExp body.
type MonoEnv = Map SpecKey TyExp

-- Result of monomorphization.
data MonoResult = MonoResult
  { monoSpecKeys :: [SpecKey]
  , monoTree     :: TyExp
  }

matchScheme :: Scheme -> Type -> Maybe Subst
matchScheme (Forall vs schTy) useTy = go schTy useTy
  where
    go (TVar n) t
      | n `elem` vs = Just (Map.singleton n t)
      | TVar n == t = Just Map.empty
      | otherwise   = Nothing
    go TInt  TInt   = Just Map.empty
    go TBool TBool  = Just Map.empty
    go (TFun a1 b1) (TFun a2 b2) = do
      s1 <- go a1 a2
      s2 <- go b1 b2
      guard (and (Map.elems (Map.intersectionWith (==) s1 s2)))
      return (Map.union s1 s2)
    go _ _ = Nothing

isConcrete :: Type -> Bool
isConcrete TInt          = True
isConcrete TBool         = True
isConcrete (TFun t1 t2)  = isConcrete t1 && isConcrete t2
isConcrete (TVar _)      = False

buildPolyEnv :: Map Name Scheme -> TyExp -> PolyEnv
buildPolyEnv schemes = go
  where
    go (TELet n e1 e2 _) =
      let sub = go e1 `Map.union` go e2
      in case Map.lookup n schemes of
           Just sch@(Forall (_:_) _) -> Map.insert n (sch, e1) sub
           _                          -> sub
    go (TEApp e1 e2 _)  = go e1 `Map.union` go e2
    go (TELam _ _ e _)  = go e
    go _                = Map.empty

collectUseSites :: PolyEnv -> TyExp -> [(Name, Type)]
collectUseSites polyEnv = go
  where
    go (TEVar n t)       = [(n, t)]
    go (TELit _ _)       = []
    go (TEApp e1 e2 _)   = go e1 ++ go e2
    go (TELam _ _ e _)   = go e
    go (TELet n e1 e2 _)
      | n `Map.member` polyEnv = go e2          -- skip generic body
      | otherwise               = go e1 ++ go e2

toSpecKey :: PolyEnv -> (Name, Type) -> Maybe SpecKey
toSpecKey polyEnv (n, useTy) = do
  (sch@(Forall vs _), _) <- Map.lookup n polyEnv
  s <- matchScheme sch useTy
  let args = map (\v -> Map.findWithDefault (TVar v) v s) vs
  guard (all isConcrete args)
  return (n, args)

specialize :: PolyEnv -> SpecKey -> TyExp
specialize polyEnv (n, args) =
  case Map.lookup n polyEnv of
    Nothing                  -> error ("specialize: unknown name " ++ n)
    Just (Forall vs _, body) -> apply (Map.fromList (zip vs args)) body

collectSpecs :: PolyEnv -> TyExp -> MonoEnv
collectSpecs polyEnv root = go Map.empty [root]
  where
    go monoEnv []         = monoEnv
    go monoEnv (te:queue) =
      let useSites  = collectUseSites polyEnv te
          keys      = mapMaybe (toSpecKey polyEnv) useSites
          freshKeys = filter (`Map.notMember` monoEnv) keys
          newBodies = map (specialize polyEnv) freshKeys
          monoEnv'  = foldl (\m (k, b) -> Map.insert k b m)
                            monoEnv
                            (zip freshKeys newBodies)
      in go monoEnv' (queue ++ newBodies)

mangleName :: SpecKey -> Name
mangleName (n, args) = n ++ "$" ++ intercalate "_" (map mangleType args)

mangleType :: Type -> String
mangleType TInt          = "Int"
mangleType TBool         = "Bool"
mangleType (TFun t1 t2)  = "Fun" ++ mangleType t1 ++ mangleType t2
mangleType (TVar v)      = v

rewrite :: PolyEnv -> TyExp -> TyExp
rewrite polyEnv = go
  where
    go (TEVar n t)
      | n `Map.member` polyEnv =
          case toSpecKey polyEnv (n, t) of
            Just key -> TEVar (mangleName key) t
            Nothing  -> TEVar n t   -- generic context (shouldn't reach runtime)
      | otherwise = TEVar n t
    go (TELit l t)      = TELit l t
    go (TEApp e1 e2 t)  = TEApp (go e1) (go e2) t
    go (TELam x t1 e t) = TELam x t1 (go e) t
    go (TELet n e1 e2 t)
      | n `Map.member` polyEnv = go e2   -- remove polymorphic binding
      | otherwise               = TELet n (go e1) (go e2) t

assemble :: MonoEnv -> TyExp -> TyExp
assemble monoEnv mainExpr =
  foldr addBinding mainExpr (Map.toList monoEnv)
  where
    addBinding (key, body) acc =
      TELet (mangleName key) body acc (typeOf acc)

monomorphize :: Exp -> Either String MonoResult
monomorphize e = do
  (_, env, te, _) <- inferElab e
  let schemes  = Map.fromList (infered env)
      polyEnv  = buildPolyEnv schemes te
      rawMono  = collectSpecs polyEnv te
      monoEnv' = Map.map (rewrite polyEnv) rawMono
      mainExpr = rewrite polyEnv te
      tree     = assemble monoEnv' mainExpr
  return MonoResult
    { monoSpecKeys = Map.keys rawMono
    , monoTree     = tree
    }
