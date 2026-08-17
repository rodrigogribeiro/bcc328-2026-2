module Main (main) where

import Test.Tasty

import qualified Parsing.CYK.Tests as CYK
import qualified Parsing.LL.Tests  as LL
import qualified Parsing.LR.Tests  as LR

main :: IO ()
main = defaultMain $ testGroup "bcc328"
    [ LL.tests
    , CYK.tests
    , LR.tests
    ]
