import Options.Applicative

import TExp.Frontend.Parser.TExpParser
import TExp.Frontend.Syntax.TExpSyntax
import TExp.Frontend.TypeCheck.TExpTypeChecker
import TExp.Interp.TExpInterp

-- command line options

data Option
  = Option Mode FilePath

data Mode
  = Interp
  | TypeCheck

optionP :: Parser Option
optionP = Option <$> modeP <*> fileOptionP

modeP :: Parser Mode
modeP
  = flag' Interp
      (  long "interp"
      <> help "Parse, type-check and evaluate the program")
    <|>
    flag' TypeCheck
      (  long "typecheck"
      <> help "Parse and type-check the program only")

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
  <> header "texp -- interpreter for the typed expression language (TAPL ch. 8)")

-- pretty-print a type

showTy :: Ty -> String
showTy TBool = "Bool"
showTy TNat  = "Nat"

-- pipeline

startPipeline :: Option -> IO ()
startPipeline (Option mode fname) = do
    content <- readFile fname
    case termParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right ast ->
        case typeCheck ast of
          Left err -> putStrLn $ "Type error: " ++ err
          Right ty ->
            case mode of
              TypeCheck ->
                putStrLn $ "OK: " ++ showTy ty
              Interp ->
                case eval ast of
                  Left err  -> putStrLn $ "Runtime error: " ++ err
                  Right val -> putStrLn (showValue val)

main :: IO ()
main = execParser opts >>= startPipeline
