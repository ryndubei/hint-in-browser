module HintInBrowser (runHintInBrowser) where

import Language.Haskell.Interpreter
import Language.Haskell.Interpreter.Unsafe
import Control.Exception
import System.IO

foreign export javascript "run_hint_in_browser" runHintInBrowser :: IO ()

runHintInBrowser :: IO ()
runHintInBrowser = do
  res <- unsafeRunInterpreterWithArgs ["-package-env", "/tmp/ghc_env"] $ do
    setImports ["Prelude"]
    interpret "'x'" (error "witness" :: Char)
  print res
