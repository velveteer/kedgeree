{-# LANGUAGE OverloadedStrings #-}

-- | The @\<head>@ injection and re-run bookkeeping. Every injected tag carries
-- 'marker'. The bootstrap also carries the version 'stamp': a page with this
-- build's stamp is up to date, anything else is cleared ('clearInjection') and
-- re-injected. The injection leads @\<head>@, ahead of MathJax.
module Kedgeree.Inject
  ( -- * Options
    Inject (..)

    -- * Marking and idempotency
  , marker
  , stamp
  , upToDate
  , clearInjection

    -- * Head rewriting
  , rewriteHead
  , mainHead
  , sourceHead
  , landingHead
  , injectPackageMeta
  ) where

import Data.Maybe (catMaybes, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Version (showVersion)

import qualified Kedgeree.Haddock as Haddock
import Kedgeree.Html
import Paths_kedgeree (version)

-- | Knobs that affect the injected markup.
data Inject = Inject
  { injDefaultTheme :: Text
  -- ^ @"auto"@, @"light"@ or @"dark"@
  , injAccent :: Maybe Text
  -- ^ optional CSS color overriding @--kg-accent@
  , injFont :: Maybe Text
  -- ^ optional font-family overriding @--kg-font@
  , injMono :: Maybe Text
  -- ^ optional monospace font-family overriding @--kg-mono@
  , injHideModuleInfo :: Bool
  -- ^ hide Haddock's module-info badge (Safe Haskell, Language, Extensions)
  , injForce :: Bool
  -- ^ re-theme even a page already carrying this build's stamp
  }

-- | Attribute on every injected tag.
marker :: Text
marker = "data-kedgeree"

-- | Version attribute on the bootstrap tag.
stamp :: Text
stamp = marker <> "-version=\"" <> T.pack (showVersion version) <> "\""

-- | Page carries this build's stamp and @--force@ is off.
upToDate :: Inject -> Text -> Bool
upToDate inj html = not (injForce inj) && stamp `T.isInfixOf` html

-- | Strip every marked element. Passes that add unmarked markup must
-- recognise their own output.
clearInjection :: Text -> Text
clearInjection html
  | marker `T.isInfixOf` html = removeElementsWithAttribute marker html
  | otherwise = html

-- | Drop the listed Haddock stylesheets and the Google Fonts link, drop or
-- defer MathJax, insert @injection@ at the start of @\<head>@.
rewriteHead :: [Text] -> Text -> Text -> Text
rewriteHead sheets injection =
  insertAfterTag "<head" injection
    . handleMathJax
    . removeTagsWhere "<link" (\tag -> any (`T.isInfixOf` tag) (Haddock.googleFontsHost : sheets))

-- | The head injection for a module, contents or index page.
mainHead :: Text -> Inject -> Text
mainHead prefix inj =
  T.concat
    [ boot inj
    , noscriptFix
    , favicon prefix
    , preloadFonts inj prefix
    , css prefix "kedgeree-tokens.css"
    , overrides inj
    , css prefix "kedgeree.css"
    , hideModuleInfo inj
    , js prefix
    ]

-- | The head injection for a hyperlinked-source page.
sourceHead :: Text -> Inject -> Text
sourceHead prefix inj =
  T.concat
    [ -- Source pages declare no charset.
      "<meta charset=\"utf-8\" " <> marker <> "=\"charset\" />"
    , boot inj
    , favicon prefix
    , preloadFonts inj prefix
    , css prefix "kedgeree-tokens.css"
    , overrides inj
    , css prefix "kedgeree-source.css"
    , js prefix
    ]

-- | The head injection for the generated landing page.
landingHead :: Text -> Inject -> Text
landingHead prefix inj =
  T.concat
    [ boot inj
    , favicon prefix
    , preloadFonts inj prefix
    , css prefix "kedgeree-tokens.css"
    , overrides inj
    , css prefix "kedgeree.css"
    , js prefix
    ]

-- | Synchronous bootstrap: sets @data-theme@ / @data-resolved@ / @data-js@ on
-- @\<html>@ before first paint. Carries the 'stamp'.
boot :: Inject -> Text
boot inj =
  T.concat
    [ "<script "
    , marker
    , "=\"boot\" "
    , stamp
    , ">(function(){try{"
    , "var k='kedgeree-theme',t=localStorage.getItem(k)||'"
    , def
    , "';"
    , "if(t!=='light'&&t!=='dark'&&t!=='auto'){t='"
    , def
    , "';}"
    , "var m=window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches;"
    , "var d=t==='dark'||(t==='auto'&&m);"
    , "var r=document.documentElement;r.setAttribute('data-theme',t);"
    , "r.setAttribute('data-resolved',d?'dark':'light');"
    , -- Stands in for Haddock's late body.js-enabled, avoiding a reflow.
      "r.setAttribute('data-js','1');"
    , "}catch(e){}})();</script>"
    ]
  where
    def = case injDefaultTheme inj of
      "light" -> "light"
      "dark" -> "dark"
      _ -> "auto"

-- | No-JS fallback: the mobile drawer needs the script, so keep the header
-- nav visible on narrow screens.
noscriptFix :: Text
noscriptFix =
  T.concat
    [ "<noscript "
    , marker
    , "=\"noscript\"><style>"
    , "@media (max-width:60rem){#" <> Haddock.packageHeaderId <> " #" <> Haddock.pageMenuId
    , "{display:flex!important;flex-wrap:wrap;}}"
    , "</style></noscript>"
    ]

-- | PNG favicon (Haddock provides none).
favicon :: Text -> Text
favicon prefix =
  T.concat
    [ "<link rel=\"icon\" type=\"image/png\" href=\""
    , prefix
    , "kedgeree-logo.png\" "
    , marker
    , "=\"icon\" />"
    ]

-- | Preload the first-paint faces (Plex Sans 400/700, JetBrains Mono 400) to
-- avoid a @font-display: swap@ flash. Skipped for an overridden family.
preloadFonts :: Inject -> Text -> Text
preloadFonts inj prefix = T.concat (map link faces)
  where
    faces =
      [f | isNothing (injFont inj), f <- ["ibm-plex-sans-400", "ibm-plex-sans-700"]]
        ++ [f | isNothing (injMono inj), f <- ["jetbrains-mono-400"]]
    link f =
      T.concat
        [ "<link rel=\"preload\" as=\"font\" type=\"font/woff2\" crossorigin href=\""
        , prefix
        , "fonts/"
        , f
        , ".woff2\" "
        , marker
        , "=\"preload\" />"
        ]

-- | Accent / font overrides as an inline @:root@ rule. Values sanitised.
overrides :: Inject -> Text
overrides inj
  | null decls = ""
  | otherwise =
      T.concat
        [ "<style "
        , marker
        , "=\"vars\">:root{"
        , T.intercalate ";" decls
        , "}</style>"
        ]
  where
    decls =
      catMaybes
        [ ("--kg-accent:" <>) . sanitizeCss <$> injAccent inj
        , ("--kg-font:" <>) . sanitizeCss <$> injFont inj
        , ("--kg-mono:" <>) . sanitizeCss <$> injMono inj
        ]

-- | Drop characters that could escape a CSS declaration.
sanitizeCss :: Text -> Text
sanitizeCss = T.filter (`notElem` ("<>{};" :: String))

-- | Hide the module-info badge. After the stylesheet, so it wins.
hideModuleInfo :: Inject -> Text
hideModuleInfo inj
  | injHideModuleInfo inj =
      T.concat ["<style ", marker, "=\"hide-info\">", Haddock.moduleInfoSelector, "{display:none}</style>"]
  | otherwise = ""

-- | Stylesheet @\<link>@ under the asset prefix.
css :: Text -> Text -> Text
css prefix href =
  T.concat
    [ "<link rel=\"stylesheet\" type=\"text/css\" href=\""
    , prefix
    , href
    , "\" "
    , marker
    , "=\"css\" />"
    ]

-- | Deferred theme script under the asset prefix.
js :: Text -> Text
js prefix =
  T.concat
    [ "<script src=\""
    , prefix
    , "kedgeree.js\" defer=\"defer\" "
    , marker
    , "=\"js\"></script>"
    ]

-- | @\<meta name="kg-package">@ at the end of @\<head>@.
injectPackageMeta :: Text -> Text -> Text
injectPackageMeta pkg =
  insertBeforeClose "</head>" $
    T.concat ["<meta name=\"kg-package\" content=\"", pkg, "\" ", marker, "=\"package\" />"]

-- | No math on the page: drop MathJax. Otherwise @defer@ the loader.
handleMathJax :: Text -> Text
handleMathJax html
  | Haddock.usesMathJax html = rewriteTags "<script" deferLoader html
  | otherwise = rewriteTags "<script" dropScript html
  where
    -- Loader and inline config block, content and close included.
    dropScript tag rest
      | Haddock.isMathJaxScript tag = ("", afterClose rest)
      | otherwise = (tag, rest)
    afterClose t = case T.breakOn "</script>" t of
      (_, rest)
        | T.null rest -> t
        | otherwise -> T.drop (T.length "</script>") rest
    -- Only the external loader (has @src@).
    deferLoader tag rest
      | "src" `T.isInfixOf` tag
      , Haddock.isMathJaxScript tag
      , not (alreadyDeferred tag) =
          (T.replace "<script" "<script defer=\"defer\"" tag, rest)
      | otherwise = (tag, rest)
    alreadyDeferred tag = "defer" `T.isInfixOf` tag || "async" `T.isInfixOf` tag
