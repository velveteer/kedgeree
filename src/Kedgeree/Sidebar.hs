{-# LANGUAGE OverloadedStrings #-}

-- | Render kedgeree.js's sidebar nav server-side, so it is present at the
-- browser's first paint instead of being built from the DOM after load. We parse
-- the page with tagsoup and emit the same structure (and the classes the CSS and
-- scroll-spy expect) with lucid.
--
-- 'renderSidebar' covers both kinds of sidebar the script used to build: the
-- /rich/ one on a module page (declarations grouped under the contents tree) and
-- the /minimal/ drawer elsewhere (just the cross-page links). It returns the nav
-- and whether it is rich. 'Nothing' means the page warrants no sidebar at all.
module Kedgeree.Sidebar (renderSidebar) where

import Control.Monad (unless, when)
import Data.Foldable (for_, traverse_)
import Data.List (tails)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Lucid hiding (for_)
import Lucid.Base (makeAttributes)
import Text.HTML.TagSoup

renderSidebar :: Text -> Maybe (Text, Bool)
renderSidebar html
  | hasInterface = Just (render True, True)
  | not (null pageLinks) = Just (render False, False)
  | otherwise = Nothing
  where
    tags = parseTags html
    hasInterface = any (hasId "interface") tags
    hasModuleHeader = any (hasId "module-header") tags
    hasContents = any (hasId "contents-list") tags

    -- Sections and their titles, from the in-page contents list. Nesting is
    -- flattened into one level. The links and grouping are unaffected.
    tocSections =
      [ (sid, T.strip (anchorText rest))
      | TagOpen "a" as : rest <- tails (within "contents-list" "div" tags)
      , Just sid <- [lookup "href" as >>= T.stripPrefix "#"]
      ]

    -- The top-level declaration of each @.top@, under the section it follows.
    decls = collectDecls (dropWhile (not . hasId "interface") tags)
    bySection :: Map Text [(Text, Text)]
    bySection = Map.fromListWith (flip (<>)) [(sec, [link]) | (sec, link) <- decls]
    orphans = Map.findWithDefault [] "" bySection

    pageLinks =
      [ (href, T.strip (anchorText rest))
      | TagOpen "a" as : rest <- tails (within "page-menu" "ul" tags)
      , Just href <- [lookup "href" as]
      , not ("#" `T.isPrefixOf` href)
      ]

    heading = firstNonEmpty [captionOf "module-header" tags, titleQualifier tags, "Contents"]
    homeHref = if hasModuleHeader then "#module-header" else "index.html"

    render :: Bool -> Text
    render rich = TL.toStrict . renderText
      $ nav_
        [ id_ "kg-sidebar"
        , makeAttributes "data-kedgeree" "sidebar"
        , makeAttributes "aria-label" "Documentation navigation"
        ]
      $ do
        a_ [class_ "kg-sb-home", href_ homeHref] $
          toHtmlRaw lambda <> " " <> strong_ (toHtml heading)
        when rich body
        unless (null pageLinks) $ do
          sbTitle "Page"
          ul_ [class_ "kg-sb-sub"] (for_ pageLinks (\(h, t) -> li_ (a_ [href_ h] (toHtml t))))

    body :: Html ()
    body
      | hasContents = do
          sbTitle "Contents"
          subList orphans
          ul_ [class_ "kg-sb-contents"] $
            for_ tocSections $ \(sid, secTitle) -> li_ $ do
              a_ [href_ ("#" <> sid)] (toHtml secTitle)
              subList (Map.findWithDefault [] sid bySection)
      | otherwise = do
          sbTitle "Declarations"
          ul_ [class_ "kg-sb-sub"] (traverse_ declLi [link | (_, link) <- decls])

    sbTitle :: Text -> Html ()
    sbTitle = div_ [class_ "kg-sb-title"] . toHtml

    subList :: [(Text, Text)] -> Html ()
    subList ds = unless (null ds) (ul_ [class_ "kg-sb-sub"] (traverse_ declLi ds))

    declLi :: (Text, Text) -> Html ()
    declLi (did, name) = li_ (a_ [href_ ("#" <> did)] (toHtml name))

lambda :: Text
lambda = "<span class=\"kg-lambda\" aria-hidden=\"true\">&#955;</span>"

-- | Walk @#interface@ in order, carrying the current section, and take the
-- top-level declaration name of each @.top@ (its first @a.def@). The same set as
-- the @#interface .top > .src a.def[id]@ selector.
collectDecls :: [Tag Text] -> [(Text, (Text, Text))]
collectDecls = go "" False
  where
    go _ _ (TagOpen "a" as : rest)
      | Just gid <- lookup "id" as, "g:" `T.isPrefixOf` gid = go gid False rest
    go sec _ (TagOpen "div" as : rest)
      | hasClass "top" as = go sec True rest
    go sec True (TagOpen "a" as : rest)
      | hasClass "def" as
      , Just did <- lookup "id" as =
          (sec, (did, T.strip (anchorText rest))) : go sec False rest
    go sec inTop (_ : rest) = go sec inTop rest
    go _ _ [] = []

-- tagsoup helpers ------------------------------------------------------------

hasId :: Text -> Tag Text -> Bool
hasId i (TagOpen _ as) = lookup "id" as == Just i
hasId _ _ = False

hasClass :: Text -> [Attribute Text] -> Bool
hasClass c as = maybe False ((c `elem`) . T.words) (lookup "class" as)

isOpen, isClose :: Text -> Tag Text -> Bool
isOpen n (TagOpen n' _) = n == n'
isOpen _ _ = False
isClose n (TagClose n') = n == n'
isClose _ _ = False

-- | The inner text of an anchor, everything up to its @</a>@.
anchorText :: [Tag Text] -> Text
anchorText = innerText . takeWhile (not . isClose "a")

-- | Tags strictly after the first opening tag matching the predicate.
after :: (Tag Text -> Bool) -> [Tag Text] -> [Tag Text]
after p = drop 1 . dropWhile (not . p)

-- | Tags inside the element with the given id, up to the first matching close.
within :: Text -> Text -> [Tag Text] -> [Tag Text]
within i tag = takeWhile (not . isClose tag) . after (hasId i)

-- | The text of the first @.caption@ inside the element with the given id.
captionOf :: Text -> [Tag Text] -> Text
captionOf i tags =
  case dropWhile (not . isCaption) (after (hasId i) tags) of
    (_ : rest) -> T.strip (innerText (takeWhile (not . isClose "p") rest))
    [] -> ""
  where
    isCaption (TagOpen _ as) = hasClass "caption" as
    isCaption _ = False

-- | The qualifier from a @\<title>pkg (Qualifier)\</title>@, e.g. \"Index\".
titleQualifier :: [Tag Text] -> Text
titleQualifier tags =
  case T.breakOnEnd "(" (innerText (within' "title")) of
    (before, after')
      | not (T.null before), Just q <- T.stripSuffix ")" (T.strip after') -> T.strip q
    _ -> ""
  where
    within' tag = takeWhile (not . isClose tag) (after (isOpen tag) tags)

firstNonEmpty :: [Text] -> Text
firstNonEmpty = T.concat . take 1 . filter (not . T.null . T.strip)
