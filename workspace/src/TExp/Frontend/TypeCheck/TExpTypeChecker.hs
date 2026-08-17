module TExp.Frontend.TypeCheck.TExpTypeChecker where

import Control.Monad (unless)
import Control.Monad.Except
import Control.Monad.Identity

import TExp.Frontend.Syntax.TExpSyntax

typeCheck :: Term -> Either String Ty
typeCheck t = runIdentity (runExceptT (tcTerm t))

type TcM a = ExceptT String Identity a

tcTerm :: Term -> TcM Ty
tcTerm TTrue = pure TBool
tcTerm TFalse = pure TBool
tcTerm (TIf t1 t2 t3) = do
    ty1 <- tcTerm t1
    unless (ty1 == TBool) $
        throwError "Type error in if: condition must have type Bool"
    ty2 <- tcTerm t2
    ty3 <- tcTerm t3
    unless (ty2 == ty3) $
        throwError "Type error in if: both branches must have the same type"
    pure ty2
tcTerm TZero = pure TNat
tcTerm (TSucc t1) = do
    ty <- tcTerm t1
    unless (ty == TNat) $
        throwError "Type error in succ: argument must have type Nat"
    pure TNat
tcTerm (TPred t1) = do
    ty <- tcTerm t1
    unless (ty == TNat) $
        throwError "Type error in pred: argument must have type Nat"
    pure TNat
tcTerm (TIsZero t1) = do
    ty <- tcTerm t1
    unless (ty == TNat) $
        throwError "Type error in iszero: argument must have type Nat"
    pure TBool
