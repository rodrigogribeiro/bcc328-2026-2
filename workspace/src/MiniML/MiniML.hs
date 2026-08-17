import System.Console.Haskeline
import Control.Monad.IO.Class (liftIO)

import MiniML.Backend.Lambda.Erase (erase)
import MiniML.Frontend.Interp.MiniMLInterp
import MiniML.Frontend.Parser.ExpParser (parser)
import MiniML.Frontend.Pretty.PrettyPrint
import MiniML.Frontend.TypeInference.Inference
import MiniML.Frontend.TypeInference.SolverMonad hiding (emptyEnv)
import MiniML.Mono.Mono (monomorphize, monoSpecKeys, monoTree)
import Lambda.Backend.TImp.LambdaToTImp (lambdaToTImp)
import TImp.Interp.TImpInterp (interpret)

main :: IO ()
main = do
    putStrLn "MiniML  —  type :q to quit, :debug to toggle debug output"
    runInputT defaultSettings (loop False)
  where
    loop :: Bool -> InputT IO ()
    loop dbg = do
      minput <- getInputLine "MiniML> "
      case minput of
        Nothing    -> outputStrLn "Goodbye!"
        Just ":q"  -> outputStrLn "Goodbye!"
        Just ":debug" -> do
          let dbg' = not dbg
          outputStrLn $ "Debug output " ++ (if dbg' then "on" else "off")
          loop dbg'
        Just input
          | all (== ' ') input -> loop dbg
          | otherwise -> do
              if take 5 input == ":mono"
                then liftIO $ processMono (drop 5 input)
                else if take 5 input == ":timp"
                  then liftIO $ processTImp (drop 5 input)
                  else liftIO $ process dbg input
              loop dbg

processMono :: String -> IO ()
processMono input =
  case parser (dropWhile (== ' ') input) of
    Left err  -> putStrLn $ "Parse error:\n" ++ err
    Right ast ->
      case monomorphize ast of
        Left err -> putStrLn $ "Monomorphization error: " ++ err
        Right result -> do
          let keys = monoSpecKeys result
          if null keys
            then putStrLn "[no polymorphic specializations]"
            else do
              putStrLn "[specializations]"
              mapM_ (\(n, args) ->
                putStrLn $ "  " ++ n ++ " @ [" ++
                  concatMap (\t -> pretty t ++ " ") args ++ "]")
                keys
          putStrLn "[monomorphic tree]"
          putStrLn $ pretty (monoTree result)

processTImp :: String -> IO ()
processTImp input =
  case parser (dropWhile (== ' ') input) of
    Left err  -> putStrLn $ "Parse error:\n" ++ err
    Right ast ->
      case inferElab ast of
        Left err -> putStrLn $ "Type error: " ++ err
        Right (_, _, te, ty) -> do
          putStrLn $ "val : " ++ pretty ty
          let lterm = erase te
              prog  = lambdaToTImp lterm
          result <- interpret prog
          case result of
            Left err -> putStrLn $ "Runtime error: " ++ err
            Right () -> return ()

process :: Bool -> String -> IO ()
process dbg input =
  case parser input of
    Left err  -> putStrLn $ "Parse error:\n" ++ err
    Right ast ->
      case inferElab ast of
        Left err          -> putStrLn $ "Type error: " ++ err
        Right (c, env, te, ty) -> do
          -- 1. Show the inferred type (always)
          putStrLn $ "val : " ++ pretty ty
          -- 2. Show elaborated tree and solver details when debugging
          if dbg
            then do
              putStrLn "  [constraint]"
              putStrLn $ "    " ++ pretty c
              putStrLn "  [elaborated]"
              putStrLn $ "    " ++ pretty te
              let infs = infered env
              if not (null infs)
                then do
                  putStrLn "  [let bindings]"
                  mapM_ (\(n, sch) ->
                    putStrLn $ "    " ++ n ++ " : " ++ pretty sch) infs
                else return ()
            else return ()
          -- 3. Evaluate and show the result
          case runEval emptyEnv ast of
            Left  err -> putStrLn $ "Runtime error: " ++ err
            Right val -> putStrLn $ "--> " ++ show val
