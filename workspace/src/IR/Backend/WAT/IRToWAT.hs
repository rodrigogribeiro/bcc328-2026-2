module IR.Backend.WAT.IRToWAT
  ( irToWAT
  ) where

import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad        (guard)
import Control.Applicative  ((<|>))

import Data.Array (Array, (!), listArray)
import Data.List  ((\\))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

import IR.Backend.WAT.WATSyntax
import IR.Frontend.Syntax.IRSyntax

-- Public entry point

-- Compile an IRT program to a WAT module.
irToWAT :: Program -> Either String WModule
irToWAT prog = do
  let retMap = buildRetMap prog
  funcDefs <- mapM (compileFunc retMap) prog
  return WModule
    { wmImports      = wasiImports
    , wmMemory       = Just 4
    , wmMemoryExport = Just "memory"
    , wmGlobals      = [heapPtrGlobal]
    , wmFuncs        = allocFunc : funcDefs
    , wmExports      = [WExport "main" "main", WExport "_start" "main"]
    , wmRawDecls     = [runtimePrint, runtimeReadInt]
    }

-- WASI imports used by the inlined runtime functions

wasiImports :: [WImport]
wasiImports =
  [ WImport "wasi_snapshot_preview1" "fd_write" "fd_write"
      (WFuncType [WI32, WI32, WI32, WI32] (Just WI32))
  , WImport "wasi_snapshot_preview1" "fd_read"  "fd_read"
      (WFuncType [WI32, WI32, WI32, WI32] (Just WI32))
  ]

heapPtrGlobal :: WGlobal
heapPtrGlobal = WGlobal "heap_ptr" WI32 True 128

-- Runtime I/O functions (verbatim WAT, embedded to avoid a separate linking step).
-- Memory layout for I/O buffers (addresses below the heap start at 128):
--   0-15  : iovec structure used by fd_write / fd_read
--  16-31  : nwritten / nread return slot
--  32-63  : input  buffer (32 bytes, used by read_int)
--  64-95  : output buffer (32 bytes, used by print)

runtimePrint :: String
runtimePrint = unlines
  [ "  (func $print (param $value i32)"
  , "    (local $temp  i32)"
  , "    (local $digit i32)"
  , "    (local $len   i32)"
  , "    (local $neg   i32)"
  , "    (local $pos   i32)"
  , "    local.get $value"
  , "    i32.const 0"
  , "    i32.lt_s"
  , "    local.set $neg"
  , "    local.get $neg"
  , "    if"
  , "      i32.const 0"
  , "      local.get $value"
  , "      i32.sub"
  , "      local.set $temp"
  , "    else"
  , "      local.get $value"
  , "      local.set $temp"
  , "    end"
  , "    i32.const 95"
  , "    local.set $pos"
  , "    local.get $temp"
  , "    i32.eqz"
  , "    if"
  , "      local.get $pos"
  , "      i32.const 48"
  , "      i32.store8"
  , "      local.get $pos"
  , "      i32.const 1"
  , "      i32.sub"
  , "      local.set $pos"
  , "      i32.const 1"
  , "      local.set $len"
  , "    else"
  , "      block $done"
  , "        loop $digit_loop"
  , "          local.get $temp"
  , "          i32.eqz"
  , "          br_if $done"
  , "          local.get $temp"
  , "          i32.const 10"
  , "          i32.rem_u"
  , "          i32.const 48"
  , "          i32.add"
  , "          local.set $digit"
  , "          local.get $pos"
  , "          local.get $digit"
  , "          i32.store8"
  , "          local.get $pos"
  , "          i32.const 1"
  , "          i32.sub"
  , "          local.set $pos"
  , "          local.get $temp"
  , "          i32.const 10"
  , "          i32.div_u"
  , "          local.set $temp"
  , "          local.get $len"
  , "          i32.const 1"
  , "          i32.add"
  , "          local.set $len"
  , "          br $digit_loop"
  , "        end"
  , "      end"
  , "    end"
  , "    local.get $neg"
  , "    if"
  , "      local.get $pos"
  , "      i32.const 45"
  , "      i32.store8"
  , "      local.get $pos"
  , "      i32.const 1"
  , "      i32.sub"
  , "      local.set $pos"
  , "      local.get $len"
  , "      i32.const 1"
  , "      i32.add"
  , "      local.set $len"
  , "    end"
  , "    local.get $pos"
  , "    i32.const 1"
  , "    i32.add"
  , "    local.get $len"
  , "    i32.add"
  , "    i32.const 10"
  , "    i32.store8"
  , "    local.get $len"
  , "    i32.const 1"
  , "    i32.add"
  , "    local.set $len"
  , "    i32.const 0"
  , "    local.get $pos"
  , "    i32.const 1"
  , "    i32.add"
  , "    i32.store"
  , "    i32.const 4"
  , "    local.get $len"
  , "    i32.store"
  , "    i32.const 1"
  , "    i32.const 0"
  , "    i32.const 1"
  , "    i32.const 16"
  , "    call $fd_write"
  , "    drop)"
  ]

runtimeReadInt :: String
runtimeReadInt = unlines
  [ "  (func $read_int (result i32)"
  , "    (local $result i32)"
  , "    (local $pos    i32)"
  , "    (local $char   i32)"
  , "    (local $neg    i32)"
  , "    i32.const 0"
  , "    i32.const 32"
  , "    i32.store"
  , "    i32.const 4"
  , "    i32.const 31"
  , "    i32.store"
  , "    i32.const 0"
  , "    i32.const 0"
  , "    i32.const 1"
  , "    i32.const 16"
  , "    call $fd_read"
  , "    drop"
  , "    i32.const 32"
  , "    local.set $pos"
  , "    local.get $pos"
  , "    i32.load8_u"
  , "    i32.const 45"
  , "    i32.eq"
  , "    if"
  , "      i32.const 1"
  , "      local.set $neg"
  , "      local.get $pos"
  , "      i32.const 1"
  , "      i32.add"
  , "      local.set $pos"
  , "    end"
  , "    block $done"
  , "      loop $parse_loop"
  , "        local.get $pos"
  , "        i32.load8_u"
  , "        local.set $char"
  , "        local.get $char"
  , "        i32.const 48"
  , "        i32.ge_u"
  , "        local.get $char"
  , "        i32.const 57"
  , "        i32.le_u"
  , "        i32.and"
  , "        i32.eqz"
  , "        br_if $done"
  , "        local.get $result"
  , "        i32.const 10"
  , "        i32.mul"
  , "        local.get $char"
  , "        i32.const 48"
  , "        i32.sub"
  , "        i32.add"
  , "        local.set $result"
  , "        local.get $pos"
  , "        i32.const 1"
  , "        i32.add"
  , "        local.set $pos"
  , "        br $parse_loop"
  , "      end"
  , "    end"
  , "    local.get $neg"
  , "    if"
  , "      i32.const 0"
  , "      local.get $result"
  , "      i32.sub"
  , "      return"
  , "    end"
  , "    local.get $result)"
  ]

-- alloc(n) allocates n 8-byte words on the bump-pointer heap.
-- Returns the base address of the allocated block.
allocFunc :: WFunc
allocFunc = WFunc
  { wfName   = "alloc"
  , wfParams = [WParam "n" WI32]
  , wfResult = Just WI32
  , wfLocals = [WLocal "base" WI32]
  , wfBody   =
      [ WGlobalGet "heap_ptr"   -- push current heap_ptr
      , WLocalSet  "base"       -- base = heap_ptr
      , WGlobalGet "heap_ptr"   -- push heap_ptr
      , WLocalGet  "n"          -- push n
      , WI32Const  8            -- push 8
      , WI32BinOp  WMul         -- n * 8
      , WI32BinOp  WAdd         -- heap_ptr + n * 8
      , WGlobalSet "heap_ptr"   -- update heap_ptr
      , WLocalGet  "base"       -- return value
      ]
  }

-- Return-type map

-- Maps function names to their WAT return type.
type RetMap = Map String (Maybe WValType)

buildRetMap :: Program -> RetMap
buildRetMap prog =
  Map.fromList $
    [ ("print",    Nothing)
    , ("read_int", Just WI32)
    , ("alloc",    Just WI32)
    ] ++
    [ (funcName fd, if hasValueReturn (funcBody fd) then Just WI32 else Nothing)
    | fd <- prog
    ]

hasValueReturn :: Stmt -> Bool
hasValueReturn (RETURN (_:_)) = True
hasValueReturn (SEQ s1 s2)    = hasValueReturn s1 || hasValueReturn s2
hasValueReturn (MOVE _ e)     = hasValueReturnE e
hasValueReturn (EXP e)        = hasValueReturnE e
hasValueReturn _              = False

hasValueReturnE :: Expr -> Bool
hasValueReturnE (ESEQ s _) = hasValueReturn s
hasValueReturnE _          = False

-- Collect temporaries used in a function

collectTempsStmt :: Stmt -> Set Temp
collectTempsStmt (SEQ s1 s2)   = collectTempsStmt s1 <> collectTempsStmt s2
collectTempsStmt (MOVE d e)    = collectTempsExpr d  <> collectTempsExpr e
collectTempsStmt (EXP e)       = collectTempsExpr e
collectTempsStmt (JUMP e)      = collectTempsExpr e
collectTempsStmt (CJUMP e _ _) = collectTempsExpr e
collectTempsStmt (LABEL _)     = Set.empty
collectTempsStmt (RETURN es)   = foldMap collectTempsExpr es

collectTempsExpr :: Expr -> Set Temp
collectTempsExpr (CONST _)       = Set.empty
collectTempsExpr (TEMP t)        = Set.singleton t
collectTempsExpr (NAME _)        = Set.empty
collectTempsExpr (BINOP _ e1 e2) = collectTempsExpr e1 <> collectTempsExpr e2
collectTempsExpr (MEM e)         = collectTempsExpr e
collectTempsExpr (CALL ef args)  = collectTempsExpr ef <> foldMap collectTempsExpr args
collectTempsExpr (ESEQ s e)      = collectTempsStmt s  <> collectTempsExpr e

-- Linearisation and label map

-- Flatten nested SEQ into a left-to-right list.
linearize :: Stmt -> [Stmt]
linearize (SEQ s1 s2) = linearize s1 ++ linearize s2
linearize s           = [s]

type SArr     = Array Int Stmt
type LabelMap = Map Label Int

buildLabelMap :: [Stmt] -> LabelMap
buildLabelMap stmts =
  Map.fromList [(l, i) | (i, LABEL l) <- zip [0..] stmts]

-- Code-generation monad

type CodeM = ExceptT String Identity

runCodeM :: CodeM a -> Either String a
runCodeM = runIdentity . runExceptT

-- Function compilation

compileFunc :: RetMap -> FuncDef -> Either String WFunc
compileFunc retMap fd = runCodeM $ do
  let stmts   = linearize (funcBody fd)
      n       = length stmts
      sv      = listArray (0, n - 1) stmts
      lm      = buildLabelMap stmts
      params  = funcParams fd
      allT    = Set.toList (collectTempsStmt (funcBody fd))
      localTs = allT \\ params
      locals  = map (\t -> WLocal t WI32) localTs
      wparams = map (\p -> WParam p WI32) params
      hasRet  = hasValueReturn (funcBody fd)
  bodyInstrs <- compileBlock retMap sv lm 0 n
  let body = if hasRet then bodyInstrs ++ [WUnreachable] else bodyInstrs
  return WFunc
    { wfName   = funcName fd
    , wfParams = wparams
    , wfResult = if hasRet then Just WI32 else Nothing
    , wfLocals = locals
    , wfBody   = body
    }

-- Block compilation (index-range based)

-- Compile statements in the half-open range [from, to).
compileBlock :: RetMap -> SArr -> LabelMap -> Int -> Int -> CodeM [WInstr]
compileBlock retMap sv lm = go
  where
    go from to | from >= to = return []
    go i    to              = case sv ! i of

      -- ── While loop: LABEL lh followed immediately by CJUMP ─────────────
      -- Two conventions are handled:
      --   (A) CJUMP cond la lb  where la = body (at i+2), lb = exit
      --       → continue condition: negate cond with eqz before br_if exit
      --   (B) CJUMP cond la lb  where lb = body (at i+2), la = exit
      --       → exit condition: use cond directly as br_if exit
      LABEL lh
        | i + 1 < to
        , CJUMP cond la lb <- sv ! (i + 1)
        , Just (posBody, posExit, exitLbl, exitCond) <-
            tryWhile lm sv (i + 2) la lb lh
        -> do
            condWat  <- compileExpr cond
            bodyWat  <- go (posBody + 1) (posExit - 1)
            restWat  <- go (posExit + 1) to
            let checkInstr = if exitCond
                             then condWat ++ [WBrIf exitLbl]       -- (B)
                             else condWat ++ [WI32Eqz, WBrIf exitLbl]  -- (A)
                loop = WBlock (Just exitLbl)
                         [WLoop (Just lh) $ checkInstr ++ bodyWat ++ [WBr lh]]
            return (loop : restWat)

      LABEL _ -> go (i + 1) to   -- standalone label: skip

      -- ── If / If-else ────────────────────────────────────────────────────
      -- Convention: CJUMP cond lt lf where lt = then-label at i+1
      CJUMP cond lt lf
        | Just posLt <- Map.lookup lt lm , posLt == i + 1
        , Just posLf <- Map.lookup lf lm , posLf > i + 1
        -> do
            condWat <- compileExpr cond
            case sv ! (posLf - 1) of
              JUMP (NAME le)
                | Just posLe <- Map.lookup le lm , posLe > posLf
                -> do
                    thenWat <- go (posLt + 1) (posLf - 1)
                    elseWat <- go (posLf + 1) posLe
                    restWat <- go (posLe + 1) to
                    return $ condWat ++ [WIf thenWat (Just elseWat)] ++ restWat
              _ -> do
                    thenWat <- go (posLt + 1) posLf
                    restWat <- go (posLf + 1) to
                    return $ condWat ++ [WIf thenWat Nothing] ++ restWat

      -- ── Back-edge / fall-through jumps (already consumed above) ────────
      JUMP _  -> go (i + 1) to

      -- ── Non-control statements ──────────────────────────────────────────
      s -> do
        sWat    <- compileSingleStmt retMap s
        restWat <- go (i + 1) to
        return (sWat ++ restWat)

-- Try to recognise a while-loop given the two CJUMP branch labels.
-- Returns Just (posBody, posExit, exitLabel, exitCond) on success.
-- exitCond = True  → la is exit, condition means "exit now" (convention B)
-- exitCond = False → lb is exit, condition means "continue" (convention A)
tryWhile :: LabelMap -> SArr -> Int -> Label -> Label -> Label
         -> Maybe (Int, Int, Label, Bool)
tryWhile lm sv fallThrough la lb lh =
  tryConvA <|> tryConvB
  where
    -- Convention A: la (true-branch) = body falls through, lb = exit
    tryConvA = do
      posLa <- Map.lookup la lm
      guard (posLa == fallThrough)
      posLb <- Map.lookup lb lm
      guard (posLb > fallThrough)
      JUMP (NAME lh') <- Just (sv ! (posLb - 1))
      guard (lh' == lh)
      return (posLa, posLb, lb, False)

    -- Convention B: lb (false-branch) = body falls through, la = exit
    tryConvB = do
      posLb <- Map.lookup lb lm
      guard (posLb == fallThrough)
      posLa <- Map.lookup la lm
      guard (posLa > fallThrough)
      JUMP (NAME lh') <- Just (sv ! (posLa - 1))
      guard (lh' == lh)
      return (posLb, posLa, la, True)

-- Single statement compilation (no control flow)

compileSingleStmt :: RetMap -> Stmt -> CodeM [WInstr]
compileSingleStmt _ (MOVE (TEMP t) e) = do
  ew <- compileExpr e
  return (ew ++ [WLocalSet t])
compileSingleStmt _ (MOVE (MEM addrE) valE) = do
  aw <- compileExpr addrE
  vw <- compileExpr valE
  return (aw ++ vw ++ [WI32Store])
compileSingleStmt _ (MOVE _ _) =
  throwError "MOVE: destination must be TEMP or MEM"
compileSingleStmt retMap (EXP (CALL (NAME f) args)) = do
  argWs <- concat <$> mapM compileExpr args
  let needDrop = case Map.lookup f retMap of
        Just (Just _) -> [WDrop]
        _             -> []
  return (argWs ++ [WCall f] ++ needDrop)
compileSingleStmt _ (EXP e) = do
  ew <- compileExpr e
  return (ew ++ [WDrop])
compileSingleStmt _ (RETURN []) =
  return [WReturn]
compileSingleStmt _ (RETURN (e:_)) = do
  ew <- compileExpr e
  return (ew ++ [WReturn])
compileSingleStmt _ (LABEL _) = return []
compileSingleStmt _ (SEQ _ _) =
  throwError "compileSingleStmt: unexpected SEQ (should be linearised away)"
compileSingleStmt _ (JUMP _)     = return []
compileSingleStmt _ (CJUMP _ _ _) =
  throwError "compileSingleStmt: unexpected bare CJUMP (unrecognised pattern)"

-- Expression compilation

compileExpr :: Expr -> CodeM [WInstr]
compileExpr (CONST n)  = return [WI32Const n]
compileExpr (TEMP  t)  = return [WLocalGet t]
compileExpr (NAME  _)  =
  throwError "NAME cannot appear as a standalone value; use CALL(NAME f, ...) instead"
compileExpr (BINOP op e1 e2) = do
  w1 <- compileExpr e1
  w2 <- compileExpr e2
  return (w1 ++ w2 ++ [WI32BinOp (translateBinOp op)])
compileExpr (MEM e) = do
  ew <- compileExpr e
  return (ew ++ [WI32Load])
compileExpr (CALL (NAME f) args) = do
  argWs <- concat <$> mapM compileExpr args
  return (argWs ++ [WCall f])
compileExpr (CALL _ _) =
  throwError "Only direct calls CALL(NAME f, ...) are supported in the WAT backend"
compileExpr (ESEQ s e) = do
  sw <- compileESEQStmt s
  ew <- compileExpr e
  return (sw ++ ew)

-- Compile a statement inside an ESEQ (zero net stack effect).
compileESEQStmt :: Stmt -> CodeM [WInstr]
compileESEQStmt (SEQ s1 s2) = do
  w1 <- compileESEQStmt s1
  w2 <- compileESEQStmt s2
  return (w1 ++ w2)
compileESEQStmt (MOVE (TEMP t) e) = do
  ew <- compileExpr e
  return (ew ++ [WLocalSet t])
compileESEQStmt (MOVE (MEM addrE) valE) = do
  aw <- compileExpr addrE
  vw <- compileExpr valE
  return (aw ++ vw ++ [WI32Store])
compileESEQStmt (LABEL _) = return []
compileESEQStmt s =
  throwError ("Unsupported statement inside ESEQ: " ++ show s)

-- BinOp translation

translateBinOp :: BinOp -> WBinOp
translateBinOp BAdd  = WAdd
translateBinOp BSub  = WSub
translateBinOp BMul  = WMul
translateBinOp BDiv  = WDivS
translateBinOp BMod  = WRemS
translateBinOp BAnd  = WAnd
translateBinOp BOr   = WOr
translateBinOp BXor  = WXor
translateBinOp BLsh  = WShl
translateBinOp BRsh  = WShrU
translateBinOp BArsh = WShrS
translateBinOp BEq   = WEq
translateBinOp BNe   = WNe
translateBinOp BLt   = WLtS
translateBinOp BLe   = WLeS
translateBinOp BGt   = WGtS
translateBinOp BGe   = WGeS
