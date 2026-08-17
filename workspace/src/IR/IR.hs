module Main where

import qualified Data.Map.Strict as Map
import Options.Applicative
import System.FilePath (replaceExtension)

import IR.Frontend.Lexer.IRLexer        (tokenize, showTokens)
import IR.Frontend.Parser.IRParser       (parseProgram)
import IR.Frontend.Pretty.IRPretty       ()
import IR.Frontend.Syntax.IRSyntax       (funcBody, Program)
import IR.Interp.IRInterp                (buildProgMap, emptyState, runFunc, FuncResult (..))
import IR.Backend.WAT.IRToWAT            (irToWAT)
import IR.Backend.WAT.WATPretty          ()
import IR.Backend.X86.IRToX86           (irToX86)
import IR.Backend.X86.X86Pretty         ()
import IR.Opt.Pipeline
import IR.Opt.TCO    (tcoProgram)
import IR.Opt.Inline (defaultInlineConfig, inlineProgram)
import Utils.Pretty                      (pretty)

-- Command-line options

data Mode
  = Lex         FilePath
  | Parse       FilePath
  | Interp      FilePath
  | Wat         FilePath
  | X86         FilePath
  | OptFold     FilePath
  | OptProp     FilePath
  | OptFoldProp FilePath
  | OptCSE      FilePath
  | OptDCE      FilePath
  | OptLICM     FilePath
  | OptUnroll   Int FilePath
  | OptFusion   FilePath
  | OptTCO      FilePath
  | OptInline   FilePath
  | OptAll      FilePath

modeP :: Parser Mode
modeP = lexP <|> parseP <|> interpP <|> watP <|> x86P
     <|> optFoldP <|> optPropP <|> optFoldPropP
     <|> optCSEP  <|> optDCEP
     <|> optLICMP <|> optUnrollP <|> optFusionP
     <|> optTCOP  <|> optInlineP
     <|> optAllP
  where
    lexP =
      Lex <$>
        (flag' () (long "lex" <> help "Tokenize and print the token stream") *> fileArg)
    parseP =
      Parse <$>
        (flag' () (long "parse" <> help "Parse and pretty-print the IR tree") *> fileArg)
    interpP =
      Interp <$>
        (flag' () (long "interp" <> help "Interpret the IR program (runs 'main')") *> fileArg)
    watP =
      Wat <$>
        (flag' () (long "wat" <> help "Compile IR to WebAssembly Text (.wat)") *> fileArg)
    x86P =
      X86 <$>
        (flag' () (long "x86" <> help "Compile IR to X86-64 assembly (.s)") *> fileArg)
    optFoldP =
      OptFold <$>
        (flag' () (long "opt-fold" <> help "Constant folding only") *> fileArg)
    optPropP =
      OptProp <$>
        (flag' () (long "opt-prop" <> help "Constant propagation (with folding)") *> fileArg)
    optFoldPropP =
      OptFoldProp <$>
        (flag' () (long "opt-foldprop" <> help "Constant folding + propagation in one pass") *> fileArg)
    optCSEP =
      OptCSE <$>
        (flag' () (long "opt-cse" <> help "Common subexpression elimination") *> fileArg)
    optDCEP =
      OptDCE <$>
        (flag' () (long "opt-dce" <> help "Dead code elimination") *> fileArg)
    optLICMP =
      OptLICM <$>
        (flag' () (long "opt-licm" <> help "Loop-invariant code motion") *> fileArg)
    optUnrollP =
      OptUnroll
        <$> option auto (long "opt-unroll" <> metavar "K"
              <> help "Loop unrolling with factor K (default 2)" <> value 2)
        <*> fileArg
    optFusionP =
      OptFusion <$>
        (flag' () (long "opt-fusion" <> help "Loop fusion") *> fileArg)
    optTCOP =
      OptTCO <$>
        (flag' () (long "opt-tco" <> help "Tail-call elimination") *> fileArg)
    optInlineP =
      OptInline <$>
        (flag' () (long "opt-inline" <> help "Function inlining") *> fileArg)
    optAllP =
      OptAll <$>
        (flag' () (long "opt-all" <> help "Full optimisation pipeline") *> fileArg)
    fileArg =
      argument str (metavar "FILE" <> help "IR source file (.ir)")

opts :: ParserInfo Mode
opts = info (modeP <**> helper)
  (  fullDesc
  <> header "ir -- IRT lexer, parser, interpreter, and optimiser"
  <> progDesc "Process files written in the IRT intermediate representation."
  )

-- Driver

main :: IO ()
main = execParser opts >>= run

run :: Mode -> IO ()

run (Lex file) = do
  src <- readFile file
  case tokenize src of
    Left  err -> putStrLn ("Lexical error:\n" ++ err)
    Right tks -> putStr (showTokens tks)

run (Parse file) = do
  src <- readFile file
  case parseProgram src of
    Left  err  -> putStrLn ("Parse error:\n" ++ err)
    Right prog -> putStrLn (pretty prog)

run (Interp file) = do
  src <- readFile file
  case parseProgram src of
    Left  err  -> putStrLn ("Parse error:\n" ++ err)
    Right prog -> do
      let progMap = buildProgMap prog
      case Map.lookup "main" progMap of
        Nothing -> putStrLn "Error: no 'main' function defined in the program."
        Just fd -> do
          result <- runFunc progMap emptyState (funcBody fd)
          case result of
            Left  err          -> putStrLn ("Runtime error: " ++ err)
            Right (FReturn vs) -> putStrLn ("Result: " ++ show vs)
            Right FNormal      -> putStrLn "Program finished (no RETURN statement)."

run (Wat file) = do
  src <- readFile file
  case parseProgram src of
    Left  err  -> putStrLn ("Parse error:\n" ++ err)
    Right prog ->
      case irToWAT prog of
        Left  err -> putStrLn ("WAT codegen error:\n" ++ err)
        Right m   -> do
          let outFile = replaceExtension file ".wat"
          writeFile outFile (pretty m)
          putStrLn ("WAT written to " ++ outFile)

run (X86 file) = do
  src <- readFile file
  case parseProgram src of
    Left  err  -> putStrLn ("Parse error:\n" ++ err)
    Right prog -> do
      let outFile = replaceExtension file ".s"
      writeFile outFile (pretty (irToX86 prog))
      putStrLn ("X86-64 assembly written to " ++ outFile)

run (OptFold     file) = runOpt file optFold
run (OptProp     file) = runOpt file optProp
run (OptFoldProp file) = runOpt file optFoldProp
run (OptCSE      file) = runOpt file optCSE
run (OptDCE      file) = runOpt file optDCE
run (OptLICM     file) = runOpt file optLICM
run (OptUnroll k file) = runOpt file (optUnrollN k)
run (OptFusion   file) = runOpt file optFusion
run (OptTCO      file) = runOpt file tcoProgram
run (OptInline   file) = runOpt file (inlineProgram defaultInlineConfig)
run (OptAll      file) = runOpt file optAll

runOpt :: FilePath -> (Program -> Program) -> IO ()
runOpt file opt = do
  src <- readFile file
  case parseProgram src of
    Left  err  -> putStrLn ("Parse error:\n" ++ err)
    Right prog -> putStrLn (pretty (opt prog))
