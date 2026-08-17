module Lambda.Backend.TImp.LambdaToTImp
  ( lambdaToTImp
  ) where

import qualified Data.Set as Set
import Control.Monad.State

import Lambda.Frontend.Syntax.Term (Term (..), Lit (..))
import TImp.Frontend.Syntax.TImpSyntax

-- Reserved tags for literal boxing

litIntTag :: Int
litIntTag = -2

litBoolTag :: Int
litBoolTag = -3

-- Annotated terms: each Lam carries a unique ID and its free-variable list.

type LamId = Int

data Ann
  = AVar Name
  | ALam LamId Name [Name] Ann
  | AApp Ann Ann
  | ALit Lit

-- Free variables of an annotated term (already computed for ALam nodes).
freeVarsAnn :: Ann -> Set.Set Name
freeVarsAnn (AVar x)         = Set.singleton x
freeVarsAnn (AApp f a)       = freeVarsAnn f `Set.union` freeVarsAnn a
freeVarsAnn (ALam _ _ fvs _) = Set.fromList fvs
freeVarsAnn (ALit _)         = Set.empty

-- Annotation pass: number each lambda (inner-first / post-order) and
-- record the list of free variables that the closure must capture.

type AnnM = State Int

freshId :: AnnM Int
freshId = do { n <- get; put (n + 1); return n }

annotate :: Term -> AnnM Ann
annotate (Var x)   = return (AVar x)
annotate (Lit l)   = return (ALit l)
annotate (App f a) = AApp <$> annotate f <*> annotate a
annotate (Lam x t) = do
  body <- annotate t
  k    <- freshId
  let fvs = Set.toList (Set.delete x (freeVarsAnn body))
  return (ALam k x fvs body)

-- Collect all lambdas from the annotated term.

collectLambdas :: Ann -> [(LamId, Name, [Name], Ann)]
collectLambdas (AVar _)            = []
collectLambdas (ALit _)            = []
collectLambdas (AApp f a)          = collectLambdas f ++ collectLambdas a
collectLambdas (ALam k x fvs body) = collectLambdas body ++ [(k, x, fvs, body)]

-- Compile an annotated term to a TImp expression.
--
--   AVar x          → look up x in substitution (or EVar x if free)
--   ALit (LInt n)   → ENew "Closure" [("tag", litIntTag),  ("val", n)]
--   ALit (LBool b)  → ENew "Closure" [("tag", litBoolTag), ("val", 0|1)]
--   AApp f a        → ECall "apply" [compile f, compile a]
--   ALam k _ fvs _  → ENew "Closure" [("tag",k), ("f0",fvs[0]), ...]

type Subst = [(Name, Exp)]

compileExprS :: Subst -> Ann -> Exp
compileExprS s (AVar x) =
  case lookup x s of
    Just e  -> e
    Nothing -> EVar x
compileExprS _ (ALit (LInt n)) =
  ENew "Closure" [("tag", EInt litIntTag), ("val", EInt n)]
compileExprS _ (ALit (LBool b)) =
  ENew "Closure" [("tag", EInt litBoolTag), ("val", EInt (if b then 1 else 0))]
compileExprS s (AApp f a) =
  ECall "apply" [compileExprS s f, compileExprS s a]
compileExprS s (ALam k _ fvs _) =
  ENew "Closure" $
    ("tag", EInt k) :
    [ ("f" ++ show i, compileExprS s (AVar v))
    | (i, v) <- zip [0::Int ..] fvs
    ]

-- Generate the Closure record declaration.
--
--   record Closure { tag: int; val: int; f0: Closure; f1: Closure; ... }
--
-- The 'val' field stores the raw value for literal-boxed closures.
-- The fi fields capture free variables for lambda closures.
-- Partial initialization is used in all cases.

genClosureRecord :: Int -> RecordDecl
genClosureRecord maxFVs =
  RecordDecl "Closure" $
    FieldDecl "tag" TInt :
    FieldDecl "val" TInt :
    [ FieldDecl ("f" ++ show i) (TRecord "Closure") | i <- [0 .. maxFVs - 1] ]

-- Generate one lifted function for lambda k.

genLiftedFunc :: (LamId, Name, [Name], Ann) -> FuncDecl
genLiftedFunc (k, x, fvs, body) =
  FuncDecl
    ("lam_" ++ show k)
    [ Param "_env" (TRecord "Closure")
    , Param "_arg" (TRecord "Closure")
    ]
    (RTTy (TRecord "Closure"))
    [ SReturn (Just (compileExprS subst body)) ]
  where
    subst =
      [ (v, EField (EVar "_env") ("f" ++ show i))
      | (i, v) <- zip [0::Int ..] fvs
      ]
      ++ [(x, EVar "_arg")]

-- Generate the dynamic-dispatch apply function.

genApplyFunc :: [LamId] -> FuncDecl
genApplyFunc lids =
  FuncDecl
    "apply"
    [ Param "_f"   (TRecord "Closure")
    , Param "_arg" (TRecord "Closure")
    ]
    (RTTy (TRecord "Closure"))
    [buildDispatch lids]
  where
    buildDispatch [] =
      SReturn (Just (ENew "Closure" [("tag", EInt (-1))]))
    buildDispatch (k : ks) =
      SIf
        (EField (EVar "_f") "tag" :=: EInt k)
        [ SReturn
            (Just (ECall ("lam_" ++ show k) [EVar "_f", EVar "_arg"]))
        ]
        [buildDispatch ks]

-- Top-level entry point.
--
-- The main block evaluates the term and prints the result.  Literal-boxed
-- closures are unwrapped: tag == litIntTag prints the integer val field;
-- tag == litBoolTag prints true/false depending on the val field.

lambdaToTImp :: Term -> TImp
lambdaToTImp term =
  TImp decls mainBlock
  where
    ann     = evalState (annotate term) 0
    lambdas = collectLambdas ann
    maxFVs  = maximum (0 : [length fvs | (_, _, fvs, _) <- lambdas])
    lids    = [k | (k, _, _, _) <- lambdas]

    closureRec  = DRecord (genClosureRecord maxFVs)
    liftedFuncs = map (DFunc . genLiftedFunc) lambdas
    applyFunc   = DFunc (genApplyFunc lids)

    decls = closureRec : liftedFuncs ++ [applyFunc]

    resTag = EField (EVar "_res") "tag"
    resVal = EField (EVar "_res") "val"

    mainBlock =
      [ SDecl "_res" (TRecord "Closure") (compileExprS [] ann)
      , SIf (resTag :=: EInt litIntTag)
          [ SPrint resVal ]
          [ SIf (resTag :=: EInt litBoolTag)
              [ SIf (resVal :!=: EInt 0)
                  [ SPrint (EBool True)  ]
                  [ SPrint (EBool False) ]
              ]
              [ SPrint (EVar "_res") ]
          ]
      ]
