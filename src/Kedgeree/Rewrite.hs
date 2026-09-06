{-# LANGUAGE OverloadedStrings #-}

-- | Pure rewriting of a Haddock page into a themed one.
module Kedgeree.Rewrite
  ( rewriteMain
  , rewriteSource
  , dedupeNoids
  , promoteHeadings
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
        & promoteHeadings
        & dedupeNoids
        & maybe id injectPackageMeta mpkg
  where
    cleared = clearInjection html

-- | Theme a hyperlinked-source page (under @src/@).
rewriteSource :: Text -> Inject -> Text -> Text
rewriteSource prefix inj html
  | upToDate inj html = html
  | otherwise = rewriteHead Haddock.sourceStylesheets (sourceHead prefix inj) (clearInjection html)

-- | Give the page a heading outline. Haddock titles the module with a
-- @\<p class="caption">@ and makes every section an @\<h1>@. The caption becomes
-- the page's @\<h1>@ and the section headings (the @g:N@ anchors and the orphan
-- instances heading) become @\<h2>@. Doc-comment headings are untouched.
-- Idempotent.
promoteHeadings :: Text -> Text
promoteHeadings = demoteSections . promoteCaption
  where
    captionOpen = "<p class=\"" <> Haddock.captionClass <> "\">"
    promoteCaption html = case T.breakOn (Haddock.idAttr Haddock.moduleHeaderId) html of
      (before, rest)
        | T.null rest -> html
        | otherwise ->
            let (hdr, afterHdr) = T.breakOn "</div>" rest
                (a, b) = T.breakOn captionOpen hdr
                hdr'
                  | T.null b = hdr
                  | otherwise =
                      let (txt, close) = T.breakOn "</p>" (T.drop (T.length captionOpen) b)
                       in a <> "<h1 class=\"" <> Haddock.captionClass <> "\">" <> txt <> "</h1>" <> T.drop 4 close
             in before <> hdr' <> afterHdr

    demoteSections html = case T.splitOn "<h1>" html of
      (s0 : segs@(_ : _)) -> go s0 segs
      _ -> html
      where
        go acc [] = acc
        go acc (seg : rest)
          | sectionAnchorBefore acc || orphansAfter seg =
              let (inner, after) = T.breakOn "</h1>" seg
               in go (acc <> "<h2>" <> inner <> "</h2>" <> T.drop 5 after) rest
          | otherwise = go (acc <> "<h1>" <> seg) rest
        -- acc ends with the section's <a href="#g:N" id="g:N">.
        sectionAnchorBefore acc = case T.breakOnEnd ("<a href=\"#" <> Haddock.sectionIdPrefix) acc of
          (pre, attrs) -> not (T.null pre) && T.all (/= '<') attrs && ">" `T.isSuffixOf` attrs
        orphansAfter seg =
          ("<div " <> Haddock.idAttr Haddock.orphansId) `T.isPrefixOf` T.drop 5 (snd (T.breakOn "</h1>" seg))

-- | Renumber Haddock's repeated @ch:noid:0@ ids so every heading/details pair
-- is unique and toggles independently. Idempotent.
dedupeNoids :: Text -> Text
dedupeNoids html = case T.splitOn Haddock.noidAnchor html of
  (s0 : segs@(_ : _)) -> s0 <> T.concat (zipWith glue [0 :: Int ..] segs)
  _ -> html
  where
    glue k seg = "ch:noid:" <> T.pack (show (k `div` 2)) <> seg
