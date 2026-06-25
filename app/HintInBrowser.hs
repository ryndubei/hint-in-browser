module HintInBrowser (runHintInBrowser) where

import Language.Haskell.Interpreter
import Language.Haskell.Interpreter.Unsafe
import qualified Data.Vector as V

foreign export javascript "run_hint_in_browser" runHintInBrowser :: IO ()

runHintInBrowser :: IO ()
runHintInBrowser = do
  res <- unsafeRunInterpreterWithArgs ["-package-env", "/tmp/ghc_env"] $ do
    setImportsF
      [ ModuleImport "Prelude" NotQualified NoImportList
      , ModuleImport "Data.Vector" (QualifiedAs (Just "V")) NoImportList
      , ModuleImport "Data.Vector" NotQualified (ImportList ["Vector"])
      ]
    interpret "V.fromList [1,2,3]" (error "witness" :: V.Vector Int)
  print res
