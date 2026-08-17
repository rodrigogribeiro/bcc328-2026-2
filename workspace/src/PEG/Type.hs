{-# LANGUAGE DataKinds      #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeFamilies   #-}
{-# LANGUAGE TypeOperators  #-}

module PEG.Type
  ( Ty (..)
  , Nullable
  , First
  , EnvEntry (..)
  , Env
  , TyOf
  , ResOf
  ) where

import Data.Kind    (Type)
import GHC.TypeLits (Symbol)

data Ty = MkTy Bool [Symbol]

type family Nullable (t :: Ty) :: Bool where
  Nullable ('MkTy n _) = n

type family First (t :: Ty) :: [Symbol] where
  First ('MkTy _ f) = f

data EnvEntry = EnvEntry Ty Type

type Env = [(Symbol, EnvEntry)]

type family TyOf (e :: EnvEntry) :: Ty where
  TyOf ('EnvEntry t _) = t

type family ResOf (e :: EnvEntry) :: Type where
  ResOf ('EnvEntry _ a) = a
