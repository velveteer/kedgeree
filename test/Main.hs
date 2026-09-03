{-# LANGUAGE OverloadedStrings #-}

-- | Golden and behavioural tests for the pure HTML rewriting.
--
-- The fixtures under @test/fixtures@ are unmodified Haddock output for the
-- modules in @example/src@ (Haddock 2.33). Each golden case themes a fixture and
-- compares the result with the file of the same name under @test/golden@.
-- Run with @--accept@ to overwrite the goldens after an intentional change,
-- then review the diff with @git diff test/golden@.
module Main (main) where

import Control.Monad (unless)
import qualified Data.ByteString as BS
import Data.IORef
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath ((</>))

import Kedgeree.Haddock (PageKind (..), classify, extractPackage)
import Kedgeree.Html (addBodyClass, removeElementsWithAttribute)
import Kedgeree.Inject
import Kedgeree.Landing (cabalFields, displayName, landingPage)
import Kedgeree.Rewrite

main :: IO ()
main = do
  accept <- ("--accept" `elem`) <$> getArgs
  failures <- newIORef (0 :: Int)
  let check name ok detail = do
        putStrLn ((if ok then "ok    " else "FAIL  ") <> name)
        unless ok $ do
          modifyIORef' failures (+ 1)
          unless (null detail) (putStrLn ("      " <> detail))

  fixtures <- traverse readFixture mainFixtures
  (_, source) <- readFixture ("src" </> "Geometry.Render.html")

  -- Golden output for every fixture, themed the way `kedgeree` themes a package
  -- directory: pages at the root use "kedgeree-assets/", src/ pages one level up.
  let mains = [(name, rewriteMain "kedgeree-assets/" defaultInject (Just pkg) html) | (name, html) <- fixtures]
      src = rewriteSource "../kedgeree-assets/" defaultInject source
      opts = rewriteMain "kedgeree-assets/" customInject (Just pkg) (lookupFixture "Showcase.html" fixtures)
      landing =
        landingPage
          defaultInject
          "kedgeree-assets/"
          "My <project>"
          (Just "A one-line description.")
          [("kedgeree-demo", Just "Hand-built modules"), ("lens-5.3", Nothing), ("odd & name", Just "")]
  goldens <-
    traverse
      (golden accept)
      ( mains
          <> [ ("src-Geometry.Render.html", src)
             , ("Showcase.options.html", opts)
             , ("landing.html", landing)
             ]
      )
  mapM_ (\(name, ok, detail) -> check ("golden " <> name) ok detail) goldens

  -- Re-running on themed output must be a no-op.
  mapM_
    ( \(name, themed) -> check ("idempotent " <> name) (rewriteMain "kedgeree-assets/" defaultInject (Just pkg) themed == themed) ""
    )
    mains
  check "idempotent src" (rewriteSource "../kedgeree-assets/" defaultInject src == src) ""

  -- A page themed by an older version is re-themed to exactly the fresh output.
  mapM_
    ( \(name, themed) ->
        let stale = T.replace ("data-kedgeree-version=\"" <> currentVersion themed <> "\"") "data-kedgeree-version=\"0.0.1\"" themed
         in check ("stale re-theme " <> name) (rewriteMain "kedgeree-assets/" defaultInject (Just pkg) stale == themed) ""
    )
    mains

  -- --force on an up-to-date page reproduces the fresh output.
  mapM_
    ( \(name, themed) ->
        check
          ("force re-theme " <> name)
          (rewriteMain "kedgeree-assets/" defaultInject {injForce = True} (Just pkg) themed == themed)
          ""
    )
    mains

  -- Non-Haddock input passes through untouched.
  check "non-html passthrough" (rewriteMain "kedgeree-assets/" defaultInject Nothing "just text" == "just text") ""

  -- Haddock markup probes.
  mapM_
    (\(name, html) -> check ("classify main " <> name) (classify html == PageMain) "")
    fixtures
  check "classify source" (classify source == PageSource) ""
  check "classify plain" (classify "<html><body>hi</body></html>" == PageMain) ""
  check "extractPackage index" (extractPackage (lookupFixture "index.html" fixtures) == Just pkg) ""
  check
    "extractPackage hackage caption"
    (extractPackage "<p class=\"caption\">text-2.1</p>" == Just "text-2.1")
    ""
  check
    "extractPackage synopsis caption"
    (extractPackage "<span class=\"caption\">Modules</span><span class=\"caption\">text-2.1: Text</span>" == Just "text-2.1")
    ""
  check "extractPackage none" (isNothing (extractPackage "<span class=\"caption\">Modules</span>")) ""

  -- Html helpers.
  check "addBodyClass adds attr" (addBodyClass "x" "<body><p>" == "<body class=\"x\"><p>") ""
  check "addBodyClass merges" (addBodyClass "x" "<body class=\"a\" id=\"b\">" == "<body class=\"x a\" id=\"b\">") ""
  check "addBodyClass no dup" (addBodyClass "a" "<body class=\"a b\">" == "<body class=\"a b\">") ""
  check "addBodyClass no prefix match" (addBodyClass "a" "<body class=\"ab\">" == "<body class=\"a ab\">") ""
  check
    "removeElements nested same tag"
    ( removeElementsWithAttribute "data-k" "<ul><li data-k=\"1\"><ul><li>a</li><li>b</li></ul></li><li>keep</li></ul>"
        == "<ul><li>keep</li></ul>"
    )
    ""
  check
    "removeElements void and text"
    (removeElementsWithAttribute "data-k" "<link data-k=\"1\" href=\"x\" /><p>data-k in text</p>" == "<p>data-k in text</p>")
    ""
  check
    "removeElements li vs link"
    (removeElementsWithAttribute "data-k" "<li data-k=\"1\"><link href=\"x\">a</li><li>b</li>" == "<li>b</li>")
    ""
  check
    "dedupeNoids renumbers pairs"
    (dedupeNoids "ch:noid:0 ch:noid:0 ch:noid:0 ch:noid:0" == "ch:noid:0 ch:noid:0 ch:noid:1 ch:noid:1")
    ""
  check
    "dedupeNoids idempotent"
    (dedupeNoids (dedupeNoids "ch:noid:0 ch:noid:0 ch:noid:0") == dedupeNoids "ch:noid:0 ch:noid:0 ch:noid:0")
    ""

  -- Landing.
  check "displayName strips version" (displayName "lens-5.3.2" == "lens") ""
  check "displayName keeps plain name" (displayName "kedgeree-demo" == "kedgeree-demo") ""
  check "displayName keeps hyphenated word" (displayName "base-compat" == "base-compat") ""
  let cabal =
        T.unlines
          [ "cabal-version: 2.4"
          , "Name:          demo"
          , "-- comment"
          , "synopsis:      First line"
          , "               continued here"
          , ""
          , "library"
          , "  synopsis: not this"
          ]
  check "cabalFields name" (lookup "name" (cabalFields cabal) == Just "demo") ""
  check "cabalFields continuation" (lookup "synopsis" (cabalFields cabal) == Just "First line continued here") ""
  check "cabalFields skips stanza" (length (filter ((== "synopsis") . fst) (cabalFields cabal)) == 1) ""

  n <- readIORef failures
  unless (n == 0) $ do
    putStrLn (show n <> " failure(s)")
    exitFailure

pkg :: Text
pkg = "kedgeree-demo-0.1.0"

mainFixtures :: [FilePath]
mainFixtures = ["index.html", "doc-index.html", "Geometry.html", "Geometry-Render.html", "Showcase.html"]

defaultInject :: Inject
defaultInject =
  Inject
    { injDefaultTheme = "auto"
    , injAccent = Nothing
    , injFont = Nothing
    , injMono = Nothing
    , injHideModuleInfo = True
    , injForce = False
    }

customInject :: Inject
customInject =
  defaultInject
    { injDefaultTheme = "dark"
    , injAccent = Just "#c0ffee"
    , injFont = Just "Inter, sans-serif"
    , injMono = Just "\"Fira Code\", monospace"
    , injHideModuleInfo = False
    }

-- | The version stamped on a themed page, read back from the page itself so the
-- stale-version test does not hard-code it.
currentVersion :: Text -> Text
currentVersion themed = T.takeWhile (/= '"') (T.drop (T.length key) (snd (T.breakOn key themed)))
  where
    key = "data-kedgeree-version=\""

readFixture :: FilePath -> IO (FilePath, Text)
readFixture name = do
  bytes <- BS.readFile ("test" </> "fixtures" </> name)
  pure (name, TE.decodeUtf8 bytes)

lookupFixture :: FilePath -> [(FilePath, Text)] -> Text
lookupFixture name = fromMaybe (error ("missing fixture " <> name)) . lookup name

-- | Compare @actual@ with the golden file, writing it when accepting. Returns
-- the case name, whether it passed and a detail line for a failure.
golden :: Bool -> (FilePath, Text) -> IO (FilePath, Bool, String)
golden accept (name, actual) = do
  let path = "test" </> "golden" </> name
  exists <- doesFileExist path
  if accept || not exists
    then do
      createDirectoryIfMissing True ("test" </> "golden")
      BS.writeFile path (TE.encodeUtf8 actual)
      pure (name, True, if exists then "" else "(created)")
    else do
      expected <- TE.decodeUtf8 <$> BS.readFile path
      pure (name, expected == actual, "differs from " <> path <> " (run with --accept to update)")
