module FJ.Backend.IR.FJCodegen (compileFJ) where

import Control.Monad (forM_)
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Data.List (findIndex, nub)
import Data.Maybe (fromJust, fromMaybe)
import qualified Data.Map.Strict as Map

import qualified IR.Frontend.Syntax.IRSyntax as IR
import FJ.Frontend.ClassTable.ClassTable
import FJ.Frontend.Syntax.FJSyntax

-- Object layout in memory
--
-- Every FJ object is represented as a contiguous block of words on the heap:
--
--   [ class_tag | field_0 | field_1 | ... | field_n ]
--
-- - Word 0  : integer class tag (unique ID per class, assigned at compile time)
-- - Word i+1: value of field i (0-indexed over all inherited + own fields)
-- - Word size: 8 bytes  →  field i lives at base + (i+1)*8
--
-- All values (object pointers, method return values) are represented as
-- integers in the IR.  The class tag enables dynamic dispatch and cast checks.

-- Code generation environment

data CgEnv = CgEnv
  { cgClassTable :: ClassTable
  , cgClassIds :: Map.Map ClassName Int
  , cgTypeEnv :: Map.Map VarName ClassName
  }

withTypeEnv :: Map.Map VarName ClassName -> CgEnv -> CgEnv
withTypeEnv te env = env { cgTypeEnv = te }

-- Code generation monad

data CgState = CgState
  { cgFuncs :: [IR.FuncDef]  -- accumulated function definitions
  , cgStmts :: [IR.Stmt]     -- current block being built
  , cgCounter :: Int         -- counter for fresh names
  }

type CgM a = StateT CgState (ExceptT String Identity) a

initState :: CgState
initState = CgState [] [] 0

runCgM :: CgM () -> Either String [IR.FuncDef]
runCgM m =
  runIdentity $ runExceptT $ fmap cgFuncs $ execStateT m initState

fresh :: CgM IR.Temp
fresh = do
  n <- gets cgCounter
  modify (\st -> st { cgCounter = n + 1 })
  return ("_t" ++ show n)

freshLabel :: CgM IR.Label
freshLabel = do
  n <- gets cgCounter
  modify (\st -> st { cgCounter = n + 1 })
  return ("_L" ++ show n)

emit :: IR.Stmt -> CgM ()
emit s = modify (\st -> st { cgStmts = cgStmts st ++ [s] })

emitFunc :: IR.FuncDef -> CgM ()
emitFunc fd = modify (\st -> st { cgFuncs = cgFuncs st ++ [fd] })

-- Run 'm' in an isolated statement block; returns the collected stmts
-- without disturbing the outer block.
inNewBlock :: CgM () -> CgM [IR.Stmt]
inNewBlock m = do
  saved <- gets cgStmts
  modify (\st -> st { cgStmts = [] })
  m
  stmts <- gets cgStmts
  modify (\st -> st { cgStmts = saved })
  return stmts

foldStmts :: [IR.Stmt] -> IR.Stmt
foldStmts [] = IR.EXP (IR.CONST 0)
foldStmts [s] = s
foldStmts (s:ss) = IR.SEQ s (foldStmts ss)

-- Static type reconstruction
--
-- FJ expressions do not carry type annotations, so we reconstruct types
-- on-the-fly using the class table and local type environment.

typeOfExpr :: ClassTable -> Map.Map VarName ClassName -> Expr -> Maybe ClassName
typeOfExpr _  env (EVar x) = Map.lookup x env
typeOfExpr _  _   (ENew c _) = Just c
typeOfExpr _  _   (ECast c _) = Just c
typeOfExpr ct env (EField e f)  = do
    c    <- typeOfExpr ct env e
    flds <- classFields ct c
    case filter (\(_, fn) -> fn == f) flds of
        ((FJType t, _) : _) -> Just t
        []                  -> Nothing
typeOfExpr ct env (EInvk e m _) = do
    c             <- typeOfExpr ct env e
    (_, FJType r) <- mtype ct m c
    Just r

-- Helpers for method dispatch

-- The class that directly defines method m for objects of class c
-- (walks up the hierarchy; returns Nothing if not found).
implementorOf :: ClassTable -> MethodName -> ClassName -> Maybe ClassName
implementorOf _  _ "Object" = Nothing
implementorOf ct m c =
    case Map.lookup c ct of
        Nothing -> Nothing
        Just cd ->
            if any (\md -> mdName md == m) (cdMethods cd)
                then Just c
                else implementorOf ct m (cdSuper cd)

-- All classes (in the table) that have method m via inheritance or definition.
classesWithMethod :: ClassTable -> MethodName -> [ClassName]
classesWithMethod ct m =
    [c | c <- Map.keys ct, mbody ct m c /= Nothing]

-- Top-level entry point

-- Compile a FJ program to an IR program (list of function definitions).
--
-- Generated functions:
--   C_new   – constructor for class C
--   C_m     – body of method m declared directly in class C
--   dispatch_m – dynamic-dispatch wrapper for method name m
--   main    – wraps progMain; prints the class tag of the result
compileFJ :: Program -> Either String IR.Program
compileFJ (Program classes mainExpr) = runCgM $ do
    let ct = buildCT classes
        -- Assign a unique integer tag to each class (Object = 0).
        classIds = Map.fromList $
                     ("Object", 0) :
                     zip (Map.keys ct) [1..]
        env0 = CgEnv ct classIds Map.empty
    -- 1. Compile constructors and methods for every class.
    mapM_ (compileClass env0) classes
    -- 2. Compile one dispatch function per distinct method name.
    let methodNames = nub [mdName md | cd <- classes, md <- cdMethods cd]
    mapM_ (compileDispatch env0) methodNames
    -- 3. Compile the main expression.
    compileMain env0 mainExpr

-- Class compilation

compileClass :: CgEnv -> ClassDecl -> CgM ()
compileClass env cd = do
    compileConstructor env cd
    mapM_ (compileMethod env (cdName cd)) (cdMethods cd)

-- Constructor: C_new(p0, p1, ..., pN)
--
-- Receives all field values (inherited first, then own), allocates an
-- object block, writes the class tag and each field, returns the pointer.
--
--   fn C_new(p0, p1, ..., pN):
--     _obj = alloc(N+1)         ; allocate tag slot + N field slots
--     MEM[_obj]         = tag_C ; class tag at offset 0
--     MEM[_obj + 8]     = p0    ; field 0 at offset 8
--     MEM[_obj + 16]    = p1    ; field 1 at offset 16
--     ...
--     return [_obj]

compileConstructor :: CgEnv -> ClassDecl -> CgM ()
compileConstructor env cd = do
    let c = cdName cd
        cid = fromJust (Map.lookup c (cgClassIds env))
    fs <- maybe (throwError $ "Undefined class:" ++ c) pure
                (classFields (cgClassTable env) c)
    let n = length fs
        params = ["_p" ++ show i | i <- [0 .. n - 1]]
    body <- inNewBlock $ do
        objT <- fresh
        -- Allocate n+1 words (tag + n fields)
        emit $ IR.MOVE (IR.TEMP objT)
                       (IR.CALL (IR.NAME "alloc") [IR.CONST (n + 1)])
        -- Write class tag
        emit $ IR.MOVE (IR.MEM (IR.TEMP objT)) (IR.CONST cid)
        -- Write each field
        forM_ (zip [0..] params) $ \(i, p) ->
            emit $ IR.MOVE
                     (IR.MEM (IR.BINOP IR.BAdd (IR.TEMP objT)
                                               (IR.CONST ((i + 1) * 8))))
                     (IR.TEMP p)
        emit $ IR.RETURN [IR.TEMP objT]
    emitFunc (IR.FuncDef (c ++ "_new") params (foldStmts body))

-- Method: C_m(_this, param0, param1, ...)
--
-- The receiver is passed as the first parameter (_this).  A local temp
-- "this" is initialised from _this so that EVar "this" in the body works.
--
--   fn C_m(_this, p0, ..., pk):
--     this = _this
--     ... body ...
--     return [result]

compileMethod :: CgEnv -> ClassName -> MethodDecl -> CgM ()
compileMethod env c md = do
    let m = mdName md
        pnames = map snd (mdParams md)
        ptypes = map (unFJType . fst) (mdParams md)
        typeEnv = Map.fromList $ ("this", c) : zip pnames ptypes
        env' = withTypeEnv typeEnv env
        irParams = "_this" : pnames
    body <- inNewBlock $ do
        -- Expose receiver under the name "this" for EVar lookups
        emit $ IR.MOVE (IR.TEMP "this") (IR.TEMP "_this")
        resT <- compileExpr env' (mdBody md)
        emit $ IR.RETURN [IR.TEMP resT]
    emitFunc (IR.FuncDef (c ++ "_m_" ++ m) irParams (foldStmts body))

-- Dynamic dispatch: dispatch_m(_recv, dp0, dp1, ...)
--
-- Reads the class tag from the receiver and chains comparisons to route
-- the call to the correct implementing function.
--
--   fn dispatch_m(_recv, dp0, ..., dpk):
--     _tag = MEM[_recv]
--     if _tag == tag_C1: return [C1_m(_recv, dp0, ..., dpk)]
--     if _tag == tag_C2: return [C2_m(_recv, dp0, ..., dpk)]
--     ...
--     return [0]        ; unreachable in well-typed programs

compileDispatch :: CgEnv -> MethodName -> CgM ()
compileDispatch env m = do
    let ct = cgClassTable env
        -- Collect classes that DEFINE m directly (to learn the arity)
        definers = [md | cd <- Map.elems ct, md <- cdMethods cd, mdName md == m]
    case definers of
        [] -> return ()
        (md : _) -> do
            let arity = length (mdParams md)
                dpParams = ["_dp" ++ show i | i <- [0 .. arity - 1]]
                irParams = "_recv" : dpParams
                -- All classes whose objects can receive method m
                receivers = classesWithMethod ct m
            body <- inNewBlock $ do
                tagT <- fresh
                emit $ IR.MOVE (IR.TEMP tagT) (IR.MEM (IR.TEMP "_recv"))
                buildDispatchChain env m tagT dpParams receivers
            emitFunc (IR.FuncDef ("dispatch_" ++ m) irParams (foldStmts body))

-- Emit the if-else chain for dispatch.
-- For each receiver class C, if the tag matches, tail-call C_m (or its
-- inherited implementation) and return the result.
buildDispatchChain
    :: CgEnv -> MethodName -> IR.Temp -> [IR.Temp] -> [ClassName] -> CgM ()
buildDispatchChain _   _ _    _      []     =
    -- Fallthrough: should not happen in a well-typed program.
    emit $ IR.RETURN [IR.CONST 0]
buildDispatchChain env m tagT dpParams (c : cs) = do
    let ct = cgClassTable env
        cid = fromJust (Map.lookup c (cgClassIds env))
        impl = fromJust (implementorOf ct m c)
        fn = impl ++ "_m_" ++ m
        callArgs = map IR.TEMP ("_recv" : dpParams)
    okL   <- freshLabel
    nextL <- freshLabel
    emit $ IR.CJUMP (IR.BINOP IR.BEq (IR.TEMP tagT) (IR.CONST cid)) okL nextL
    emit $ IR.LABEL okL
    emit $ IR.RETURN [IR.CALL (IR.NAME fn) callArgs]
    emit $ IR.LABEL nextL
    buildDispatchChain env m tagT dpParams cs

-- Main function
--
-- Evaluates progMain and prints the class tag of the resulting object.
-- (FJ values are objects; printing the tag is the observable output.)

compileMain :: CgEnv -> Expr -> CgM ()
compileMain env mainExpr = do
    body <- inNewBlock $ do
        resT <- compileExpr env mainExpr
        -- Print the class tag stored at offset 0 of the result object.
        emit $ IR.EXP (IR.CALL (IR.NAME "print") [IR.MEM (IR.TEMP resT)])
        emit $ IR.RETURN []
    emitFunc (IR.FuncDef "main" [] (foldStmts body))

-- Expression compilation
--
-- Each expression is compiled to a fresh temp that holds its value.
-- Statements needed as side effects are accumulated via 'emit'.

compileExpr :: CgEnv -> Expr -> CgM IR.Temp
compileExpr _ (EVar x) = return x
compileExpr env (ENew c args) = do
    argTs <- mapM (compileExpr env) args
    t <- fresh
    emit $ IR.MOVE (IR.TEMP t)
                   (IR.CALL (IR.NAME (c ++ "_new")) (map IR.TEMP argTs))
    return t
compileExpr env (EField e f) = do
    ptrT <- compileExpr env e
    let ct = cgClassTable env
        tenv = cgTypeEnv env
        ec = fromMaybe "Object" (typeOfExpr ct tenv e)
    fs <- maybe (throwError $ "Undefined name:" ++ ec) pure 
                (classFields ct ec)
    let idx = fromJust (findIndex (\(_, fn) -> fn == f) fs)
        offset = (idx + 1) * 8
    t <- fresh
    emit $ IR.MOVE (IR.TEMP t)
                   (IR.MEM (IR.BINOP IR.BAdd (IR.TEMP ptrT) (IR.CONST offset)))
    return t
compileExpr env (EInvk e m args) = do
    recvT <- compileExpr env e
    argTs <- mapM (compileExpr env) args
    t <- fresh
    emit $ IR.MOVE (IR.TEMP t)
                   (IR.CALL (IR.NAME ("dispatch_" ++ m))
                             (map IR.TEMP (recvT : argTs)))
    return t
compileExpr env (ECast d e) = do
    ptrT <- compileExpr env e
    let ct = cgClassTable env
        ids = cgClassIds env
        validIds = [i | (cn, i) <- Map.toList ids, isSubtype ct cn d]
    okL   <- freshLabel
    failL <- freshLabel
    tagT  <- fresh
    emit $ IR.MOVE (IR.TEMP tagT) (IR.MEM (IR.TEMP ptrT))
    emit $ IR.CJUMP (buildOrChain (IR.TEMP tagT) validIds) okL failL
    -- Failure branch: signal a ClassCastException via print(-1) then return 0.
    emit $ IR.LABEL failL
    emit $ IR.EXP (IR.CALL (IR.NAME "print") [IR.CONST (-1)])
    emit $ IR.RETURN [IR.CONST 0]
    emit $ IR.LABEL okL
    return ptrT

-- Build a disjunction of tag comparisons for cast checking.
--   buildOrChain tag [i1, i2, i3]  ≡  (tag==i1) | (tag==i2) | (tag==i3)

buildOrChain :: IR.Expr -> [Int] -> IR.Expr
buildOrChain _   [] = IR.CONST 0
buildOrChain tag [i] = IR.BINOP IR.BEq tag (IR.CONST i)
buildOrChain tag (i:is) =
    IR.BINOP IR.BOr
             (IR.BINOP IR.BEq tag (IR.CONST i))
             (buildOrChain tag is)
