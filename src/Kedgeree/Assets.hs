{-# LANGUAGE TemplateHaskell #-}

-- | The theme assets (CSS / JS / SVG), embedded into the binary at build
-- time so that @kedgeree@ is a single self-contained executable with no
-- runtime asset-path lookup.
module Kedgeree.Assets
  ( assets
  ) where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedDir)

-- | Every file under @assets/@, as @(relative-path, contents)@ pairs.
assets :: [(FilePath, ByteString)]
assets = $(embedDir "assets")
