module Main where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Options.Applicative
import System.Console.Haskeline
import System.Exit (exitSuccess)
import System.FilePath ((-<.>))

import FJ.Backend.IR.FJCodegen (compileFJ)
import FJ.Frontend.ClassTable.ClassTable
import IR.Frontend.Pretty.IRPretty ()
import FJ.Frontend.Parser.FJParser
import FJ.Frontend.Pretty.FJPretty
import FJ.Frontend.Syntax.FJSyntax
import FJ.Frontend.TypeChecker.FJTypeChecker
import FJ.Interp.FJInterp
import Utils.Pretty (pretty)

-- Command-line options

data Mode = Repl | CompileIR

data Options = Options
  { optMode :: Mode
  , optFile :: Maybe FilePath
  }

optionsP :: Parser Options
optionsP = Options
  <$> flag Repl CompileIR
        (  long "ir"
        <> help "Compile source file to IRT and write the result to a .ir file")
  <*> optional
        (strOption
           (  long "file"
           <> short 'f'
           <> metavar "FILENAME"
           <> help "Source file to compile (required with --ir)"))

opts :: ParserInfo Options
opts = info (optionsP <**> helper)
  (  fullDesc
  <> header "fj -- Featherweight Java interpreter and compiler")

-- IR compilation pipeline

compileIR :: FilePath -> IO ()
compileIR fname = do
    src <- readFile fname
    case parseProgram src of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right prog@(Program cls _) -> do
        let ct = buildCT cls
        case typeCheckClasses ct cls of
          Left err -> putStrLn $ "Type error: " ++ err
          Right _  ->
            case compileFJ prog of
              Left err   -> putStrLn $ "Code generation error: " ++ err
              Right irProg -> do
                let irFile = fname -<.> "ir"
                writeFile irFile (pretty irProg)
                putStrLn $ "IR written to " ++ irFile

-- REPL

data ReplState = ReplState
  { rsClasses :: [ClassDecl]
  , rsDebug   :: Bool
  }

emptyState :: ReplState
emptyState = ReplState [] False

banner :: String
banner = unlines
  [ "Featherweight Java Interpreter"
  , "  :load <file>   load class declarations from a FJ source file"
  , "  :classes       list loaded classes"
  , "  :debug         toggle debug output"
  , "  :q             quit"
  , ""
  , "Type a FJ expression to type-check and evaluate it."
  ]

runRepl :: IO ()
runRepl = do
    putStr banner
    runInputT defaultSettings (loop emptyState)
  where
    loop :: ReplState -> InputT IO ()
    loop st = do
      minput <- getInputLine "FJ> "
      case minput of
        Nothing   -> liftIO exitSuccess
        Just ":q" -> outputStrLn "Goodbye!"
        Just ":classes" -> do
          let names = map cdName (rsClasses st)
          if null names
            then outputStrLn "(no classes loaded)"
            else mapM_ outputStrLn names
          loop st
        Just ":debug" -> do
          let st' = st { rsDebug = not (rsDebug st) }
          outputStrLn $ "Debug " ++ (if rsDebug st' then "on" else "off")
          loop st'
        Just cmd
          | take 6 cmd == ":load " -> do
              let path = dropWhile (== ' ') (drop 6 cmd)
              st' <- liftIO $ loadFile st path
              loop st'
          | all (== ' ') cmd -> loop st
          | otherwise -> do
              liftIO $ processExpr st cmd
              loop st

loadFile :: ReplState -> FilePath -> IO ReplState
loadFile st path = do
    src <- readFile path
    case parseProgram src of
      Left err -> do
        putStrLn $ "Parse error in " ++ path ++ ":\n" ++ err
        return st
      Right (Program cls _mainExpr) -> do
        let allClasses = rsClasses st ++ cls
            ct         = buildCT allClasses
        case typeCheckClasses ct allClasses of
          Left err -> do
            putStrLn $ "Type error in " ++ path ++ ":\n" ++ err
            return st
          Right _ -> do
            putStrLn $ "Loaded " ++ show (length cls) ++ " class(es): " ++
                       unwords (map cdName cls)
            return st { rsClasses = allClasses }

processExpr :: ReplState -> String -> IO ()
processExpr st input = do
    let ct = buildCT (rsClasses st)
    case parseExpr input of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right e  -> do
        when (rsDebug st) $ putStrLn $ "  [parsed] " ++ prettyExpr e
        case typeCheckExpr ct e of
          Left err -> putStrLn $ "Type error: " ++ err
          Right ty -> do
            putStrLn $ "type : " ++ prettyType ty
            case evalExpr ct e of
              Left  err -> putStrLn $ "Runtime error: " ++ err
              Right val -> putStrLn $ "--> "  ++ showValue val

-- Entry point

main :: IO ()
main = do
    o <- execParser opts
    case optMode o of
      CompileIR ->
        case optFile o of
          Nothing    -> putStrLn "Error: --ir requires a source file (-f FILE)"
          Just fname -> compileIR fname
      Repl -> runRepl
