module TWhile.Backend.WASM.Syntax where

-- WebAssembly types supported by the TWhile backend.
-- Booleans are represented as i32 (0 = false, 1 = true).
data WasmType = I32
  deriving (Eq, Show)

-- WebAssembly instruction set used by the TWhile backend.
data WasmInstr
  = I32Const Int
  | LocalGet  Int
  | LocalSet  Int
  | I32Add
  | I32Sub
  | I32Mul
  | I32DivS
  | I32LtS
  | I32Eq
  | I32Eqz
  | Call String
  | Drop
  | If   (Maybe WasmType) [WasmInstr] [WasmInstr]
  | Block [WasmInstr]
  | Loop  [WasmInstr]
  | BrIf  Int
  | Br    Int
  deriving (Eq, Show)

data WasmFunc = WasmFunc
  { funcName    :: String
  , funcParams  :: [WasmType]
  , funcResults :: [WasmType]
  , funcLocals  :: [WasmType]
  , funcBody    :: [WasmInstr]
  } deriving (Eq, Show)

data WasmImport = WasmImport
  { importModule :: String
  , importName   :: String
  , importDesc   :: ImportDesc
  } deriving (Eq, Show)

data ImportDesc = ImportFunc String [WasmType] [WasmType]
  deriving (Eq, Show)

data WasmExport = WasmExport
  { exportName :: String
  , exportDesc :: ExportDesc
  } deriving (Eq, Show)

data ExportDesc = ExportFunc String
  deriving (Eq, Show)

data WasmModule = WasmModule
  { moduleImports :: [WasmImport]
  , moduleExports :: [WasmExport]
  , moduleFuncs   :: [WasmFunc]
  } deriving (Eq, Show)
