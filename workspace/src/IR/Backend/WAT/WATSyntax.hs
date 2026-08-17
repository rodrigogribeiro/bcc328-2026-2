module IR.Backend.WAT.WATSyntax where

-- Named identifier in WAT (locals, labels, function names).
type WIdent = String

-- The only value type needed: all IR values are integer-word-sized.
data WValType = WI32
  deriving (Eq, Show)

-- Binary operations on i32.
data WBinOp
  = WAdd | WSub | WMul | WDivS | WRemS
  | WAnd | WOr  | WXor
  | WShl | WShrS | WShrU
  | WEq  | WNe
  | WLtS | WLeS | WGtS | WGeS
  deriving (Eq, Show)

-- WAT instructions used by the IR backend.
data WInstr
  = WI32Const  Int           -- i32.const n
  | WLocalGet  WIdent        -- local.get $x
  | WLocalSet  WIdent        -- local.set $x  (consumes stack top)
  | WLocalTee  WIdent        -- local.tee $x  (set + keep on stack)
  | WGlobalGet WIdent        -- global.get $g
  | WGlobalSet WIdent        -- global.set $g (consumes stack top)
  | WI32BinOp  WBinOp       -- i32.<op>  (binary, pops two, pushes one)
  | WI32Eqz                  -- i32.eqz   (pops one i32, pushes 0/1)
  | WI32Load                 -- i32.load  (address on stack → value)
  | WI32Store                -- i32.store (address then value on stack)
  | WDrop                    -- drop top of stack
  | WReturn                  -- return from function
  | WBlock (Maybe WIdent) [WInstr]
  | WLoop  (Maybe WIdent) [WInstr]
  | WIf    [WInstr] (Maybe [WInstr])  -- then-branch; optional else-branch
  | WBr    WIdent            -- br $label
  | WBrIf  WIdent            -- br_if $label
  | WCall  WIdent            -- call $func
  | WUnreachable             -- unreachable (bottom type)
  deriving (Eq, Show)

-- Parameter declaration.
data WParam = WParam WIdent WValType
  deriving (Eq, Show)

-- Local variable declaration.
data WLocal = WLocal WIdent WValType
  deriving (Eq, Show)

-- Function type used in imports.
data WFuncType = WFuncType [WValType] (Maybe WValType)
  deriving (Eq, Show)

-- Function definition.
data WFunc = WFunc
  { wfName   :: WIdent
  , wfParams :: [WParam]
  , wfResult :: Maybe WValType
  , wfLocals :: [WLocal]
  , wfBody   :: [WInstr]
  } deriving (Eq, Show)

-- Import declaration.
data WImport = WImport
  { wiModule   :: String
  , wiField    :: String
  , wiDescName :: WIdent
  , wiDescType :: WFuncType
  } deriving (Eq, Show)

-- Mutable global variable with a constant initialiser.
data WGlobal = WGlobal
  { wgName    :: WIdent
  , wgType    :: WValType
  , wgMutable :: Bool
  , wgInit    :: Int
  } deriving (Eq, Show)

-- Export declaration.
data WExport = WExport String WIdent   -- external name, internal function id
  deriving (Eq, Show)

-- A complete WebAssembly module.
data WModule = WModule
  { wmImports      :: [WImport]
  , wmMemory       :: Maybe Int         -- initial pages (64 KB each)
  , wmMemoryExport :: Maybe String      -- inline export name for the memory, if any
  , wmGlobals      :: [WGlobal]
  , wmFuncs        :: [WFunc]
  , wmExports      :: [WExport]
  , wmRawDecls     :: [String]          -- verbatim WAT declarations appended after wmFuncs
  } deriving (Eq, Show)
