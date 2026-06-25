# hint-in-browser

Heavily based on Cheng Shao's [ghc-api-browser test in the GHC test suite](https://gitlab.haskell.org/ghc/ghc/-/tree/master/testsuite/tests/ghc-api-browser), but also adds cabal dependencies and an environment file listing them to the rootfs.

Not currently interactive, read `app/HintInBrowser.hs` to understand what is going on.

`hint` almost works out of the box but required a couple minor changes, hence the submodule.

### Building and runninig

The following should suffice:

```
git clone --recurse-submodules https://github.com/ryndubei/hint-in-browser
cd hint-in-browser
nix develop
npm install
npm run dev
```
