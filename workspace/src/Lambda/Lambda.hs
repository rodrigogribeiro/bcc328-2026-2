import Options.Applicative
import System.FilePath
import System.Console.Haskeline
import Control.Monad.IO.Class (liftIO)

import Lambda.Backend.TImp.LambdaToTImp
import Lambda.Frontend.Parser.LambdaParser
import Lambda.Interp.LambdaInterp
import TImp.Frontend.Pretty.TImpPretty ()
import Utils.Pretty hiding ((<>))

-- ---------------------------------------------------------------------------
-- Command line options
-- ---------------------------------------------------------------------------

data Option
  = Repl
  | CompileTImp FilePath

optionP :: Parser Option
optionP = replP <|> timpP
  where
    replP =
      flag' Repl
        (  long "repl"
        <> help "Start the interactive REPL")
    timpP =
      CompileTImp <$>
        strOption
          (  long "timp"
          <> metavar "FILENAME"
          <> help "Compile and run a lambda-calculus source file via TImp")

opts :: ParserInfo Option
opts = info (optionP <**> helper)
  (  fullDesc
  <> header "lambda -- untyped lambda calculus interpreter and compiler")

-- ---------------------------------------------------------------------------
-- REPL
-- ---------------------------------------------------------------------------

banner :: String
banner = unlines
  [ "Untyped Lambda Calculus"
  , "  syntax:  \\x. t   |   t t   |   x"
  , "  multi-binder:  \\x y z. t"
  , "  quit:    :q"
  ]

runRepl :: IO ()
runRepl = do
    putStr banner
    runInputT defaultSettings loop
  where
    loop :: InputT IO ()
    loop = do
      minput <- getInputLine "λ> "
      case minput of
        Nothing   -> outputStrLn "Goodbye!"
        Just ":q" -> outputStrLn "Goodbye!"
        Just input
          | all (== ' ') input -> loop
          | otherwise -> do
              liftIO $ processInput input
              loop

processInput :: String -> IO ()
processInput input =
  case lambdaParser input of
    Left  err -> putStrLn $ "Parse error:\n" ++ err
    Right t   ->
      case runEval t of
        Left  err -> putStrLn $ "Error: " ++ err
        Right val -> putStrLn $ "--> " ++ show val

-- ---------------------------------------------------------------------------
-- TImp compilation and execution
-- ---------------------------------------------------------------------------

runTImp :: FilePath -> IO ()
runTImp fname = do
    content <- readFile fname
    case lambdaParser content of
      Left err -> putStrLn $ "Parse error:\n" ++ err
      Right t  -> do
        let prog    = lambdaToTImp t
            outFile = fname -<.> "timp"
        writeFile outFile (pretty prog)
        putStrLn $ "TImp code written to " ++ outFile

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = execParser opts >>= \opt ->
  case opt of
    Repl           -> runRepl
    CompileTImp fp -> runTImp fp
