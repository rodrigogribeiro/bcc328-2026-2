module MiniML.Frontend.Pretty.PrettyPrint where

import Prelude hiding ((<>))

import Control.Monad.State
import Data.List
import qualified Data.Map as Map
import Text.PrettyPrint.HughesPJ

import MiniML.Frontend.Syntax.Exp (Lit(..))
import MiniML.Frontend.Syntax.Type
import MiniML.Frontend.Syntax.TyExp
import MiniML.Frontend.TypeInference.Constraint


class Pretty a where
  ppr :: a -> Doc

pretty :: Pretty a => a -> String
pretty = render . ppr

instance Pretty Type where
  ppr TInt = text "int"
  ppr TBool = text "bool"
  ppr (TVar v) = text v
  ppr (TFun t1@(TFun _ _) t2)
    = parens (ppr t1) <+> text "->" <+> ppr t2
  ppr (TFun t1 t2)
    = ppr t1 <+> text "->" <+> ppr t2

instance Pretty Scheme where
  ppr (Forall [] t) = ppr t
  ppr (Forall vs t)
    =     text "forall"
      <+> hsep (map text vs')
      <>  text "."
      <+> ppr t'
    where
      allVars = [[x] | x <- ['a'..'z']] ++
                [x : show i | i <- [1 :: Integer ..], x <- ['a'.. 'z']]
      s = Map.fromList (zip vs (map TVar allVars))
      t' = apply s t
      vs' = zipWith (\ _ v -> v) vs allVars

instance Pretty Subst where
  ppr = text . br . concat . intersperse ", " . map go . Map.toList
    where
      go (v,t) = v ++ " +-> " ++ pretty t
      br s = "[" ++ s ++ "]"

-- pretty-printing annotated expressions

instance Pretty TyExp where
  ppr (TEVar n t)
    = parens (text n <+> text ":" <+> ppr t)
  ppr (TELit l t)
    = parens (pprLit l <+> text ":" <+> ppr t)
  ppr (TEApp e1 e2 t)
    = parens (ppr e1 <+> ppr e2 <+> text ":" <+> ppr t)
  ppr (TELam x t1 e t)
    = parens (  text "\\" <> text x <> text ":" <> ppr t1
             <> text "." <+> ppr e
             <+> text ":" <+> ppr t)
  ppr (TELet n e1 e2 t)
    = parens (  text "let" <+> text n <+> text "="
             <+> ppr e1 <+> text "in" <+> ppr e2
             <+> text ":" <+> ppr t)

pprLit :: Lit -> Doc
pprLit (LInt n)  = text (show n)
pprLit (LBool b) = text (show b)

-- converting constraints into strings

instance Pretty Constraint where
  ppr c = evalState (pp c) 0

type PP a = State Int a

fresh :: PP Type
fresh = do
  n <- get
  put (n + 1)
  pure (TVar $ "v" ++ show n)

pp :: Constraint -> PP Doc
pp CTrue = pure $ text "T"
pp (t1 :=: t2)
  = pure $ hsep [ppr t1, text "=", ppr t2]
pp (c1 :&: c2)
  = pure $ hsep [ppr c1, text "&&", ppr c2]
pp (CExists f)
  = do
      v <- fresh
      c <- pp (f v)
      pure $ hsep [ text "exists"
                  , ppr v
                  , text "."
                  , c
                  ]
pp (CDef n t c)
  = pure $ hsep [ text "def"
                , text n
                , text ":"
                , ppr t
                , text "in"
                , ppr c
                ]
pp (CLet n t c1 c2)
  = do
      d1 <- pp c1
      d2 <- pp c2
      pure $ hsep [ text "let"
                  , text n
                  , text ":"
                  , ppr t
                  , braces d1
                  , text "in"
                  , d2
                  ]
pp (CInst n t)
  = pure $ hcat [ text "inst("
                , text n
                , text ", "
                , ppr t
                , text ")"
                ]
pp (CInstScheme sch t)
  = pure $ text "schemeinst(" <> ppr sch <>
           text ", " <> ppr t <> text ")"
