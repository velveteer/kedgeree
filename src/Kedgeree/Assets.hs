{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Theme assets (CSS, JS, fonts, icons), embedded at build time, and their
-- location in a themed tree.
module Kedgeree.Assets
  ( assets
  , assetDirName
  , assetPrefix
  ) where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedDir)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (makeRelative, splitDirectories, takeDirectory)

-- | Every file under @assets/@ as @(relative path, contents)@.
assets :: [(FilePath, ByteString)]
assets = $(embedDir "assets")

-- | The shared asset directory, written once at the tree root.
assetDirName :: FilePath
assetDirName = "kedgeree-assets"

-- | Relative href prefix from @page@ back to the asset directory under @root@:
-- @"kedgeree-assets/"@ at the root, @"../kedgeree-assets/"@ one level down.
assetPrefix :: FilePath -> FilePath -> Text
assetPrefix root page =
  T.concat (replicate depth "../") <> T.pack assetDirName <> "/"
  where
    rel = makeRelative root (takeDirectory page)
    depth = length (filter (`notElem` [".", ""]) (splitDirectories rel))
