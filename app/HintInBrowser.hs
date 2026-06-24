module HintInBrowser (runHintInBrowser) where

foreign export javascript "run_hint_in_browser" runHintInBrowser :: IO ()

runHintInBrowser :: IO ()
runHintInBrowser = putStrLn "Hello, Haskell!"
