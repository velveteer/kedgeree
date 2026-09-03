{-# LANGUAGE OverloadedStrings #-}

-- | Server-rendered chrome: header (menu, brand, search, theme toggle), the
-- Instances control in the header nav, and the sidebar. kedgeree.js only wires
-- behavior. Every element carries the 'marker'.
module Kedgeree.Chrome
  ( injectHeaderChrome
  , injectInstancesControl
  , injectSidebar
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import qualified Kedgeree.Haddock as Haddock
import Kedgeree.Html
import Kedgeree.Inject (marker)
import Kedgeree.Sidebar (renderSidebar)

-- | Insert the header chrome at the start of @#package-header@.
injectHeaderChrome :: Maybe Text -> Text -> Text
injectHeaderChrome mpkg = insertAfterTag (Haddock.idAttr Haddock.packageHeaderId) (headerChrome brand)
  where
    brand = case mpkg of
      Just pkg | not (T.null (T.strip pkg)) -> pkg
      _ -> "Documentation"

-- | Button icons are CSS masks (@assets/icons/*.svg@).
headerChrome :: Text -> Text
headerChrome brand =
  T.concat
    [ "<button type=\"button\" class=\"kg-iconbtn kg-menu-toggle\""
    , " title=\"Toggle navigation\" aria-label=\"Toggle navigation\" "
    , marker
    , "=\"menu\"></button>"
    , "<a class=\"kg-brand\" href=\"index.html\" "
    , marker
    , "=\"brand\">"
    , "<span class=\"kg-lambda\" aria-hidden=\"true\">&#955;</span>"
    , "<span>"
    , htmlEscape brand
    , "</span></a>"
    , "<div class=\"kg-actions\" "
    , marker
    , "=\"actions\">"
    , "<button type=\"button\" class=\"kg-search\" title=\"Search (press / )\">"
    , "<span class=\"kg-search-label\">Search&#8230;</span><kbd>/</kbd></button>"
    , "<button type=\"button\" class=\"kg-iconbtn kg-theme\""
    , " title=\"Toggle color theme\" aria-label=\"Toggle color theme\"></button>"
    , "</div>"
    ]

-- | Add the Instances dropdown to @#page-menu@ when @source@ (the plain page)
-- has instances. kedgeree.js drops Haddock's late one.
injectInstancesControl :: Text -> Text -> Text
injectInstancesControl source
  | Haddock.hasInstances source = insertAfterTag (Haddock.idAttr Haddock.pageMenuId) instancesControl
  | otherwise = id

-- | Native @\<details>@. No fragment @\<a>@, so kedgeree.js's filter keeps it.
instancesControl :: Text
instancesControl =
  T.concat
    [ "<li "
    , marker
    , "=\"instances\">"
    , "<details class=\"kg-instances\"><summary>Instances</summary>"
    , "<ul class=\"kg-instances-menu\">"
    , "<li><button type=\"button\" data-inst=\"open\">Expand all instances</button></li>"
    , "<li><button type=\"button\" data-inst=\"close\">Collapse all instances</button></li>"
    , "</ul></details></li>"
    ]

-- | Append the sidebar (rendered from the plain page @source@) to @\<body>@
-- and set @kg-has-sidebar@, plus @kg-sidebar-min@ for the minimal kind.
injectSidebar :: Text -> Text -> Text
injectSidebar source html = case renderSidebar source of
  Just (nav, rich) ->
    addBodyClass "kg-has-sidebar" $
      (if rich then id else addBodyClass "kg-sidebar-min") (insertBeforeClose "</body>" nav html)
  Nothing -> html
