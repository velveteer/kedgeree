{-# LANGUAGE OverloadedStrings #-}

-- | Pure HTML rewriting: given the text of a Haddock-generated page, inject
-- the Kedgeree theme assets into its @<head>@. All structural UI (sidebar,
-- search, theme toggle) is built client-side by @kedgeree.js@ — here we wire
-- in the bootstrap, stylesheet, script, favicon and a no-JS fallback.
--
-- The injection goes at the very start of @<head>@, ahead of Haddock's
-- render-blocking MathJax @<script>@ — which we also mark @defer@ — so the
-- theme and styles are resolved before first paint and the deferred
-- @kedgeree.js@ runs early enough to enhance the DOM without a flash.
--
-- Idempotency is version-aware: a page already carrying THIS build's stamp is
-- left untouched, but a page themed by a DIFFERENT version has that older
-- injection stripped and the current one applied — so upgrading Kedgeree and
-- re-running actually re-themes, rather than silently keeping stale assets.
module Kedgeree.Rewrite
  ( Inject (..)
  , rewriteMain
  , rewriteSource
  , landingPage
  , displayName
  , marker
  ) where

import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Version (showVersion)

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

-- | Attribute that brands every tag Kedgeree injects, so re-runs can locate
-- (and, on a version change, strip) them.
marker :: Text
marker = "data-kedgeree"

-- | The current build version, as text (e.g. @"0.1.0"@).
kgVersion :: Text
kgVersion = T.pack (showVersion version)

-- | The stamp identifying THIS build's injection. Stamped on the bootstrap
-- tag and used to decide whether a page is already up to date.
stamp :: Text
stamp = marker <> "-version=\"" <> kgVersion <> "\""

-- | Rewrite a top-level documentation page (module / contents / index).
-- Kedgeree owns the styling, so Haddock's own stylesheets are removed.
--
-- @prefix@ is the relative path from this page to the shared asset directory
-- (e.g. @"kedgeree-assets\/"@ at the tree root, @"..\/kedgeree-assets\/"@ one
-- level down), so a single copy of the assets serves the whole tree.
rewriteMain :: Text -> Inject -> Text -> Text
rewriteMain prefix inj html = withSidebarClass (rewrite inj sheets injection html)
  where
    sheets = ["linuwial.css", "quick-jump.css"]
    injection =
      boot inj
        <> noscriptFix
        <> favicon prefix
        <> preloadFonts inj prefix
        <> css prefix "kedgeree-tokens.css"
        <> overrides inj
        <> css prefix "kedgeree.css"
        <> hideModuleInfo inj
        <> js prefix
    -- Reserve the sidebar column up front so the page does not reflow when
    -- the script builds it. addBodyClass is itself idempotent.
    withSidebarClass h
      | "id=\"interface\"" `T.isInfixOf` h = addBodyClass "kg-has-sidebar" h
      | otherwise = h

-- | Build a standalone, themed landing page for a multi-package tree: a header
-- carrying @title@ and a grid of links, one per package, to @\<name>/index.html@.
-- It reuses the same bootstrap, stylesheets and script as a themed Haddock page,
-- so the theme, fonts and toggle behave identically. @prefix@ resolves the shared
-- assets (always @"kedgeree-assets\/"@, since the landing sits at the tree root).
-- The bootstrap stamp marks it as Kedgeree's, so a later run leaves it untouched.
-- | Render the themed landing page. @mdesc@ is an optional one-line project
-- description shown under the title. Each package is its directory name paired
-- with an optional synopsis (from its @.cabal@, if available).
landingPage :: Inject -> Text -> Text -> Maybe Text -> [(Text, Maybe Text)] -> Text
landingPage inj prefix title mdesc pkgs =
  T.concat
    [ "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
    , "<meta charset=\"utf-8\" />"
    , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />"
    , "<title>"
    , safeTitle
    , "</title>"
    , boot inj
    , favicon prefix
    , preloadFonts inj prefix
    , css prefix "kedgeree-tokens.css"
    , overrides inj
    , css prefix "kedgeree.css"
    , js prefix
    , "\n</head>\n<body class=\"kg-landing\">\n"
    , "<header class=\"kg-landing-header\"><div class=\"kg-landing-heading\"><h1>"
    , safeTitle
    , "</h1>"
    , description
    , "</div></header>\n"
    , "<main class=\"kg-landing-main\"><ul class=\"kg-pkg-list\">"
    , foldMap item pkgs
    , "</ul></main>\n</body>\n</html>\n"
    ]
  where
    safeTitle = htmlEscape title
    description = case mdesc of
      Just d | not (T.null (T.strip d)) ->
        "<p class=\"kg-landing-desc\">" <> htmlEscape (T.strip d) <> "</p>"
      _ -> ""
    item (dir, msyn) =
      T.concat
        [ "<li><a class=\"kg-pkg\" href=\""
        , htmlEscape dir
        , "/index.html\"><span class=\"kg-pkg-text\"><span class=\"kg-pkg-name\">"
        , htmlEscape (displayName dir)
        , "</span>"
        , desc
        , "</span></a></li>"
        ]
      where
        desc = case msyn of
          Just s | not (T.null (T.strip s)) ->
            "<span class=\"kg-pkg-desc\">" <> htmlEscape (T.strip s) <> "</span>"
          _ -> ""

-- | The label shown for a package directory: the directory name with a trailing
-- @-\<version>@ dropped, so a stack tree (which names dirs @\<pkg>-\<version>@)
-- reads as cleanly as a @haddock-project@ tree (which uses just @\<pkg>@). The
-- link still targets the real directory name.
displayName :: Text -> Text
displayName dir = case T.breakOnEnd "-" dir of
  (pkg, ver)
    | not (T.null pkg)
    , not (T.null ver)
    , T.all (`elem` ("0123456789." :: String)) ver ->
        T.dropEnd 1 pkg
  _ -> dir

-- | Minimal HTML-text escaping for values placed in element content / hrefs.
htmlEscape :: Text -> Text
htmlEscape =
  T.replace "\"" "&quot;"
    . T.replace ">" "&gt;"
    . T.replace "<" "&lt;"
    . T.replace "&" "&amp;"

-- | Rewrite a hyperlinked-source page. These live under @src/@. @prefix@ points
-- back up to the shared asset directory (typically @"..\/kedgeree-assets\/"@).
rewriteSource :: Text -> Inject -> Text -> Text
rewriteSource prefix inj =
  rewrite
    inj
    ["style.css"]
    -- Haddock's source pages declare no charset, so injected/unicode glyphs
    -- can mojibake — assert UTF-8.
    ( "<meta charset=\"utf-8\" "
        <> marker
        <> "=\"charset\" />"
        <> boot inj
        <> favicon prefix
        <> preloadFonts inj prefix
        <> css prefix "kedgeree-tokens.css"
        <> overrides inj
        <> css prefix "kedgeree-source.css"
        <> js prefix
    )

-- | Shared logic: skip if already at the current version — otherwise clear any
-- older Kedgeree injection, strip Haddock's stylesheets (we replace them) and
-- the Google Fonts CDN link (we self-host fonts), mark MathJax @defer@ so it
-- stops blocking the parser, and splice our injection in at the start of @<head>@.
rewrite :: Inject -> [Text] -> Text -> Text -> Text
rewrite inj sheets injection html
  -- @--force@ skips this short-circuit — the strip-and-reinject path below
  -- already cleans a previous injection, so re-theming stays idempotent.
  | not (injForce inj) && stamp `T.isInfixOf` html = html
  | otherwise = injectAfterHead injection (deferMathJax stripped)
  where
    stripped = foldr removeLinkContaining cdnStripped sheets
    cdnStripped = removeLinkContaining "fonts.googleapis.com" cleared
    -- A stale (older-version) injection is removed before re-applying.
    cleared
      | marker `T.isInfixOf` html = removeMarkedElements html
      | otherwise = html

-- | The inline bootstrap. Runs synchronously in @<head>@ so the resolved
-- theme is on @<html>@ before the browser paints — no flash of wrong theme.
-- Carries the version stamp that drives idempotency.
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
    , "}catch(e){}})();</script>"
    ]
  where
    def = case injDefaultTheme inj of
      "light" -> "light"
      "dark" -> "dark"
      _ -> "auto"

-- | With JavaScript disabled the sidebar is never built, so collapse the
-- column we reserve for it — otherwise an empty gutter would remain. We also
-- reserve the column by stamping @kg-has-sidebar@ on @\<body>@ server-side,
-- which hides Haddock's in-page table of contents (the sidebar replaces it) —
-- with no JS there is no sidebar, so restore the TOC too. @!important@ beats
-- the equally-specific hide rule in kedgeree.css regardless of source order.
noscriptFix :: Text
noscriptFix =
  T.concat
    [ "<noscript "
    , marker
    , "=\"noscript\"><style>"
    , "body.kg-has-sidebar{grid-template-columns:minmax(0,1fr);"
    , "grid-template-areas:\"header\" \"main\" \"footer\";}"
    , "body.kg-has-sidebar #table-of-contents{display:block!important;}"
    , -- kedgeree.js normally lifts the Source/# links onto the signature's right —
      -- with no JS the float fallback drops them onto a stray line, so render them
      -- inline at the end of the signature instead.
      ".src>a.link,.src>a.selflink"
    , "{float:none!important;opacity:1!important;margin-left:0.6rem;}"
    , -- On mobile the header nav is normally hidden because kedgeree.js mirrors it
      -- into the hamburger drawer. With no JS there is no drawer, so keep the
      -- Contents/Index/Source links in the header rather than leaving it empty.
      "@media (max-width:60rem){#package-header #page-menu"
    , "{display:flex!important;flex-wrap:wrap;}}"
    , "</style></noscript>"
    ]

-- | The SVG brand mark, wired in as a favicon (Haddock provides none).
favicon :: Text -> Text
favicon prefix =
  T.concat
    [ "<link rel=\"icon\" type=\"image/svg+xml\" href=\""
    , prefix
    , "kedgeree-logo.svg\" "
    , marker
    , "=\"icon\" />"
    ]

-- | Preload the bundled font faces that dominate the first paint — body text
-- (Plex Sans 400), the page title (Plex Sans 700) and code (JetBrains Mono 400)
-- — so they are in hand before text renders. Without this the faces are fetched
-- lazily, so the fallback paints first and @font-display: swap@ then swaps each
-- in, a visible flash. A family the visitor has overridden is skipped: its
-- bundled faces are then unused and must not be fetched.
preloadFonts :: Inject -> Text -> Text
preloadFonts inj prefix = T.concat (map link faces)
  where
    faces =
      [f | injFont inj == Nothing, f <- ["ibm-plex-sans-400", "ibm-plex-sans-700"]]
        ++ [f | injMono inj == Nothing, f <- ["jetbrains-mono-400"]]
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

-- | Optional accent / font overrides, emitted as a tiny inline stylesheet.
-- Values are sanitised so a CLI argument cannot break out of the declaration.
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

-- | Drop characters that could escape an inline CSS declaration. Font-family
-- lists and color values keep their commas, quotes and parentheses.
sanitizeCss :: Text -> Text
sanitizeCss = T.filter (`notElem` ("<>{};" :: String))

-- | When requested, hide Haddock's module-info badge — the @table.info@ box in
-- the module header that shows Safe Haskell (and, with @--show-extensions@,
-- Language and Extensions). Injected after the stylesheet so @display:none@ wins.
hideModuleInfo :: Inject -> Text
hideModuleInfo inj
  | injHideModuleInfo inj =
      T.concat ["<style ", marker, "=\"hide-info\">table.info{display:none}</style>"]
  | otherwise = ""

-- | A branded stylesheet @<link>@, resolved against the shared asset directory.
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

-- | The deferred theme script, resolved against the shared asset directory.
js :: Text -> Text
js prefix =
  T.concat
    [ "<script src=\""
    , prefix
    , "kedgeree.js\" defer=\"defer\" "
    , marker
    , "=\"js\"></script>"
    ]

-- | Insert @ins@ immediately after the opening @<head ...>@ tag, so our theme
-- assets are the first thing the browser processes. If there is no @<head>@
-- the document is returned unchanged.
injectAfterHead :: Text -> Text -> Text
injectAfterHead ins html =
  case T.breakOn "<head" html of
    (before, rest)
      | T.null rest -> html
      | otherwise -> case T.breakOn ">" rest of
          (tag, after)
            | T.null after -> html
            | otherwise -> before <> tag <> ">" <> ins <> T.drop 1 after

-- | Add a class to the @<body>@ tag, merging into an existing @class@
-- attribute when present and adding one otherwise — robust to a @<body>@ that
-- carries attributes, unlike a literal @"<body>"@ replacement.
addBodyClass :: Text -> Text -> Text
addBodyClass klass html =
  case T.breakOn "<body" html of
    (before, rest)
      | T.null rest -> html
      | otherwise -> case T.breakOn ">" rest of
          (tag, after)
            | T.null after -> html
            -- Already on the body tag (the class string only ever appears
            -- here, never in the head's no-JS rule) — leave it alone.
            | klass `T.isInfixOf` tag -> html
            | otherwise -> before <> mergeClass tag <> after
  where
    classAttr = "class=\""
    mergeClass tag =
      case T.breakOn classAttr tag of
        (b, c)
          | T.null c -> tag <> " " <> classAttr <> klass <> "\""
          | otherwise ->
              b <> classAttr <> klass <> " " <> T.drop (T.length classAttr) c

-- | Mark Haddock's external MathJax @<script>@ as @defer@ so it no longer blocks
-- the parser (and therefore first paint). MathJax still typesets on load. We
-- match a @src@ that mentions @mathjax@ case-insensitively, which covers both
-- the historic @MathJax.js@ and a lowercase @mathjax.js@ filename. The inline
-- @x-mathjax-config@ block has no @src@, so it is correctly left untouched.
deferMathJax :: Text -> Text
deferMathJax = go
  where
    go t =
      case T.breakOn "<script" t of
        (before, rest)
          | T.null rest -> before
          | otherwise ->
              let (body, afterGt) = T.breakOn ">" rest
                  tag = body <> ">"
                  remainder = T.drop 1 afterGt
               in if isMathJaxScript tag && not (alreadyDeferred tag)
                    then before <> T.replace "<script" "<script defer=\"defer\"" tag <> go remainder
                    else before <> tag <> go remainder
    isMathJaxScript tag =
      "src" `T.isInfixOf` tag && "mathjax" `T.isInfixOf` T.toLower tag
    alreadyDeferred tag = "defer" `T.isInfixOf` tag || "async" `T.isInfixOf` tag

-- | Remove every self-closing @<link .../>@ tag whose text contains @needle@
-- (used to drop Haddock's Google Fonts CDN link).
removeLinkContaining :: Text -> Text -> Text
removeLinkContaining needle = go
  where
    go t =
      case T.breakOn "<link" t of
        (before, rest)
          | T.null rest -> before
          | otherwise ->
              let (body, afterGt) = T.breakOn ">" rest
                  tag = body <> ">"
                  remainder = T.drop 1 afterGt
               in if needle `T.isInfixOf` tag
                    then before <> go remainder
                    else before <> tag <> go remainder

-- | Strip every element whose opening tag carries the marker attribute —
-- content and closing tag included for non-void elements. Used to clear a
-- previous (older-version) Kedgeree injection before re-applying the current
-- one.
removeMarkedElements :: Text -> Text
removeMarkedElements = go
  where
    go t =
      case T.breakOn marker t of
        (pre, suf)
          | T.null suf -> t
          | otherwise ->
              let (beforeLt, tagHead) = T.breakOnEnd "<" pre
               in -- Only strip when the marker is an attribute inside an opening
                  -- tag: there must be a preceding '<' with no '>' between it and
                  -- the marker. Otherwise it is a literal in page text — keep it
                  -- and carry on past this occurrence.
                  if T.null beforeLt || ">" `T.isInfixOf` tagHead
                    then pre <> marker <> go (T.drop (T.length marker) suf)
                    else
                      let before = T.dropEnd 1 beforeLt
                          name = T.takeWhile isNameChar tagHead
                          element = "<" <> tagHead <> suf
                       in before <> go (dropElement name element)

    -- @element@ starts at the tag's '<' — return the text after the element.
    dropElement name element
      | name `elem` voidEls = afterFirst ">" element
      | otherwise =
          let close = "</" <> name <> ">"
           in case T.breakOn close element of
                (_, found)
                  | T.null found -> afterFirst ">" element
                  | otherwise -> T.drop (T.length close) found

    afterFirst needle s = T.drop (T.length needle) (snd (T.breakOn needle s))
    voidEls = ["link", "meta", "br", "img", "input", "hr", "source"]
    isNameChar c = c `notElem` (" \t\r\n>/" :: String)
