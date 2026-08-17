import Options.Applicative
import System.FilePath

import TLine.Backend.IR.TLineCodegen   (compileTLine)
import qualified TLine.Backend.C.TLineCCodegen as CCodegen
import IR.Frontend.Pretty.IRPretty ()
import TLine.Frontend.Parser.TLineParser
import TLine.Frontend.Syntax.TLineSyntax
import TLine.Frontend.TypeCheck.TLineTypeCheck
import Utils.Pretty hiding (Mode, (<>))

-- command line options

data Option
  = Option Mode FilePath

data Mode
  = TypeCheck
  | CompileIR
  | CompileC

optionP :: Parser Option
optionP = Option <$> modeP <*> fileOptionP

modeP :: Parser Mode
modeP = typecheckP <|> irP <|> cP
  where
    typecheckP =
      flag' TypeCheck
        (  long "typecheck"
        <> help "Parse and type-check the program, printing the typing context")
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
  <> header "tline -- type checker and compiler for TLine")

-- pretty-print a type

showTy :: Ty -> String
showTy TInt    = "int"
showTy TBool   = "bool"
showTy TString = "string"

-- pipeline

startPipeline :: Option -> IO ()

startPipeline (Option TypeCheck fname) = do
    content <- readFile fname
    case tlineParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err  -> putStrLn $ "Type error: " ++ err
          Right ctx -> do
            putStrLn "OK. Typing context:"
            mapM_ (\(v, t) -> putStrLn $ "  " ++ v ++ " : " ++ showTy t) ctx

startPipeline (Option CompileIR fname) = do
    content <- readFile fname
    case tlineParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err -> putStrLn $ "Type error: " ++ err
          Right _  ->
            case compileTLine ast of
              Left err   -> putStrLn $ "Code generation error: " ++ err
              Right prog -> do
                let irFile = fname -<.> "ir"
                writeFile irFile (pretty prog)
                putStrLn $ "IR written to " ++ irFile

startPipeline (Option CompileC fname) = do
    content <- readFile fname
    case tlineParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err -> putStrLn $ "Type error: " ++ err
          Right _  ->
            case CCodegen.compileTLine ast of
              Left err    -> putStrLn $ "Code generation error: " ++ err
              Right cCode -> do
                let cFile = fname -<.> "c"
                writeFile cFile cCode
                putStrLn $ "C code written to " ++ cFile

main :: IO ()
main = execParser opts >>= startPipeline
