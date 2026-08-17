{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE KindSignatures       #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module PEG.Grammar
  ( Rules (..)
  , Grammar (..)
  , Acyclic
  ) where

import Data.Kind    (Constraint, Type)
import GHC.TypeLits (ErrorMessage (..), Symbol, TypeError)

import PEG.Syntax  (Name, PExp)
import PEG.TyLevel (Elem)
import PEG.Type

data Rules (env :: Env) (defs :: Env) where
  RNil  :: Rules env '[]
  RCons :: Name s
        -> PExp env ty a
        -> Rules env rest
        -> Rules env ('(s, 'EnvEntry ty a) ': rest)

type family Acyclic (env :: Env) :: Constraint where
  Acyclic '[]                             = ()
  Acyclic ('(s, 'EnvEntry ty _) ': rest) =
    (NotLeftRec s (Elem s (First ty)) ty, Acyclic rest)

type family NotLeftRec (s :: Symbol) (b :: Bool) (ty :: Ty) :: Constraint where
  NotLeftRec _ 'False _  = ()
  NotLeftRec s 'True  ty =
    TypeError ('Text "Left-recursive non-terminal: " ':<>: 'ShowType s
         ':$$: 'Text "Its head set already contains itself: "
               ':<>: 'ShowType (First ty)
         ':$$: 'Text "Violates the acyclicity condition i `notElem` Gamma(i).F.")

data Grammar (env :: Env) (startTy :: Ty) (startA :: Type) where
  Grammar :: Acyclic env
          => Rules env env
          -> PExp env startTy startA
          -> Grammar env startTy startA
