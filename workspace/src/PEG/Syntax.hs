{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleInstances   #-}

module PEG.Syntax
  ( Name (..)
  , PExp (..)
  , nt
  , pureP
  , fmapP
  , indent
  , position
  , align
  , (<$>.)
  , (<*>.)
  , (.>>.)
  , (.||.)
  , opt
  , plus
  , oneOf
  , stringNE
  , SeqTy
  , ChoiceTy
  , NTTy
  ) where

import Data.Kind    (Type)
import GHC.TypeLits (Symbol, KnownSymbol)

import PEG.Indent (Rel)
import PEG.Type
import PEG.TyLevel
import PEG.Member

data Name (s :: Symbol) = Name

type SeqTy t1 t2 =
  'MkTy (And (Nullable t1) (Nullable t2))
        (Union (First t1) (If (Nullable t1) (First t2) '[]))

type ChoiceTy t1 t2 =
  'MkTy (Or  (Nullable t1) (Nullable t2))
        (Union (First t1) (First t2))

type NTTy s env =
  'MkTy (Nullable (TyOf (Lookup s env)))
        (ConsIfAbsent s (First (TyOf (Lookup s env))))

data PExp (env :: Env) (ty :: Ty) (a :: Type) where
  Pure     :: a -> PExp env ('MkTy 'True '[]) a
  Term     :: Char -> PExp env ('MkTy 'False '[]) Char
  AnyChar  :: PExp env ('MkTy 'False '[]) Char
  NT       :: ( KnownSymbol s
              , KnownMember s env (TyOf (Lookup s env)) (ResOf (Lookup s env))
              )
           => Name s
           -> PExp env (NTTy s env) (ResOf (Lookup s env))
  Seq      :: PExp env t1 (a -> b)
           -> PExp env t2 a
           -> PExp env (SeqTy t1 t2) b
  Choice   :: PExp env t1 a
           -> PExp env t2 a
           -> PExp env (ChoiceTy t1 t2) a
  Star     :: PExp env ('MkTy 'False f) a
           -> PExp env ('MkTy 'True  f) [a]
  Not      :: PExp env ('MkTy n f) a
           -> PExp env ('MkTy 'True f) ()
  Map      :: (a -> b)
           -> PExp env ty a
           -> PExp env ty b
  Indent   :: Rel n
           -> PExp env ty a
           -> PExp env ty a
  Position :: Rel n
           -> PExp env ty a
           -> PExp env ty a
  Align    :: PExp env ty a
           -> PExp env ty a

instance Functor (PExp env ty) where
  fmap = Map

nt :: forall s env.
      ( KnownSymbol s
      , KnownMember s env (TyOf (Lookup s env)) (ResOf (Lookup s env))
      )
   => PExp env (NTTy s env) (ResOf (Lookup s env))
nt = NT (Name :: Name s)

pureP :: a -> PExp env ('MkTy 'True '[]) a
pureP = Pure

fmapP :: (a -> b) -> PExp env ty a -> PExp env ty b
fmapP = Map

indent :: Rel n -> PExp env ty a -> PExp env ty a
indent = Indent

position :: Rel n -> PExp env ty a -> PExp env ty a
position = Position

align :: PExp env ty a -> PExp env ty a
align = Align

(<$>.) :: (a -> b) -> PExp env ty a -> PExp env ty b
(<$>.) = Map
infixl 4 <$>.

(<*>.) :: PExp env t1 (a -> b)
       -> PExp env t2 a
       -> PExp env (SeqTy t1 t2) b
(<*>.) = Seq
infixl 4 <*>.

(.>>.) :: PExp env t1 a
       -> PExp env t2 b
       -> PExp env (SeqTy t1 t2) b
e1 .>>. e2 = Map (\_ b -> b) e1 <*>. e2
infixl 6 .>>.

(.||.) :: PExp env t1 a -> PExp env t2 a -> PExp env (ChoiceTy t1 t2) a
(.||.) = Choice
infixl 5 .||.

opt :: PExp env t a
    -> PExp env (ChoiceTy t ('MkTy 'True '[])) (Maybe a)
opt e = (Just <$>. e) .||. pureP Nothing

plus :: PExp env ('MkTy 'False f) a
     -> PExp env (SeqTy ('MkTy 'False f) ('MkTy 'True f)) [a]
plus e = (:) <$>. e <*>. Star e

oneOf :: [Char] -> PExp env ('MkTy 'False '[]) Char
oneOf []     = error "PEG.Syntax.oneOf: empty character class"
oneOf [c]    = Term c
oneOf (c:cs) = Term c .||. oneOf cs

stringNE :: String -> PExp env ('MkTy 'False '[]) String
stringNE []     = error "PEG.Syntax.stringNE: empty string"
stringNE [c]    = (\x -> [x]) <$>. Term c
stringNE (c:cs) = (:) <$>. Term c <*>. stringNE cs
