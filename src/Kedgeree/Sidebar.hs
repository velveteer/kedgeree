{-# LANGUAGE OverloadedStrings #-}

-- | Server-side rendering of the sidebar nav, so it is present at first paint.
-- Parsed with tagsoup, emitted with lucid, using the classes kedgeree.css and
-- the scroll-spy expect.
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

import qualified Kedgeree.Haddock as Haddock

-- | The sidebar for a page and whether it is /rich/ (a module page:
-- declarations grouped under the contents tree) rather than /minimal/ (the
-- cross-page links only). 'Nothing' when the page warrants no sidebar.
renderSidebar :: Text -> Maybe (Text, Bool)
renderSidebar html
  | hasInterface = Just (render True, True)
  | not (null pageLinks) = Just (render False, False)
  | otherwise = Nothing
  where
    tags = parseTags html
    hasInterface = any (hasId Haddock.interfaceId) tags
    hasModuleHeader = any (hasId Haddock.moduleHeaderId) tags
    hasContents = any (hasId Haddock.contentsListId) tags

    -- (section id, title) from #contents-list, nesting flattened.
    tocSections =
      [ (sid, T.strip (anchorText rest))
      | TagOpen "a" as : rest <- tails (within Haddock.contentsListId "div" tags)
      , Just sid <- [lookup "href" as >>= T.stripPrefix "#"]
      ]

    -- Top-level declaration of each .top, keyed by the section it follows.
    decls = collectDecls (dropWhile (not . hasId Haddock.interfaceId) tags)
    bySection :: Map Text [(Text, Text)]
    bySection = Map.fromListWith (flip (<>)) [(sec, [link]) | (sec, link) <- decls]
    orphans = Map.findWithDefault [] "" bySection

    -- Non-fragment links from #page-menu.
    pageLinks =
      [ (href, T.strip (anchorText rest))
      | TagOpen "a" as : rest <- tails (within Haddock.pageMenuId "ul" tags)
      , Just href <- [lookup "href" as]
      , not ("#" `T.isPrefixOf` href)
      ]

    heading = firstNonEmpty [captionOf Haddock.moduleHeaderId tags, titleQualifier tags, "Contents"]
    homeHref = if hasModuleHeader then "#" <> Haddock.moduleHeaderId else "index.html"

    render :: Bool -> Text
    render rich = TL.toStrict . renderText
      $ nav_
        [ id_ "kg-sidebar"
        , makeAttributes "data-kedgeree" "sidebar"
        , makeAttributes "aria-label" "Documentation navigation"
        ]
      $ do
        a_ [class_ "kg-sb-home", href_ homeHref] (strong_ (toHtml heading))
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

-- | Walk @#interface@ tracking the current @g:@ section. Yields
-- @(section, (id, name))@ for the first @a.def[id]@ of each @.top@.
collectDecls :: [Tag Text] -> [(Text, (Text, Text))]
collectDecls = go "" False
  where
    go _ _ (TagOpen "a" as : rest)
      | Just gid <- lookup "id" as, Haddock.sectionIdPrefix `T.isPrefixOf` gid = go gid False rest
    go sec _ (TagOpen "div" as : rest)
      | hasClass Haddock.topClass as = go sec True rest
    go sec True (TagOpen "a" as : rest)
      | hasClass Haddock.defClass as
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

-- | Inner text of an anchor, up to its @</a>@.
anchorText :: [Tag Text] -> Text
anchorText = innerText . takeWhile (not . isClose "a")

-- | Tags strictly after the first tag matching the predicate.
after :: (Tag Text -> Bool) -> [Tag Text] -> [Tag Text]
after p = drop 1 . dropWhile (not . p)

-- | Tags inside the element with the given id, up to its balancing close.
-- Nested elements of the same tag name are accounted for.
within :: Text -> Text -> [Tag Text] -> [Tag Text]
within i tag = balanced (0 :: Int) . after (hasId i)
  where
    balanced _ [] = []
    balanced d (t : ts)
      | isClose tag t = if d == 0 then [] else t : balanced (d - 1) ts
      | isOpen tag t = t : balanced (d + 1) ts
      | otherwise = t : balanced d ts

-- | Text of the first @.caption@ inside the element with the given id.
captionOf :: Text -> [Tag Text] -> Text
captionOf i tags =
  case dropWhile (not . isCaption) (after (hasId i) tags) of
    (_ : rest) -> T.strip (innerText (takeWhile (not . isClose "p") rest))
    [] -> ""
  where
    isCaption (TagOpen _ as) = hasClass Haddock.captionClass as
    isCaption _ = False

-- | @Qualifier@ from @\<title>pkg (Qualifier)\</title>@, e.g. \"Index\".
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
