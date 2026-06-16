{-# LANGUAGE OverloadedStrings #-}

-- | Pure HTML rewriting. Inject the Kedgeree theme into a Haddock page's
-- @<head>@, and render the chrome (header, sidebar, source-link layout,
-- instances control) server-side so it is present at first paint.
--
-- The injection leads @<head>@, ahead of Haddock's render-blocking MathJax
-- @<script>@ (which we also mark @defer@), so the theme resolves before first
-- paint and the deferred @kedgeree.js@ only wires up behavior.
--
-- Idempotency is version-aware. A page with THIS build's stamp is left alone. A
-- page themed by a different version has the old injection stripped and the new
-- one applied, so upgrading and re-running re-themes.
module Kedgeree.Rewrite
  ( Inject (..)
  , rewriteMain
  , rewriteSource
  , landingPage
  , displayName
  , marker
  ) where

import Data.Char (isSpace)
import Data.List (isPrefixOf)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Version (showVersion)

import Kedgeree.Sidebar (renderSidebar)
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
-- @mpkg@ is the package name (when known), used to render the header brand
-- server-side so it does not pop in after the script runs.
rewriteMain :: Text -> Inject -> Maybe Text -> Text -> Text
rewriteMain prefix inj mpkg html =
  wrapSig (injectInstances (injectSidebar (injectChrome (rewrite inj sheets injection html))))
  where
    -- Group each declaration's trailing Source/# links and fold per-argument type
    -- bars back onto the signature line, both server-side, so CSS pins/shows them
    -- with no post-load DOM work from kedgeree.js. Idempotent.
    wrapSig out
      | "kg-srclinks" `T.isInfixOf` out = out
      | otherwise = breakLongSigs (wrapArgSigs (wrapSourceLinks out))
    -- Our "Instances" nav control (expand/collapse all), rendered into #page-menu
    -- server-side so it is at first paint. Replaces the bundle's late one (which
    -- kedgeree.js drops). Only on pages with instances.
    injectInstances out
      | "data-details-id=\"i:" `T.isInfixOf` html
      , not ("kg-instances" `T.isInfixOf` out) =
          insertAfterTag "id=\"page-menu\"" instancesControl out
      | otherwise = out
    -- The sidebar nav, rendered from the page so it is at first paint, plus the
    -- body classes the grid needs (kg-sidebar-min marks the drawer-only kind).
    -- Idempotent: skip if one is already present (a non-force re-run).
    injectSidebar out = case renderSidebar html of
      Just (nav, rich)
        | not ("id=\"kg-sidebar\"" `T.isInfixOf` out)
        , (before, rest) <- T.breakOn "</body>" out
        , not (T.null rest) ->
            addBodyClass "kg-has-sidebar" $
              (if rich then id else addBodyClass "kg-sidebar-min") (before <> nav <> rest)
      _ -> out
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
    injectChrome = injectHeaderChrome (headerChrome brandName)
    brandName = case mpkg of
      Just pkg | not (T.null (T.strip pkg)) -> pkg
      _ -> "Documentation"

-- | Build a standalone, themed landing page for a multi-package tree: a header
-- with @title@ and a grid of links, one per package, to @\<name>/index.html@. It
-- reuses the same bootstrap, stylesheets and script as a themed Haddock page, so
-- the theme, fonts and toggle behave identically. @prefix@ resolves the shared
-- assets (always @"kedgeree-assets\/"@, the landing sits at the tree root), and
-- the bootstrap stamp marks it ours so a later run leaves it be. @mdesc@ is an
-- optional one-line description under the title. Each package is its directory
-- name paired with an optional synopsis (from its @.cabal@, if available).
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
      Just d
        | not (T.null (T.strip d)) ->
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
          Just s
            | not (T.null (T.strip s)) ->
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
    -- Haddock's source pages declare no charset, so injected unicode glyphs can
    -- mojibake. Assert UTF-8.
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

-- | Shared logic. If already at the current version, do nothing. Otherwise clear
-- any older Kedgeree injection, strip Haddock's stylesheets (we replace them) and
-- the Google Fonts CDN link (we self-host fonts), drop or defer Haddock's MathJax,
-- and splice our injection in at the start of @<head>@.
rewrite :: Inject -> [Text] -> Text -> Text -> Text
rewrite inj sheets injection html
  -- @--force@ skips this short-circuit. The strip-and-reinject path below already
  -- cleans a previous injection, so re-theming stays idempotent.
  | not (injForce inj) && stamp `T.isInfixOf` html = html
  | otherwise = injectAfterHead injection (handleMathJax stripped)
  where
    stripped = foldr removeLinkContaining cdnStripped sheets
    cdnStripped = removeLinkContaining "fonts.googleapis.com" cleared
    -- A stale (older-version) injection is removed before re-applying.
    cleared
      | marker `T.isInfixOf` html = removeMarkedElements html
      | otherwise = html

-- | The inline bootstrap. Runs synchronously in @<head>@ so the resolved theme
-- is on @<html>@ before the browser paints, with no flash of the wrong theme.
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
    , -- Mark JS as live before first paint so the "hide-when-js-enabled" toggle
      -- labels (the module tree's "Submodules", the synopsis/instance summaries)
      -- are hidden from the start, rather than painting and then vanishing in a
      -- reflow once Haddock's bundle adds body.js-enabled after load.
      "r.setAttribute('data-js','1');"
    , "}catch(e){}})();</script>"
    ]
  where
    def = case injDefaultTheme inj of
      "light" -> "light"
      "dark" -> "dark"
      _ -> "auto"

-- | The no-JS fallback. The sidebar, header chrome and per-signature Source
-- links are all server-rendered now, so they stand on their own without the
-- script. The one thing that still needs JS is the mobile drawer (kedgeree.js
-- mirrors the header nav into it), so when it can't open keep the header's
-- Contents/Index/Source links visible on mobile rather than leaving an empty nav.
noscriptFix :: Text
noscriptFix =
  T.concat
    [ "<noscript "
    , marker
    , "=\"noscript\"><style>"
    , "@media (max-width:60rem){#package-header #page-menu"
    , "{display:flex!important;flex-wrap:wrap;}}"
    , "</style></noscript>"
    ]

-- | The header chrome (menu button, brand, search, theme toggle) rendered
-- server-side so it is present at first paint instead of being built by
-- kedgeree.js after load. Button icons are CSS masks (assets @icons/*.svg@), so
-- the markup carries no SVG and the script only wires up the click handlers.
-- Each element carries the marker, so a re-run strips and refreshes it.
headerChrome :: Text -> Text
headerChrome pkg =
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
    , htmlEscape pkg
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

-- | Our \"Instances\" nav dropdown (expand/collapse all), as a native
-- @\<details>@ so the open/close needs no script. It carries no @\<a href=\"#\">@,
-- so kedgeree.js's fragment-href filter leaves it be while dropping the bundle's
-- late duplicate. The script wires the two actions.
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

-- | Wrap each declaration's trailing @Source@ / @#@ links in a
-- @\<span class="kg-srclinks">@ so the stylesheet can pin them to the signature's
-- top-right. Done server-side, so nothing jumps on first paint. @class="link"@
-- marks a Source link and, in Haddock's output, appears only on these.
wrapSourceLinks :: Text -> Text
wrapSourceLinks = T.concat . go
  where
    go t = case T.breakOn "<a " t of
      (before, post)
        | T.null post -> [before]
        | otherwise ->
            let (anchor, rest) = takeAnchor post
             in if "class=\"link\"" `T.isInfixOf` openTag anchor
                  then
                    let (extra, rest') = takeSelflink rest
                     in before : "<span class=\"kg-srclinks\">" : anchor : extra : "</span>" : go rest'
                  else before : anchor : go rest

    -- An anchor element, up to and including its closing @</a>@.
    takeAnchor t = case T.breakOn "</a>" t of
      (a, b)
        | T.null b -> (a, b)
        | otherwise -> (a <> "</a>", T.drop 4 b)

    openTag = T.takeWhile (/= '>')

    -- The @#@ self-link that follows a Source link (with any whitespace), if any.
    takeSelflink t =
      let (ws, r) = T.span isSpace t
       in case takeAnchor r of
            (anchor, r')
              | "<a " `T.isPrefixOf` r
              , "class=\"selflink\"" `T.isInfixOf` openTag anchor ->
                  (ws <> anchor, r')
            _ -> ("", t)

-- | Fold each argument-documented function's per-argument type bars back onto its
-- signature line, right after the defined name. Haddock renders these as a bare
-- name plus a @subs arguments@ table. Inlining the table's @td.src@ bars shows the
-- full type at first paint, so nothing reflows. Any unexpected shape is left
-- untouched.
wrapArgSigs :: Text -> Text
wrapArgSigs = go
  where
    argsOpen = "<div class=\"subs arguments\">"
    go t = case T.breakOn argsOpen t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            inlineInto (extractBars rest) before
              <> argsOpen
              <> go (T.drop (T.length argsOpen) rest)

    -- The space-joined argument bars (each @td.src@ inner) of the table opening rest.
    extractBars rest =
      let tableInner = fst (T.breakOn "</table>" (snd (T.breakOn "<table>" rest)))
       in T.intercalate " " (map T.strip (tdSrcs tableInner))

    tdSrcs t =
      let (_, r) = T.breakOn tdMark t
       in if T.null r
            then []
            else
              let (inner, afterInner) = T.breakOn "</td>" (T.drop (T.length tdMark) r)
               in inner : tdSrcs afterInner
      where
        tdMark = "<td class=\"src\">"

    -- Insert the inlined signature into the @<p class="src">@ at the end of before,
    -- just after the defined name's @</a>@. Falls through on any unexpected shape.
    inlineInto bars before
      | T.null bars = before
      | (pre, psrc) <- T.breakOnEnd "<p class=\"src\">" before
      , not (T.null pre)
      , "class=\"def\"" `T.isInfixOf` psrc
      , (defPart, afterDef) <- T.breakOn "</a>" psrc
      , not (T.null afterDef) =
          pre <> defPart <> "</a> <span class=\"kg-argsig\">" <> bars <> "</span>" <> T.drop 4 afterDef
      | otherwise = before

-- | Arrow-aligned multi-line signatures, server-side. Each top-level @::@ @=>@
-- @->@ (never one nested in parens or brackets) starts a fresh line indented two
-- columns, but only for signatures long enough to want it. Short ones stay on one
-- line. A fixed length threshold trades a little width-awareness for zero load
-- jank. Runs after the Source links are grouped, so it leaves them alone.
breakLongSigs :: Text -> Text
breakLongSigs =
  goElem "<p class=\"src\">" "</p>"
    . goElem "<td class=\"src\">" "</td>"
    . goElem "<dfn class=\"src\">" "</dfn>"
  where
    -- For each signature element of a kind (top-level decls are <p>, constructors
    -- and methods <td>, record fields <dfn>), break a long signature at its
    -- top-level arrows and mark it kg-multiline.
    goElem open close t = case T.breakOn open t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            let afterOpen = T.drop (T.length open) rest
                (inner, afterInner) = T.breakOn close afterOpen
                (inner', broke) = processSig inner
                open' =
                  if broke
                    then T.replace "class=\"src\"" "class=\"src kg-multiline\"" open
                    else open
             in before
                  <> open'
                  <> inner'
                  <> close
                  <> goElem open close (T.drop (T.length close) afterInner)

    -- Break the signature (everything before the Source/# links) if it's long,
    -- then keep every @->@ from splitting across a soft-wrap. A hyphen is a break
    -- opportunity, so a narrow viewport would otherwise wrap "Int -" then "> a".
    -- When the element has Source/# links (the <p> decls), move the signature into
    -- a scrollable .kg-sig so a lone over-long identifier scrolls rather than
    -- sliding under the pinned links.
    processSig inner =
      let (sig, links) = T.breakOn "<span class=\"kg-srclinks\">" inner
          long = visibleLen sig > 68
          sig' = atomicArrows (if long then breakArrows sig else sig)
          out
            | T.null links = sig'
            | otherwise = "<span class=\"kg-sig\">" <> sig' <> "</span>" <> links
       in (out, long)

    atomicArrows = T.replace "-&gt;" "<span class=\"kg-arr\">-&gt;</span>"

    -- Scan the signature HTML, tracking bracket depth in text and skipping tags,
    -- inserting a break before each top-level arrow. Arrows carry their @>@ as the
    -- @&gt;@ entity in the markup.
    breakArrows = T.pack . scan (0 :: Int) False . T.unpack
    scan _ _ [] = []
    scan depth seen ('<' : cs) =
      let (tag, rest) = break (== '>') cs
       in case rest of
            ('>' : rest') -> '<' : tag ++ '>' : scan depth seen rest'
            _ -> '<' : tag
    scan depth seen s@(c : cs)
      | c == '(' || c == '[' = c : scan (depth + 1) True cs
      | c == ')' || c == ']' = c : scan (max 0 (depth - 1)) True cs
      | depth == 0 && seen
      , Just (arrow, rest) <- arrowAt s =
          '\n' : ' ' : ' ' : arrow ++ scan depth True rest
      | c == ' ' || c == '\t' || c == '\n' = c : scan depth seen cs
      | otherwise = c : scan depth True cs

    arrowAt s
      | "::" `isPrefixOf` s = Just ("::", drop 2 s)
      | "-&gt;" `isPrefixOf` s = Just ("-&gt;", drop 5 s)
      | "=&gt;" `isPrefixOf` s = Just ("=&gt;", drop 5 s)
      | otherwise = Nothing

    -- Visible (rendered) length: tags dropped, the few entities we care about decoded.
    visibleLen = T.length . decode . stripTags
    stripTags t = case T.breakOn "<" t of
      (a, b)
        | T.null b -> a
        | otherwise -> a <> stripTags (T.drop 1 (snd (T.breakOn ">" b)))
    decode = T.replace "&gt;" ">" . T.replace "&lt;" "<" . T.replace "&amp;" "&"

-- | Splice the header chrome in right after Haddock's @#package-header@ opening
-- tag. The chrome's @.kg-actions@ is @margin-left:auto@, so order handles itself.
injectHeaderChrome :: Text -> Text -> Text
injectHeaderChrome chrome html
  -- Idempotent: a non-force re-run returns an already-themed page unchanged, so
  -- skip when our chrome is already there rather than injecting a second copy.
  | (marker <> "=\"brand\"") `T.isInfixOf` html = html
  | otherwise = insertAfterTag "id=\"package-header\"" chrome html

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

-- | Preload the bundled font faces that dominate the first paint: body text
-- (Plex Sans 400), the page title (Plex Sans 700) and code (JetBrains Mono 400),
-- so they are in hand before text renders. Without this the faces load lazily, so
-- the fallback paints first and @font-display: swap@ then swaps each in, a visible
-- flash. A family the visitor has overridden is skipped, since its bundled faces
-- are then unused and must not be fetched.
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

-- | When requested, hide Haddock's module-info badge: the @table.info@ box in the
-- module header that shows Safe Haskell (and, with @--show-extensions@, Language
-- and Extensions). Injected after the stylesheet so @display:none@ wins.
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

-- | Insert @ins@ immediately after the first opening tag containing @anchor@. A
-- literal lead like @"<head"@ or an attribute like @id="page-menu"@ both work.
-- The document is returned unchanged if @anchor@ (or the tag's @>@) is absent.
insertAfterTag :: Text -> Text -> Text -> Text
insertAfterTag anchor ins html =
  case T.breakOn anchor html of
    (before, rest)
      | T.null rest -> html
      | otherwise -> case T.breakOn ">" rest of
          (tag, after)
            | T.null after -> html
            | otherwise -> before <> tag <> ">" <> ins <> T.drop 1 after

-- | Splice our theme assets in right after the opening @<head ...>@ tag, so they
-- are the first thing the browser processes.
injectAfterHead :: Text -> Text -> Text
injectAfterHead = insertAfterTag "<head"

-- | Add a class to the @<body>@ tag, merging into an existing @class@ attribute
-- when present and adding one otherwise. Robust to a @<body>@ that carries
-- attributes, unlike a literal @"<body>"@ replacement.
addBodyClass :: Text -> Text -> Text
addBodyClass klass html =
  case T.breakOn "<body" html of
    (before, rest)
      | T.null rest -> html
      | otherwise -> case T.breakOn ">" rest of
          (tag, after)
            | T.null after -> html
            -- Already on the body tag (the class string only ever appears here,
            -- never in the head's no-JS rule), so leave it alone.
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

-- | Haddock loads MathJax on every page, and it parks a \"Processing math\" box
-- in the corner while it loads. Math is wrapped in @class="mathjax"@ (per
-- Haddock's tex2jax @processClass@ config), so when none is present we drop
-- MathJax entirely. Otherwise we keep it but mark the loader @defer@ (and hide its
-- message box in CSS).
handleMathJax :: Text -> Text
handleMathJax html
  | "class=\"mathjax\"" `T.isInfixOf` html = deferMathJax html
  | otherwise = removeMathJax html

-- | Walk @html@ tag by tag: at each opening tag starting with @lead@, hand the
-- whole tag (its @>@ included) and the text after it to @edit@, which returns
-- what to emit in its place and where to resume scanning. Anything outside such
-- tags is copied through untouched.
rewriteTags :: Text -> (Text -> Text -> (Text, Text)) -> Text -> Text
rewriteTags lead edit = go
  where
    go t = case T.breakOn lead t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            let (body, afterGt) = T.breakOn ">" rest
                (emit, continue) = edit (body <> ">") (T.drop 1 afterGt)
             in before <> emit <> go continue

-- | Strip Haddock's MathJax loader and its inline @x-mathjax-config@ block,
-- content and closing tag included.
removeMathJax :: Text -> Text
removeMathJax = rewriteTags "<script" edit
  where
    edit tag rest
      | isMathJax tag = ("", afterClose rest)
      | otherwise = (tag, rest)
    isMathJax tag =
      let low = T.toLower tag
       in ("src" `T.isInfixOf` tag && "mathjax" `T.isInfixOf` low)
            || "x-mathjax-config" `T.isInfixOf` low
    afterClose t = case T.breakOn "</script>" t of
      (_, rest)
        | T.null rest -> t
        | otherwise -> T.drop (T.length "</script>") rest

-- | Mark Haddock's external MathJax @<script>@ as @defer@ so it no longer blocks
-- the parser (and therefore first paint). MathJax still typesets on load. We
-- match a @src@ that mentions @mathjax@ case-insensitively, which covers both
-- the historic @MathJax.js@ and a lowercase @mathjax.js@ filename. The inline
-- @x-mathjax-config@ block has no @src@, so it is correctly left untouched.
deferMathJax :: Text -> Text
deferMathJax = rewriteTags "<script" edit
  where
    edit tag rest
      | isMathJaxScript tag && not (alreadyDeferred tag) =
          (T.replace "<script" "<script defer=\"defer\"" tag, rest)
      | otherwise = (tag, rest)
    isMathJaxScript tag =
      "src" `T.isInfixOf` tag && "mathjax" `T.isInfixOf` T.toLower tag
    alreadyDeferred tag = "defer" `T.isInfixOf` tag || "async" `T.isInfixOf` tag

-- | Remove every self-closing @<link .../>@ tag whose text contains @needle@
-- (used to drop Haddock's Google Fonts CDN link).
removeLinkContaining :: Text -> Text -> Text
removeLinkContaining needle = rewriteTags "<link" $ \tag rest ->
  if needle `T.isInfixOf` tag then ("", rest) else (tag, rest)

-- | Strip every element whose opening tag carries the marker attribute, content
-- and closing tag included for non-void elements. Used to clear a previous
-- (older-version) Kedgeree injection before re-applying the current one.
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
                  -- the marker. Otherwise it is a literal in page text, so keep it
                  -- and carry on past this occurrence.
                  if T.null beforeLt || ">" `T.isInfixOf` tagHead
                    then pre <> marker <> go (T.drop (T.length marker) suf)
                    else
                      let before = T.dropEnd 1 beforeLt
                          name = T.takeWhile isNameChar tagHead
                          element = "<" <> tagHead <> suf
                       in before <> go (dropElement name element)

    -- @element@ starts at the tag's '<'. Return the text after the element.
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
