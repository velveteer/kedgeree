{-# LANGUAGE OverloadedStrings #-}

-- | Pure rewriting of a Haddock page into a themed one.
module Kedgeree.Rewrite
  ( rewriteMain
  , rewriteSource
  , dedupeNoids
  ) where

import Data.Function ((&))
import Data.Text (Text)
import qualified Data.Text as T

import Kedgeree.Chrome
import qualified Kedgeree.Haddock as Haddock
import Kedgeree.Inject
import Kedgeree.Signature (wrapSignatures)

-- | Theme a module, contents or index page. @prefix@ is the relative path to
-- the shared asset directory, @mpkg@ the package id for the header brand.
-- Returns the input unchanged when already themed by this version.
rewriteMain :: Text -> Inject -> Maybe Text -> Text -> Text
rewriteMain prefix inj mpkg html
  | upToDate inj html = html
  | otherwise =
      cleared
        & rewriteHead Haddock.mainStylesheets (mainHead prefix inj)
        & injectHeaderChrome mpkg
        & injectSidebar cleared
        & injectInstancesControl cleared
        & wrapSignatures
        & dedupeNoids
        & maybe id injectPackageMeta mpkg
  where
    cleared = clearInjection html

-- | Theme a hyperlinked-source page (under @src/@).
rewriteSource :: Text -> Inject -> Text -> Text
rewriteSource prefix inj html
  | upToDate inj html = html
  | otherwise = rewriteHead Haddock.sourceStylesheets (sourceHead prefix inj) (clearInjection html)

-- | Renumber Haddock's repeated @ch:noid:0@ ids so every heading/details pair
-- is unique and toggles independently. Idempotent.
dedupeNoids :: Text -> Text
dedupeNoids html = case T.splitOn Haddock.noidAnchor html of
  (s0 : segs@(_ : _)) -> s0 <> T.concat (zipWith glue [0 :: Int ..] segs)
  _ -> html
  where
    glue k seg = "ch:noid:" <> T.pack (show (k `div` 2)) <> seg
