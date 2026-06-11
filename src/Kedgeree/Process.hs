{-# LANGUAGE OverloadedStrings #-}

-- | Drive a run of Kedgeree over a directory of generated Haddock HTML:
-- copy the embedded assets in, then rewrite every page in place.
--
-- The walk is recursive, so it handles both a single package's
-- @doc/html/<pkg>@ directory and a whole-project tree produced by
-- @cabal haddock-project@ (an index page plus one subdirectory per
-- package, each with its own @src/@).
module Kedgeree.Process
  ( Options (..)
  , run
  ) where

import Control.Concurrent (getNumCapabilities)
import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Exception (bracket_)
import Control.Monad (forM, join, when)
import qualified Data.ByteString as BS
import Data.List (find, nub)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , pathIsSymbolicLink
  )
import System.FilePath
  ( makeRelative
  , splitDirectories
  , takeDirectory
  , takeExtension
  , (</>)
  )
import System.IO (hPutStrLn, stderr)

import Kedgeree.Assets (assets)
import Kedgeree.Rewrite (Inject (..), marker, rewriteMain, rewriteSource)

-- | Parsed command-line options.
data Options = Options
  { optDir :: FilePath
  -- ^ root directory of generated Haddock HTML
  , optDefaultTheme :: Text
  -- ^ @"auto"@ / @"light"@ / @"dark"@
  , optAccent :: Maybe Text
  -- ^ optional accent-color override
  , optFont :: Maybe Text
  -- ^ optional UI/prose font-family override
  , optMono :: Maybe Text
  -- ^ optional monospace font-family override
  , optNoSource :: Bool
  -- ^ skip hyperlinked-source pages
  , optHideModuleInfo :: Bool
  -- ^ hide Haddock's module-info badge (Safe Haskell, Language, Extensions)
  , optForce :: Bool
  -- ^ re-theme pages already carrying this build's stamp
  }

-- | Apply the theme to @optDir@ and everything beneath it.
run :: Options -> IO ()
run opts = do
  let dir = optDir opts
  ok <- doesDirectoryExist dir
  if not ok
    then hPutStrLn stderr $ "kedgeree: not a directory: " <> dir
    else do
      let inj =
            Inject
              (optDefaultTheme opts)
              (optAccent opts)
              (optFont opts)
              (optMono opts)
              (optHideModuleInfo opts)
              (optForce opts)

      pages <- findHtml dir

      -- Files are independent, so process them on a bounded worker pool.
      caps <- getNumCapabilities
      let workers = max 4 (caps * 2)

      -- One shared copy of the asset set (CSS/JS/fonts/logo) lands under the
      -- tree root, and every page references it with a relative href computed
      -- from its depth. This avoids duplicating ~120 KB of fonts into every
      -- directory that holds HTML (a package dir, its src/, …).
      mapM_ (writeAsset (dir </> assetDirName)) assets

      let dirs = nub (map takeDirectory pages)
      -- Resolve each directory's package name (from index.html) for the navbar.
      pkgByDir <- mapM (\d -> (,) d <$> packageFor d) dirs
      let pkgOf p = join (lookup (takeDirectory p) pkgByDir)

      results <-
        pooledMapConcurrently
          workers
          (\p -> rewritePage opts inj (assetPrefix dir p) (pkgOf p) p)
          pages
      -- Count only pages we actually (re)wrote, so a no-op re-run reports
      -- honestly rather than claiming to have themed everything again.
      let writtenPages = map fst (filter snd results)
          mains = length (filter (== PageMain) writtenPages)
          srcs = length (filter (== PageSource) writtenPages)

      putStrLn $
        if mains + srcs == 0
          then "kedgeree: already up to date in " <> dir
          else
            "kedgeree: themed "
              <> show mains
              <> " page(s)"
              <> (if srcs > 0 then ", " <> show srcs <> " source page(s)" else "")
              <> " in "
              <> dir

-- | Run @f@ over every item concurrently, but with at most @n@ actions in
-- flight at once (bounding open file handles and memory). Order of results
-- matches the input.
pooledMapConcurrently :: Int -> (a -> IO b) -> [a] -> IO [b]
pooledMapConcurrently n f xs = do
  sem <- newQSem n
  mapConcurrently (\x -> bracket_ (waitQSem sem) (signalQSem sem) (f x)) xs

-- | How a page was classified (also drives which stylesheet it gets).
data PageKind = PageMain | PageSource | PageSkipped
  deriving (Eq)

-- | The shared asset directory, placed once at the tree root.
assetDirName :: FilePath
assetDirName = "kedgeree-assets"

-- | The relative href prefix from a page back to the shared asset directory:
-- @"kedgeree-assets\/"@ for a page at the root, @"..\/kedgeree-assets\/"@ one
-- level down, and so on. @root@ is the directory the assets were written under.
assetPrefix :: FilePath -> FilePath -> Text
assetPrefix root page =
  T.concat (replicate depth "../") <> T.pack assetDirName <> "/"
  where
    rel = makeRelative root (takeDirectory page)
    depth = length (filter (`notElem` [".", ""]) (splitDirectories rel))

-- | Read, classify, rewrite and (if changed) write a single page back. Returns
-- the page's classification and whether it was actually rewritten this run.
-- @prefix@ resolves the shared assets for this page. @mpkg@ is the package name
-- for this page's directory, if known.
rewritePage :: Options -> Inject -> Text -> Maybe Text -> FilePath -> IO (PageKind, Bool)
rewritePage opts inj prefix mpkg path = do
  bytes <- BS.readFile path
  case TE.decodeUtf8' bytes of
    -- A non-UTF-8 file isn't Haddock output we can theme — skip it rather than
    -- aborting the whole (concurrent) run.
    Left _ -> do
      hPutStrLn stderr $ "kedgeree: skipping (not valid UTF-8): " <> path
      pure (PageSkipped, False)
    Right original -> do
      let kind = classify original
      case kind of
        PageSource | optNoSource opts -> pure (PageSkipped, False)
        _ -> do
          let themed = case kind of
                PageSource -> rewriteSource prefix inj original
                _ -> rewriteMain prefix inj original
              rewritten = case (kind, mpkg) of
                (PageMain, Just pkg) -> injectPackageMeta pkg themed
                _ -> themed
              changed = rewritten /= original
          when changed $ BS.writeFile path (TE.encodeUtf8 rewritten)
          pure (kind, changed)

-- | The package name advertised by a directory's @index.html@ (the nested
-- module-list caption), if present.
packageFor :: FilePath -> IO (Maybe Text)
packageFor d = do
  let idx = d </> "index.html"
  exists <- doesFileExist idx
  if not exists
    then pure Nothing
    else do
      bytes <- BS.readFile idx
      pure $ either (const Nothing) extractPackage (TE.decodeUtf8' bytes)

-- | Pull the package id out of a contents page. Haddock labels the module group
-- with a @\<p class="caption">@ holding @\<pkg>-\<version>@, but the page has
-- other captions too (e.g. "Modules"), so take the first caption whose text is
-- shaped like @name-version@ rather than relying on its position.
extractPackage :: Text -> Maybe Text
extractPackage html =
  find isPackageId (map captionText (drop 1 (T.splitOn "<p class=\"caption\">" html)))
  where
    captionText = T.strip . fst . T.breakOn "</p>"
    -- A package id is @name-version@ with a numeric version, e.g. @text-2.1@.
    -- Reject @<>"@ as well, since the value is injected into a meta attribute.
    isPackageId s = case T.breakOnEnd "-" s of
      (name, ver) ->
        not (T.null name)
          && not (T.null ver)
          && T.all (`elem` ("0123456789." :: String)) ver
          && T.all (`notElem` ("<>\"" :: String)) name

-- | Record the package name in a @\<meta>@ so kedgeree.js can show it. The tag
-- carries the marker so a version-upgrade re-run strips and refreshes it like
-- every other injected element.
injectPackageMeta :: Text -> Text -> Text
injectPackageMeta pkg html
  | "kg-package" `T.isInfixOf` html = html
  | otherwise = case T.breakOn "</head>" html of
      (before, rest)
        | T.null rest -> html
        | otherwise -> before <> meta <> rest
  where
    meta =
      "<meta name=\"kg-package\" content=\""
        <> pkg
        <> "\" "
        <> marker
        <> "=\"package\" />"

-- | A page is a hyperlinked-source page when it lacks Haddock's package
-- header yet carries tokenised-source @hs-*@ spans. Everything else
-- (modules, the contents page, the index, a haddock-project landing page)
-- is treated as a main page.
classify :: Text -> PageKind
classify t
  | "package-header" `T.isInfixOf` t = PageMain
  | "class=\"hs-" `T.isInfixOf` t = PageSource
  | otherwise = PageMain

-- | Write one embedded asset under @base@, creating directories as needed.
writeAsset :: FilePath -> (FilePath, BS.ByteString) -> IO ()
writeAsset base (path, bytes) = do
  let dest = base </> path
  createDirectoryIfMissing True (takeDirectory dest)
  BS.writeFile dest bytes

-- | Every @.html@ file at or below @dir@ (recursive).
findHtml :: FilePath -> IO [FilePath]
findHtml dir = do
  entries <- listDirectory dir
  fmap concat . forM entries $ \e -> do
    let p = dir </> e
    isSym <- pathIsSymbolicLink p
    if isSym
      then pure [] -- don't follow symlinks, to avoid directory cycles
      else do
        isDir <- doesDirectoryExist p
        if isDir
          then findHtml p
          else pure [p | takeExtension e == ".html"]
