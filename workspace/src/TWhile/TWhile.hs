import Options.Applicative
import System.FilePath

import qualified TWhile.Backend.IR.TWhileCodegen    as IRGen
import qualified TWhile.Backend.WASM.TWhileCodegen  as WASMGen
import qualified TWhile.Backend.C.TWhileCCodegen    as CGen
import IR.Frontend.Pretty.IRPretty ()
import TWhile.Frontend.Parser.TWhileParser
import TWhile.Frontend.Syntax.TWhileSyntax
import TWhile.Frontend.TypeCheck.TWhileTypeCheck
import Utils.Pretty hiding (Mode, (<>))

-- Command line options

data Option = Option Mode FilePath

data Mode
  = TypeCheck
  | CompileWasm
  | CompileIR
  | CompileC

optionP :: Parser Option
optionP = Option <$> modeP <*> fileOptionP

modeP :: Parser Mode
modeP = typecheckP <|> wasmP <|> irP <|> cP
  where
    typecheckP =
      flag' TypeCheck
        (  long "typecheck"
        <> help "Parse and type-check the program, printing the typing context")
    wasmP =
      flag' CompileWasm
        (  long "wasm"
        <> help "Compile to WebAssembly text format (.wat)")
    irP =
      flag' CompileIR
        (  long "ir"
        <> help "Compile to IRT and write the result to a .ir file")
    cP =
      flag' CompileC
        (  long "c"
        <> help "Compile to C and write the result to a .c file")

fileOptionP :: Parser FilePath
fileOptionP
  = strOption
      (  long "file"
      <> short 'f'
      <> metavar "FILENAME"
      <> help "Source file to process")

opts :: ParserInfo Option
opts = info optionP
  (  fullDesc
  <> header "twhile -- type checker and compiler for TWhile")

-- Helpers

showTy :: Ty -> String
showTy TInt    = "int"
showTy TBool   = "bool"
showTy TString = "string"

-- Pipeline

startPipeline :: Option -> IO ()
startPipeline (Option TypeCheck fname) = do
    content <- readFile fname
    case twhileParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err  -> putStrLn $ "Type error: " ++ err
          Right ctx -> do
            putStrLn "OK. Typing context:"
            mapM_ (\(v, t) -> putStrLn $ "  " ++ v ++ " : " ++ showTy t) ctx
startPipeline (Option CompileWasm fname) = do
    content <- readFile fname
    case twhileParser content of
      Left err  -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err -> putStrLn $ "Type error: " ++ err
          Right _  ->
            case WASMGen.compileTWhile ast of
              Left err      -> putStrLn $ "Code generation error: " ++ err
              Right watCode -> do
                let watFile = fname -<.> "wat"
                writeFile watFile watCode
                putStrLn $ "WebAssembly module written to " ++ watFile
startPipeline (Option CompileIR fname) = do
    content <- readFile fname
    case twhileParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err -> putStrLn $ "Type error: " ++ err
          Right _  ->
            case IRGen.compileTWhile ast of
              Left err   -> putStrLn $ "Code generation error: " ++ err
              Right prog -> do
                let irFile = fname -<.> "ir"
                writeFile irFile (pretty prog)
                putStrLn $ "IR written to " ++ irFile
startPipeline (Option CompileC fname) = do
    content <- readFile fname
    case twhileParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err -> putStrLn $ "Type error: " ++ err
          Right _  ->
            case CGen.compileTWhile ast of
              Left err    -> putStrLn $ "Code generation error: " ++ err
              Right cCode -> do
                let cFile = fname -<.> "c"
                writeFile cFile cCode
                putStrLn $ "C code written to " ++ cFile

-- Main

main :: IO ()
main = execParser opts >>= startPipeline
