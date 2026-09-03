{-# LANGUAGE OverloadedStrings #-}

-- | Theme a directory tree of Haddock HTML in place: write the shared assets,
-- rewrite every page concurrently, optionally write a landing page.
module Kedgeree.Process
  ( Options (..)
  , run
  ) where

import Control.Concurrent (getNumCapabilities)
import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent.MVar (modifyMVar_, newMVar)
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Exception (bracket_)
import Control.Monad (forM, join, when)
import qualified Data.ByteString as BS
import Data.Foldable (for_)
import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , pathIsSymbolicLink
  )
import System.FilePath (equalFilePath, takeDirectory, takeExtension, (</>))
import System.IO (hFlush, hIsTerminalDevice, hPutStr, hPutStrLn, stderr)

import Kedgeree.Assets (assetDirName, assetPrefix, assets)
import Kedgeree.Haddock (PageKind (..), classify, extractPackage)
import Kedgeree.Inject (Inject (..))
import Kedgeree.Landing (Landing (..), writeLanding)
import Kedgeree.Rewrite (rewriteMain, rewriteSource)

-- | Command-line options.
data Options = Options
  { optDir :: FilePath
  -- ^ root of the Haddock HTML tree
  , optDefaultTheme :: Text
  -- ^ @"auto"@ / @"light"@ / @"dark"@
  , optAccent :: Maybe Text
  , optFont :: Maybe Text
  , optMono :: Maybe Text
  , optNoSource :: Bool
  -- ^ skip hyperlinked-source pages
  , optHideModuleInfo :: Bool
  , optForce :: Bool
  -- ^ re-theme pages already at this version
  , optLanding :: Maybe Text
  -- ^ landing page title, when one is wanted
  , optPackages :: [Text]
  -- ^ landing package list and order. Empty: discover all
  , optProjectRoot :: Maybe FilePath
  , optLandingDescription :: Maybe Text
  }

-- | Theme @optDir@ and everything beneath it.
run :: Options -> IO ()
run opts = do
  let dir = optDir opts
  ok <- doesDirectoryExist dir
  if not ok
    then hPutStrLn stderr $ "kedgeree: not a directory: " <> dir
    else do
      let inj =
            Inject
              { injDefaultTheme = optDefaultTheme opts
              , injAccent = optAccent opts
              , injFont = optFont opts
              , injMono = optMono opts
              , injHideModuleInfo = optHideModuleInfo opts
              , injForce = optForce opts
              }
      pages0 <- findHtml dir
      -- The landing page replaces the root index.html wholesale.
      let pages = case optLanding opts of
            Just _ -> filter (not . equalFilePath (dir </> "index.html")) pages0
            Nothing -> pages0

      mapM_ (writeAsset (dir </> assetDirName)) assets

      -- Package id per directory, from its index.html, for the header brand.
      pkgByDir <- mapM (\d -> (,) d <$> packageFor d) (nub (map takeDirectory pages))
      let pkgOf p = join (lookup (takeDirectory p) pkgByDir)

      caps <- getNumCapabilities
      results <-
        withProgress (length pages) $ \tick ->
          pooledMapConcurrently
            (max 4 (caps * 2))
            (\p -> rewritePage opts inj (assetPrefix dir p) (pkgOf p) p <* tick)
            pages

      let written = [kind | (kind, True) <- results]
          mains = length (filter (== PageMain) written)
          srcs = length (filter (== PageSource) written)
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

      for_ (optLanding opts) $ \title ->
        writeLanding
          inj
          Landing
            { landingDir = dir
            , landingTitle = title
            , landingDescription = optLandingDescription opts
            , landingPackages = optPackages opts
            , landingProjectRoot = optProjectRoot opts
            }

-- | Run an action with a @tick@ that redraws a @n/total@ counter on stderr.
-- Only when stderr is a terminal. The cursor is hidden while drawing and the
-- line erased afterwards, even on exception. Thread-safe.
withProgress :: Int -> (IO () -> IO a) -> IO a
withProgress total body = do
  isTty <- hIsTerminalDevice stderr
  done <- newMVar (0 :: Int)
  let tick = when isTty $ modifyMVar_ done $ \k -> do
        let n = k + 1
        hPutStr stderr ("\rkedgeree: theming " <> show n <> "/" <> show total <> " pages")
        hFlush stderr
        pure n
  bracket_
    (when isTty $ hPutStr stderr "\ESC[?25l" >> hFlush stderr)
    (when isTty $ hPutStr stderr "\r\ESC[K\ESC[?25h" >> hFlush stderr)
    (body tick)

-- | 'mapConcurrently' with at most @n@ actions in flight.
pooledMapConcurrently :: Int -> (a -> IO b) -> [a] -> IO [b]
pooledMapConcurrently n f xs = do
  sem <- newQSem n
  mapConcurrently (bracket_ (waitQSem sem) (signalQSem sem) . f) xs

-- | Read, classify, rewrite and (if changed) write back one page. Returns the
-- kind and whether the file was written.
rewritePage :: Options -> Inject -> Text -> Maybe Text -> FilePath -> IO (PageKind, Bool)
rewritePage opts inj prefix mpkg path = do
  bytes <- BS.readFile path
  case TE.decodeUtf8' bytes of
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
                _ -> rewriteMain prefix inj mpkg original
              changed = themed /= original
          when changed $ BS.writeFile path (TE.encodeUtf8 themed)
          pure (kind, changed)

-- | The package id advertised by a directory's @index.html@, if any.
packageFor :: FilePath -> IO (Maybe Text)
packageFor d = do
  let idx = d </> "index.html"
  exists <- doesFileExist idx
  if not exists
    then pure Nothing
    else either (const Nothing) extractPackage . TE.decodeUtf8' <$> BS.readFile idx

-- | Write one embedded asset under @base@.
writeAsset :: FilePath -> (FilePath, BS.ByteString) -> IO ()
writeAsset base (path, bytes) = do
  let dest = base </> path
  createDirectoryIfMissing True (takeDirectory dest)
  BS.writeFile dest bytes

-- | Every @.html@ at or below @dir@. Symlinks are not followed.
findHtml :: FilePath -> IO [FilePath]
findHtml dir = do
  entries <- listDirectory dir
  fmap concat . forM entries $ \e -> do
    let p = dir </> e
    isSym <- pathIsSymbolicLink p
    isDir <- if isSym then pure False else doesDirectoryExist p
    if isDir
      then findHtml p
      else pure [p | not isSym, takeExtension e == ".html"]
