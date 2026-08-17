module FJ.Frontend.ClassTable.ClassTable where

import qualified Data.Map.Strict as Map
import FJ.Frontend.Syntax.FJSyntax

-- Class table maps class names to their declarations.
type ClassTable = Map.Map ClassName ClassDecl

-- The distinguished root class.
objectClass :: ClassName
objectClass = "Object"

-- Build a class table from a list of declarations.
buildCT :: [ClassDecl] -> ClassTable
buildCT = Map.fromList . map (\cd -> (cdName cd, cd))

-- All fields of C in declaration order (inherited fields first).
classFields :: ClassTable -> ClassName -> Maybe [(FJType, FieldName)]
classFields _  "Object" = Just []
classFields ct c = do
    cd <- Map.lookup c ct
    parentFs <- classFields ct (cdSuper cd)
    return (parentFs ++ cdFields cd)

-- Type signature of method m in C (searches up the hierarchy).
mtype :: ClassTable -> MethodName -> ClassName -> Maybe ([FJType], FJType)
mtype _  _ "Object" = Nothing
mtype ct m c = do
    cd <- Map.lookup c ct
    case filter (\md -> mdName md == m) (cdMethods cd) of
      (md:_) -> Just (map fst (mdParams md), mdRetType md)
      []     -> mtype ct m (cdSuper cd)

-- Parameters and body of method m in C (searches up the hierarchy).
mbody :: ClassTable -> MethodName -> ClassName -> Maybe ([VarName], Expr)
mbody _  _ "Object" = Nothing
mbody ct m c = do
    cd <- Map.lookup c ct
    case filter (\md -> mdName md == m) (cdMethods cd) of
      (md:_) -> Just (map snd (mdParams md), mdBody md)
      []     -> mbody ct m (cdSuper cd)

-- Subtyping: C <: D  (reflexive-transitive closure of extends).
isSubtype :: ClassTable -> ClassName -> ClassName -> Bool
isSubtype _  c d | c == d     = True
isSubtype _  _ "Object"       = True
isSubtype ct c d =
    case Map.lookup c ct of
      Nothing -> False
      Just cd -> isSubtype ct (cdSuper cd) d
