-- Constant propagation.  Re-exported from 'IR.Opt.ConstFoldProp', which
-- performs folding and propagation together in a single tree traversal.
module IR.Opt.ConstProp
  ( propProgram
  , propFuncDef
  ) where

import IR.Frontend.Syntax.IRSyntax
import IR.Opt.ConstFoldProp (foldPropProgram, foldPropFuncDef)

propProgram :: Program -> Program
propProgram = foldPropProgram

propFuncDef :: FuncDef -> FuncDef
propFuncDef = foldPropFuncDef
