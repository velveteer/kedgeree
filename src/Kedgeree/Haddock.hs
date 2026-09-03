{-# LANGUAGE OverloadedStrings #-}

-- | Every assumption about Haddock's HTML: the ids, classes and tag shapes
-- the rewriting matches on. Update here when Haddock's markup changes. Golden
-- tests under @test/@ pin the output for Haddock 2.33. Browser-side
-- counterparts: @assets/kedgeree.js@, @assets/kedgeree.css@.
module Kedgeree.Haddock
  ( -- * Page classification
    PageKind (..)
  , classify
  , isPackagePage
  , extractPackage

    -- * The @\<head>@
  , mainStylesheets
  , sourceStylesheets
  , googleFontsHost
  , usesMathJax
  , isMathJaxScript
  , moduleInfoSelector

    -- * Landmarks
  , packageHeaderId
  , pageMenuId
  , moduleHeaderId
  , interfaceId
  , contentsListId
  , sectionIdPrefix
  , idAttr

    -- * Classes
  , captionClass
  , topClass
  , defClass
  , sourceLinkClass
  , selfLinkClass

    -- * Declaration markup
  , srcParagraphOpen
  , srcCellOpen
  , srcDfnOpen
  , argumentsOpen
  , rightEdgeOpen
  , hasInstances
  , noidAnchor
  ) where

import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T

-- | How a page was classified (also drives which stylesheet it gets).
data PageKind = PageMain | PageSource | PageSkipped
  deriving (Eq, Show)

-- | Source page: no package header, has @hs-*@ token spans. Else main.
classify :: Text -> PageKind
classify t
  | isPackagePage t = PageMain
  | "class=\"hs-" `T.isInfixOf` t = PageSource
  | otherwise = PageMain

-- | Has Haddock's package header (every contents and module page).
isPackagePage :: Text -> Bool
isPackagePage = T.isInfixOf packageHeaderId

-- | Package id (@name-version@) from a contents page: the first @.caption@
-- whose text, before any @": synopsis"@, has that shape. Covers
-- @\<p class="caption">text-2.1</p>@ (@--hackage@) and
-- @\<span class="caption">text-2.1: synopsis</span>@.
extractPackage :: Text -> Maybe Text
extractPackage html =
  find isPackageId (map captionText (drop 1 (T.splitOn ("class=\"" <> captionClass <> "\">") html)))
  where
    captionText = T.strip . fst . T.breakOn ": " . T.takeWhile (/= '<')
    -- Numeric version, no @<>"@ (the value lands in an attribute).
    isPackageId s = case T.breakOnEnd "-" s of
      (name, ver) ->
        not (T.null name)
          && not (T.null ver)
          && T.all (`elem` ("0123456789." :: String)) ver
          && T.all (`notElem` ("<>\"" :: String)) name

-- | The stylesheets Haddock links from a main page. Kedgeree replaces them.
mainStylesheets :: [Text]
mainStylesheets = ["linuwial.css", "quick-jump.css"]

-- | The stylesheet Haddock links from a hyperlinked-source page.
sourceStylesheets :: [Text]
sourceStylesheets = ["style.css"]

-- | Haddock links its web font from here. Kedgeree self-hosts fonts instead.
googleFontsHost :: Text
googleFontsHost = "fonts.googleapis.com"

-- | Page has math (Haddock wraps it in @class="mathjax"@).
usesMathJax :: Text -> Bool
usesMathJax = T.isInfixOf "class=\"mathjax\""

-- | Haddock's MathJax loader (@src@ matched case-insensitively) or its inline
-- @x-mathjax-config@ block.
isMathJaxScript :: Text -> Bool
isMathJaxScript tag =
  ("src" `T.isInfixOf` tag && "mathjax" `T.isInfixOf` low)
    || "x-mathjax-config" `T.isInfixOf` low
  where
    low = T.toLower tag

-- | Module-info badge (Safe Haskell, Language, Extensions) selector.
moduleInfoSelector :: Text
moduleInfoSelector = "table.info"

-- | The top bar of every main page, holding the package caption and @#page-menu@.
packageHeaderId :: Text
packageHeaderId = "package-header"

-- | The header's cross-page nav list (Source, Contents, Index, ...).
pageMenuId :: Text
pageMenuId = "page-menu"

-- | A module page's title block.
moduleHeaderId :: Text
moduleHeaderId = "module-header"

-- | A module page's declarations.
interfaceId :: Text
interfaceId = "interface"

-- | A module page's in-page table of contents.
contentsListId :: Text
contentsListId = "contents-list"

-- | Section anchors inside @#interface@ are @\<a id="g:N">@.
sectionIdPrefix :: Text
sectionIdPrefix = "g:"

-- | The attribute text @id="..."@ for an id, for use as a text anchor.
idAttr :: Text -> Text
idAttr i = "id=\"" <> i <> "\""

-- | Captions: the package id on a contents page, a module's name in its header.
captionClass :: Text
captionClass = "caption"

-- | A top-level declaration box inside @#interface@.
topClass :: Text
topClass = "top"

-- | The defined name inside a declaration's signature, an @\<a id=...>@.
defClass :: Text
defClass = "def"

-- | A declaration's \"Source\" link (needs @--hyperlinked-source@).
sourceLinkClass :: Text
sourceLinkClass = "link"

-- | A declaration's @#@ permalink.
selfLinkClass :: Text
selfLinkClass = "selflink"

-- | A top-level declaration's signature line.
srcParagraphOpen :: Text
srcParagraphOpen = "<p class=\"src\">"

-- | A constructor's, method's or argument's signature cell.
srcCellOpen :: Text
srcCellOpen = "<td class=\"src\">"

-- | A record field's signature.
srcDfnOpen :: Text
srcDfnOpen = "<dfn class=\"src\">"

-- | The per-argument documentation table under an argument-documented function.
argumentsOpen :: Text
argumentsOpen = "<div class=\"subs arguments\">"

-- | The trailing spacer Haddock puts at the end of a signature line.
rightEdgeOpen :: Text
rightEdgeOpen = "<span class=\"rightedge\""

-- | Does the page have any instance lists? Their toggles are
-- @data-details-id="i:..."@.
hasInstances :: Text -> Bool
hasInstances = T.isInfixOf "data-details-id=\"i:"

-- | Id Haddock stamps on every unnamed collapsible section, never incremented.
noidAnchor :: Text
noidAnchor = "ch:noid:0"
