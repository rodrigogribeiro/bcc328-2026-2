module Main where

import Control.Monad (unless)
import Options.Applicative
import System.FilePath

import TImp.Frontend.Lexer.TImpLexer    (tokenize, showTokens)
import TImp.Frontend.Parser.TImpParser  (timpParser)
import TImp.Frontend.Syntax.TImpSyntax
import TImp.Frontend.TypeCheck.TImpTypeCheck (typeCheck, TcResult (..))
import TImp.Interp.TImpInterp           (interpret)
import TImp.Backend.IR.TImpCodegen      (compileTImp)
import qualified TImp.Backend.C.TImpCCodegen as CCodegen
import IR.Frontend.Pretty.IRPretty      ()
import IR.Backend.X86.IRToX86           (irToX86)
import IR.Backend.X86.X86Pretty         ()
import Utils.Pretty                     (pretty)

-- Command-line options

data Mode
  = Lex
  | Parse
  | TypeChk
  | Interp
  | CompileIR
  | CompileC
  | CompileX86

data Options = Options Mode FilePath

modeP :: Parser Mode
modeP = lexP <|> parseP <|> typecheckP <|> interpP <|> irP <|> cP <|> x86P
  where
    lexP =
      flag' Lex
        (long "lex" <> help "Tokenize the program and print the token stream")
    parseP =
      flag' Parse
        (long "parse" <> help "Parse the program and print the AST")
    typecheckP =
      flag' TypeChk
        (long "typecheck" <> help "Type-check and print the typing context")
    interpP =
      flag' Interp
        (long "interp" <> help "Interpret the program")
    irP =
      flag' CompileIR
        (long "ir" <> help "Compile to IRT and write a .ir file")
    cP =
      flag' CompileC
        (long "c" <> help "Compile to C and write a .c file")
    x86P =
      flag' CompileX86
        (long "x86" <> help "Compile to X86-64 assembly and write a .s file")

fileP :: Parser FilePath
fileP = strOption
  (long "file" <> short 'f' <> metavar "FILE" <> help "Source file (.timp)")

optionsP :: Parser Options
optionsP = Options <$> modeP <*> fileP

opts :: ParserInfo Options
opts = info (optionsP <**> helper)
  (fullDesc
   <> header "timp -- type checker, interpreter and compiler for TImp"
   <> progDesc "Process files written in the TImp language.")

-- Pipeline

run :: Options -> IO ()
run (Options Lex fname) = do
  src <- readFile fname
  case tokenize src of
    Left err -> putStrLn ("Lexical error:\n" ++ err)
    Right ts -> putStr (showTokens ts)
run (Options Parse fname) = do
  src <- readFile fname
  case timpParser src of
    Left err  -> putStrLn ("Parse error:\n" ++ err)
    Right ast -> print ast
run (Options TypeChk fname) = do
  src <- readFile fname
  case timpParser src of
    Left err  -> putStrLn ("Parse error:\n" ++ err)
    Right ast ->
      case typeCheck ast of
        Left err -> putStrLn ("Type error: " ++ err)
        Right r  -> do
          putStrLn "OK. Type context:"
          unless (null (tcRecordCtx r)) $ do
            putStrLn "\nRecord types:"
            mapM_ printRecord (tcRecordCtx r)
          unless (null (tcFuncCtx r)) $ do
            putStrLn "\nFunctions:"
            mapM_ printFunc (tcFuncCtx r)
          unless (null (tcVarCtx r)) $ do
            putStrLn "\nTop-level variables:"
            mapM_ (\(v, t) -> putStrLn ("  " ++ v ++ " : " ++ showTy t)) (tcVarCtx r)
run (Options Interp fname) = do
  src <- readFile fname
  case timpParser src of
    Left err  -> putStrLn ("Parse error:\n" ++ err)
    Right ast ->
      case typeCheck ast of
        Left err -> putStrLn ("Type error: " ++ err)
        Right _  -> do
          result <- interpret ast
          case result of
            Left err -> putStrLn ("Runtime error: " ++ err)
            Right _  -> pure ()
run (Options CompileIR fname) = do
  src <- readFile fname
  case timpParser src of
    Left err  -> putStrLn ("Parse error:\n" ++ err)
    Right ast ->
      case typeCheck ast of
        Left err -> putStrLn ("Type error: " ++ err)
        Right _  ->
          case compileTImp ast of
            Left err   -> putStrLn ("Code generation error: " ++ err)
            Right prog -> do
              let irFile = fname -<.> "ir"
              writeFile irFile (pretty prog)
              putStrLn ("IR written to " ++ irFile)
run (Options CompileC fname) = do
  src <- readFile fname
  case timpParser src of
    Left err  -> putStrLn ("Parse error:\n" ++ err)
    Right ast ->
      case typeCheck ast of
        Left err -> putStrLn ("Type error: " ++ err)
        Right _  ->
          case CCodegen.compileTImp ast of
            Left err    -> putStrLn ("Code generation error: " ++ err)
            Right cCode -> do
              let cFile = fname -<.> "c"
              writeFile cFile cCode
              putStrLn ("C code written to " ++ cFile)
run (Options CompileX86 fname) = do
  src <- readFile fname
  case timpParser src of
    Left err  -> putStrLn ("Parse error:\n" ++ err)
    Right ast ->
      case typeCheck ast of
        Left err -> putStrLn ("Type error: " ++ err)
        Right _  ->
          case compileTImp ast of
            Left err   -> putStrLn ("Code generation error: " ++ err)
            Right prog -> do
              let asmFile = fname -<.> "s"
              writeFile asmFile (pretty (irToX86 prog))
              putStrLn ("X86-64 assembly written to " ++ asmFile)

-- Display helpers

showTy :: Ty -> String
showTy TInt        = "int"
showTy TBool       = "bool"
showTy TString     = "string"
showTy (TRecord n) = n

showRetTy :: RetTy -> String
showRetTy RTVoid    = "void"
showRetTy (RTTy t)  = showTy t

printRecord :: (Name, [(Field, Ty)]) -> IO ()
printRecord (name, fields) = do
  putStrLn ("  record " ++ name ++ " {")
  mapM_ (\(f, t) -> putStrLn ("    " ++ f ++ " : " ++ showTy t)) fields
  putStrLn "  }"

printFunc :: (Name, ([Ty], RetTy)) -> IO ()
printFunc (name, (params, ret)) =
  putStrLn ("  fn " ++ name
            ++ "(" ++ commaSep (map showTy params) ++ ")"
            ++ " : " ++ showRetTy ret)

commaSep :: [String] -> String
commaSep []     = ""
commaSep [x]    = x
commaSep (x:xs) = x ++ ", " ++ commaSep xs

-- Main

main :: IO ()
main = execParser opts >>= run
