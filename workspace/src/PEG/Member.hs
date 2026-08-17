{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

module PEG.Member
  ( Member (..)
  , KnownMember (..)
  ) where

import Data.Kind    (Type)
import Data.Proxy   (Proxy (..))
import GHC.TypeLits (ErrorMessage (..), Symbol, TypeError)

import PEG.Type
import PEG.TyLevel (SymEq)

data Member (s :: Symbol) (env :: Env) (ty :: Ty) (a :: Type) where
  Here  :: Member s ('(s, 'EnvEntry ty a) ': rest) ty a
  There :: Member s rest ty a -> Member s (e ': rest) ty a

class KnownMember (s :: Symbol) (env :: Env) (ty :: Ty) (a :: Type) where
  member :: Member s env ty a

instance TypeError ('Text "Undefined non-terminal: " ':<>: 'ShowType s
               ':$$: 'Text "The grammar has no rule for this name.")
      => KnownMember s '[] ty a where
  member = error "PEG.Member: unreachable"

instance KnownMember' (SymEq s t) s ('(t, e) ': rest) ty a
      => KnownMember s ('(t, e) ': rest) ty a where
  member = member' (Proxy :: Proxy (SymEq s t))

class KnownMember' (b :: Bool) (s :: Symbol) (env :: Env)
                   (ty :: Ty) (a :: Type) where
  member' :: Proxy b -> Member s env ty a

instance (s ~ t, e ~ 'EnvEntry ty a)
      => KnownMember' 'True s ('(t, e) ': rest) ty a where
  member' _ = Here

instance KnownMember s rest ty a
      => KnownMember' 'False s ('(t, e) ': rest) ty a where
  member' _ = There member
