module FJ.Frontend.TypeChecker.FJTypeChecker
  ( typeCheckProgram
  , typeCheckExpr
  , typeCheckClasses
  ) where

import Control.Monad (forM_, unless, when)
import Control.Monad.Except
import qualified Data.Map.Strict as Map

import FJ.Frontend.Syntax.FJSyntax
import FJ.Frontend.ClassTable.ClassTable

-- Type-checking monad

type TcM a = Except String a

type Env = Map.Map VarName FJType

-- Expression typing  (Figure 19-1 of TAPL / FJ paper)

-- Infer the type of an expression.
tcExpr :: ClassTable -> Env -> Expr -> TcM FJType
tcExpr _ env (EVar x) =
  case Map.lookup x env of
    Just t  -> return t
    Nothing -> throwError $ "Unbound variable: " ++ x
tcExpr ct env (EField e f) = do
    FJType c <- tcExpr ct env e
    case classFields ct c of
      Nothing -> throwError $ "Unknown class: " ++ c
      Just fs ->
        case lookup f (map (\(t,fn) -> (fn, t)) fs) of
          Just t  -> return t
          Nothing -> throwError $
            "Field '" ++ f ++ "' not found in class " ++ c
tcExpr ct env (EInvk e m args) = do
    FJType c <- tcExpr ct env e
    (paramTypes, retType) <-
      maybe (throwError $ "Method '" ++ m ++ "' not found in " ++ c)
            return
            (mtype ct m c)
    argTypes <- mapM (tcExpr ct env) args
    when (length argTypes /= length paramTypes) $
      throwError $ "Wrong number of arguments for method '" ++ m ++ "'"
    forM_ (zip argTypes paramTypes) $ \(FJType got, FJType expected) ->
      unless (isSubtype ct got expected) $
        throwError $ "Argument type mismatch: '" ++ got ++
                     "' is not a subtype of '" ++ expected ++ "'"
    return retType
tcExpr ct env (ENew c args) = do
    fs <- maybe (throwError $ "Unknown class: " ++ c)
                return
                (classFields ct c)
    let expectedTypes = map fst fs
    argTypes <- mapM (tcExpr ct env) args
    when (length argTypes /= length expectedTypes) $
      throwError $ "Wrong number of arguments for 'new " ++ c ++ "'"
    forM_ (zip argTypes expectedTypes) $ \(FJType got, FJType expected) ->
      unless (isSubtype ct got expected) $
        throwError $ "Constructor argument type mismatch in 'new " ++ c ++
                     "': '" ++ got ++ "' is not a subtype of '" ++ expected ++ "'"
    return (FJType c)
tcExpr ct env (ECast c e) = do
    FJType _ <- tcExpr ct env e
    return (FJType c)

-- Method well-formedness  (T-Method)

tcMethod :: ClassTable -> ClassName -> MethodDecl -> TcM ()
tcMethod ct c md = do
    let env = Map.fromList $
                ("this", FJType c) :
                map (\(t, x) -> (x, t)) (mdParams md)
    bodyType <- tcExpr ct env (mdBody md)
    unless (isSubtype ct (unFJType bodyType) (unFJType (mdRetType md))) $
      throwError $ "Return type mismatch in method '" ++ mdName md ++
                   "' of class '" ++ c ++ "'"
    case Map.lookup c ct >>= \cd -> mtype ct (mdName md) (cdSuper cd) of
      Nothing -> return ()
      Just (superParams, superRet) -> do
        let curParams = map fst (mdParams md)
        unless (curParams == superParams && mdRetType md == superRet) $
          throwError $ "Method '" ++ mdName md ++ "' in '" ++ c ++
                       "' overrides with a different signature"

-- Constructor well-formedness  (T-Class helper)

tcConstructor :: ClassTable -> ClassDecl -> TcM ()
tcConstructor ct cd = do
    allFs <- maybe (throwError $ "Unknown class: " ++ cdName cd)
                   return
                   (classFields ct (cdName cd))
    let ctor          = cdCtor cd
        paramTypes    = map (unFJType . fst) (ctorParams ctor)
        allFieldTypes = map (unFJType . fst) allFs
    unless (paramTypes == allFieldTypes) $
      throwError $ "Constructor parameters do not match all fields in '" ++
                   cdName cd ++ "'"
    superFs <- maybe (throwError "Cannot look up superclass fields")
                     return
                     (classFields ct (cdSuper cd))
    unless (length (ctorSuper ctor) == length superFs) $
      throwError $ "Wrong number of super() arguments in constructor of '" ++
                   cdName cd ++ "'"
    let ownFieldNames = map snd (cdFields cd)
        initNames     = map fst (ctorInits ctor)
    unless (initNames == ownFieldNames) $
      throwError $ "Constructor field initializations do not match own fields in '" ++
                   cdName cd ++ "'"

-- Class well-formedness  (T-Class)

tcClass :: ClassTable -> ClassDecl -> TcM ()
tcClass ct cd = do
    unless (cdSuper cd == "Object" || Map.member (cdSuper cd) ct) $
      throwError $ "Superclass '" ++ cdSuper cd ++
                   "' not found for class '" ++ cdName cd ++ "'"
    tcConstructor ct cd
    mapM_ (tcMethod ct (cdName cd)) (cdMethods cd)

-- Program entry point

typeCheckProgram :: Program -> Either String FJType
typeCheckProgram (Program cls main) =
  runExcept $ do
    let ct = buildCT cls
    mapM_ (tcClass ct) cls
    tcExpr ct Map.empty main

typeCheckExpr :: ClassTable -> Expr -> Either String FJType
typeCheckExpr ct e = runExcept (tcExpr ct Map.empty e)

typeCheckClasses :: ClassTable -> [ClassDecl] -> Either String ()
typeCheckClasses ct cls = runExcept (mapM_ (tcClass ct) cls)
