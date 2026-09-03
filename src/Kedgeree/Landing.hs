{-# LANGUAGE OverloadedStrings #-}

-- | The @--landing@ page: a themed root @index.html@ listing the package
-- directories of a multi-package tree, with synopses read from the project's
-- @.cabal@ files.
module Kedgeree.Landing
  ( Landing (..)
  , writeLanding
  , landingPage
  , displayName

    -- * Discovery
  , discoverPackages
  , findProjectRoot
  , readSynopses
  , cabalFields
  ) where

import Control.Monad (forM)
import qualified Data.ByteString as BS
import Data.Char (isAlpha)
import Data.Foldable (traverse_)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory, makeAbsolute)
import System.FilePath (takeDirectory, takeExtension, (</>))
import System.IO (hPutStrLn, stderr)

import Kedgeree.Assets (assetDirName)
import qualified Kedgeree.Haddock as Haddock
import Kedgeree.Html (htmlEscape)
import Kedgeree.Inject (Inject, landingHead)

-- | Landing page settings.
data Landing = Landing
  { landingDir :: FilePath
  -- ^ doc tree root, receives @index.html@
  , landingTitle :: Text
  , landingDescription :: Maybe Text
  , landingPackages :: [Text]
  -- ^ package directories to list, in order. Empty: all discovered, sorted
  , landingProjectRoot :: Maybe FilePath
  -- ^ where to look for @.cabal@ synopses. @Nothing@: auto-detect
  }

-- | Write @landingDir/index.html@. Warns on stderr about requested packages
-- that do not exist.
writeLanding :: Inject -> Landing -> IO ()
writeLanding inj cfg = do
  found <- Set.fromList <$> discoverPackages dir
  selected <- case landingPackages cfg of
    [] -> pure (Set.toAscList found)
    wanted -> do
      traverse_ warnMissing (filter (`Set.notMember` found) wanted)
      pure (filter (`Set.member` found) wanted)
  case selected of
    [] -> hPutStrLn stderr $ "kedgeree: --landing: no packages found under " <> dir
    pkgs -> do
      root <- maybe (findProjectRoot dir) (pure . Just) (landingProjectRoot cfg)
      synopses <- maybe (pure Map.empty) readSynopses root
      let dest = dir </> "index.html"
          prefix = T.pack assetDirName <> "/"
          entries = [(p, Map.lookup (displayName p) synopses) | p <- pkgs]
          page = landingPage inj prefix (landingTitle cfg) (landingDescription cfg) entries
      BS.writeFile dest (TE.encodeUtf8 page)
      putStrLn $ "kedgeree: wrote landing page (" <> show (length pkgs) <> " package(s)) to " <> dest
  where
    dir = landingDir cfg
    warnMissing pkg =
      hPutStrLn stderr $ "kedgeree: --package not found under " <> dir <> ": " <> T.unpack pkg

-- | Render the landing page. @prefix@ resolves the shared assets. Each package
-- is its directory name paired with an optional synopsis.
landingPage :: Inject -> Text -> Text -> Maybe Text -> [(Text, Maybe Text)] -> Text
landingPage inj prefix title mdesc pkgs =
  T.concat
    [ "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
    , "<meta charset=\"utf-8\" />"
    , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />"
    , "<title>"
    , safeTitle
    , "</title>"
    , landingHead prefix inj
    , "\n</head>\n<body class=\"kg-landing\">\n"
    , "<header class=\"kg-landing-header\"><div class=\"kg-landing-heading\"><h1>"
    , safeTitle
    , "</h1>"
    , optional "<p class=\"kg-landing-desc\">" "</p>" mdesc
    , "</div></header>\n"
    , "<main class=\"kg-landing-main\"><ul class=\"kg-pkg-list\">"
    , foldMap item pkgs
    , "</ul></main>\n</body>\n</html>\n"
    ]
  where
    safeTitle = htmlEscape title
    -- Wrap a non-blank value in the given tags.
    optional open close = maybe "" (\v -> if T.null (T.strip v) then "" else open <> htmlEscape (T.strip v) <> close)
    item (dir, msyn) =
      T.concat
        [ "<li><a class=\"kg-pkg\" href=\""
        , htmlEscape dir
        , "/index.html\"><span class=\"kg-pkg-text\"><span class=\"kg-pkg-name\">"
        , htmlEscape (displayName dir)
        , "</span>"
        , optional "<span class=\"kg-pkg-desc\">" "</span>" msyn
        , "</span></a></li>"
        ]

-- | Directory name with a trailing numeric @-\<version>@ dropped (stack names
-- doc dirs @\<pkg>-\<version>@).
displayName :: Text -> Text
displayName dir = case T.breakOnEnd "-" dir of
  (pkg, ver)
    | not (T.null pkg)
    , not (T.null ver)
    , T.all (`elem` ("0123456789." :: String)) ver ->
        T.dropEnd 1 pkg
  _ -> dir

-- | Immediate subdirectories of @dir@ whose @index.html@ is a Haddock contents
-- page. The asset directory is skipped.
discoverPackages :: FilePath -> IO [Text]
discoverPackages dir = do
  entries <- listDirectory dir
  catMaybes <$> traverse probe entries
  where
    probe e
      | e == assetDirName = pure Nothing
      | otherwise = do
          let p = dir </> e
          isDir <- doesDirectoryExist p
          isDocs <- if isDir then isHaddockDocDir p else pure False
          pure (if isDocs then Just (T.pack e) else Nothing)

isHaddockDocDir :: FilePath -> IO Bool
isHaddockDocDir d = do
  let idx = d </> "index.html"
  exists <- doesFileExist idx
  if not exists
    then pure False
    else either (const False) Haddock.isPackagePage . TE.decodeUtf8' <$> BS.readFile idx

-- | Nearest ancestor of @start@ (inclusive) holding a @cabal.project@,
-- @stack.yaml@ or any @.cabal@ file.
findProjectRoot :: FilePath -> IO (Maybe FilePath)
findProjectRoot start = makeAbsolute start >>= go
  where
    go d = do
      here <- looksLikeRoot d
      if here
        then pure (Just d)
        else let up = takeDirectory d in if up == d then pure Nothing else go up
    looksLikeRoot d = do
      proj <- doesFileExist (d </> "cabal.project")
      stk <- doesFileExist (d </> "stack.yaml")
      cabal <- any ((== ".cabal") . takeExtension) <$> listDirectory d
      pure (proj || stk || cabal)

-- | Package @name@ to @synopsis@ for every @.cabal@ under @root@. Packages
-- without a synopsis are absent.
readSynopses :: FilePath -> IO (Map Text Text)
readSynopses root = do
  cabals <- findCabalFiles root
  Map.fromList . catMaybes <$> traverse synopsisOf cabals
  where
    synopsisOf f = do
      bytes <- BS.readFile f
      pure $ case TE.decodeUtf8' bytes of
        Left _ -> Nothing
        Right txt ->
          let fields = cabalFields txt
           in (,) <$> lookup "name" fields <*> lookup "synopsis" fields

-- | Top-level @field: value@ pairs of a @.cabal@ file, names lowercased,
-- values joined across indented continuation lines. Indented stanza fields
-- and comments are skipped. Lazy, so early fields cost only a prefix scan.
cabalFields :: Text -> [(Text, Text)]
cabalFields = collect . T.lines
  where
    collect [] = []
    collect (l : ls) = case fieldStart l of
      Just (key, value0) ->
        let (continued, rest) = span continues ls
            value = T.unwords (filter (not . T.null) (map T.strip (value0 : continued)))
         in (key, value) : collect rest
      Nothing -> collect ls

    fieldStart l
      | not (indented l)
      , (before, after) <- T.break (== ':') l
      , Just (_colon, value0) <- T.uncons after
      , let key = T.toLower (T.strip before)
      , not (T.null key)
      , T.all (\c -> isAlpha c || c == '-') key =
          Just (key, value0)
      | otherwise = Nothing

    continues l = indented l && not (T.null (T.strip l))
    indented = maybe False ((`elem` (" \t" :: String)) . fst) . T.uncons

-- | Every @.cabal@ at or below @dir@, skipping hidden directories and
-- @dist-newstyle@.
findCabalFiles :: FilePath -> IO [FilePath]
findCabalFiles dir = do
  entries <- listDirectory dir
  fmap concat . forM entries $ \e -> do
    let p = dir </> e
    isDir <- doesDirectoryExist p
    if isDir
      then if skip e then pure [] else findCabalFiles p
      else pure [p | takeExtension e == ".cabal"]
  where
    skip e = take 1 e == "." || e == "dist-newstyle"
