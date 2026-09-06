{-# LANGUAGE OverloadedStrings #-}

-- | Server-side signature layout: group Source/# links, inline per-argument
-- type bars, break long signatures at top-level operators. Output is unmarked,
-- so 'unwrapSignatures' strips a previous run's markup before the passes run.
module Kedgeree.Signature
  ( wrapSignatures
  , unwrapSignatures
  , wrapSourceLinks
  , wrapArgSigs
  , breakLongSigs
  ) where

import Data.Char (isSpace)
import Data.List (isPrefixOf)
import Data.Text (Text)
import qualified Data.Text as T

import qualified Kedgeree.Haddock as Haddock
import Kedgeree.Html (decodeEntities, stripTags, visibleLength)

-- | All three passes, after undoing any previous run's.
wrapSignatures :: Text -> Text
wrapSignatures = breakLongSigs . wrapArgSigs . wrapSourceLinks . unwrapSignatures

-- | Strip a previous run's signature markup so the passes run afresh on a
-- stale or forced re-theme: the kg-sig, kg-srclinks, kg-op and kg-grp wrappers
-- are unwrapped, kg-nl break markers and inlined kg-argsig bars are dropped, and
-- the kg-multiline / kg-len-N classes removed. Earlier builds put the links
-- before the signature and broke it with hard newlines; those are moved after
-- it and flattened. No-op on a plain Haddock page.
unwrapSignatures :: Text -> Text
unwrapSignatures html
  | not ("kg-srclinks" `T.isInfixOf` html) = html
  | otherwise = mapSrcElems legacyOrder (unwrapSpans (dropClasses html))
  where
    dropClasses t = case T.splitOn "class=\"src kg-multiline" t of
      (s0 : segs) -> T.concat (s0 : map (("class=\"src" <>) . T.dropWhile (/= '"')) segs)
      [] -> t

    -- Chunks start at a '<'. Spans are tracked on a stack: Keep is copied,
    -- Drop loses its tags, DropAll loses its content too.
    unwrapSpans t = case T.splitOn "<" t of
      (s0 : chunks) -> T.concat (s0 : go [] chunks)
      [] -> t
    go _ [] = []
    go stack (c : cs)
      | "/span>" `T.isPrefixOf` c = case stack of
          (Drop : st) -> textAfter c : go st cs
          (DropAll : st) -> textAfterClosing st c : go st cs
          (Keep : st) -> emit ("<" <> c) : go st cs
          [] -> ("<" <> c) : go [] cs
      | "span " `T.isPrefixOf` c =
          let tag = T.takeWhile (/= '>') c
              mode
                | any ((`T.isInfixOf` tag) . spanClass) ["kg-sig", "kg-srclinks", "kg-op", "kg-grp", "kg-nl"] = Drop
                | spanClass "kg-argsig" `T.isInfixOf` tag = DropAll
                | otherwise = Keep
           in case mode of
                Keep -> emit ("<" <> c) : go (Keep : stack) cs
                Drop -> emit (textAfter c) : go (Drop : stack) cs
                DropAll -> go (DropAll : stack) cs
      | otherwise = emit ("<" <> c) : go stack cs
      where
        emit s = if DropAll `elem` stack then "" else s
        textAfter s = emit (T.drop 1 (T.dropWhile (/= '>') s))
        -- Text after the tag closing a DropAll span, kept unless one still encloses it.
        textAfterClosing st s = if DropAll `elem` st then "" else T.drop 1 (T.dropWhile (/= '>') s)
    spanClass k = "class=\"" <> k <> "\""

    -- Hard breaks ("\n" before an operator, "\n  " in cells) collapse back to
    -- spaces, and leading Source / # anchors move after the signature.
    legacyOrder open inner = (open, fix (flatten inner))
      where
        fix s = case leadingAnchors s of
          Just (anchors, sig) -> T.stripEnd sig <> " " <> anchors
          Nothing -> s
    flatten = T.replace "\n" " " . T.replace " \n" "\n" . T.replace "\n  " "\n"
    leadingAnchors s
      | isLinkAnchor s =
          let (a1, r1) = takeAnchor s
              (ws, r2) = T.span isSpace r1
           in if isLinkAnchor r2
                then let (a2, r3) = takeAnchor r2 in Just (a1 <> ws <> a2, T.stripStart r3)
                else Just (a1, T.stripStart r1)
      | otherwise = Nothing
    isLinkAnchor s =
      "<a " `T.isPrefixOf` s
        && let tag = T.takeWhile (/= '>') s
            in classAttr Haddock.sourceLinkClass `T.isInfixOf` tag || classAttr Haddock.selfLinkClass `T.isInfixOf` tag

data SpanMode = Keep | Drop | DropAll
  deriving (Eq)

classAttr :: Text -> Text
classAttr c = "class=\"" <> c <> "\""

-- | An anchor element through its @</a>@, and the rest.
takeAnchor :: Text -> (Text, Text)
takeAnchor t = case T.breakOn "</a>" t of
  (a, b)
    | T.null b -> (a, b)
    | otherwise -> (a <> "</a>", T.drop 4 b)

-- | Apply @f open inner@ to every @p.src@, @td.src@ and @dfn.src@ element.
mapSrcElems :: (Text -> Text -> (Text, Text)) -> Text -> Text
mapSrcElems f =
  goElem Haddock.srcParagraphOpen "</p>"
    . goElem Haddock.srcCellOpen "</td>"
    . goElem Haddock.srcDfnOpen "</dfn>"
  where
    goElem open close t = case T.breakOn open t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            let afterOpen = T.drop (T.length open) rest
                (inner, afterInner) = T.breakOn close afterOpen
                (open', inner') = f open inner
             in before <> open' <> inner' <> close <> goElem open close (T.drop (T.length close) afterInner)

-- | Wrap each declaration's trailing Source (@a.link@) and @#@ (@a.selflink@)
-- links in @span.kg-srclinks@. A lone selflink (re-export) is wrapped too.
-- Source links get @title="Source"@.
wrapSourceLinks :: Text -> Text
wrapSourceLinks = T.concat . go
  where
    go t = case T.breakOn "<a " t of
      (before, post)
        | T.null post -> [before]
        | otherwise ->
            let (anchor, rest) = takeAnchor post
                tag = openTag anchor
             in if classAttr Haddock.sourceLinkClass `T.isInfixOf` tag
                  then
                    let (extra, rest') = takeSelflink rest
                        anchor'
                          | "title=" `T.isInfixOf` anchor = anchor
                          | otherwise =
                              T.replace
                                (classAttr Haddock.sourceLinkClass)
                                (classAttr Haddock.sourceLinkClass <> " title=\"Source\"")
                                anchor
                     in before : "<span class=\"kg-srclinks\">" : anchor' : extra : "</span>" : go rest'
                  else
                    if classAttr Haddock.selfLinkClass `T.isInfixOf` tag
                      then before : "<span class=\"kg-srclinks\">" : anchor : "</span>" : go rest
                      else before : anchor : go rest

    openTag = T.takeWhile (/= '>')

    -- Whitespace plus a following selflink anchor, if present.
    takeSelflink t =
      let (ws, r) = T.span isSpace t
       in case takeAnchor r of
            (anchor, r')
              | "<a " `T.isPrefixOf` r
              , classAttr Haddock.selfLinkClass `T.isInfixOf` openTag anchor ->
                  (ws <> anchor, r')
            _ -> ("", t)

-- | Inline an argument-documented function's @td.src@ type bars into its
-- @p.src@ signature, after the @a.def@, as @span.kg-argsig@. Unexpected shapes
-- are left untouched.
wrapArgSigs :: Text -> Text
wrapArgSigs = go
  where
    argsOpen = Haddock.argumentsOpen
    go t = case T.breakOn argsOpen t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            inlineInto (extractBars rest) before
              <> argsOpen
              <> go (T.drop (T.length argsOpen) rest)

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
        tdMark = Haddock.srcCellOpen

    inlineInto bars before
      | T.null bars = before
      | (pre, psrc) <- T.breakOnEnd Haddock.srcParagraphOpen before
      , not (T.null pre)
      , ("class=\"" <> Haddock.defClass <> "\"") `T.isInfixOf` psrc
      , (defPart, afterDef) <- T.breakOn "</a>" psrc
      , not (T.null afterDef) =
          pre <> defPart <> "</a> <span class=\"kg-argsig\">" <> bars <> "</span>" <> T.drop 4 afterDef
      | otherwise = before

-- | Scanner state for 'breakLongSigs'.
data Scan = Scan
  { scDepth :: !Int
  -- ^ bracket depth
  , scSeen :: !Bool
  -- ^ any non-space text emitted yet
  , scGroup :: !Bool
  -- ^ inside a kept (@kg-grp@) top-level group
  , scFundep :: !Bool
  -- ^ past a top-level @|@
  }

-- | Per-signature layout decisions.
data Layout = Layout
  { lyLong :: !Bool
  -- ^ break at top-level operators
  , lyBreakForall :: !Bool
  -- ^ break after a top-level forall dot
  }

-- | Color @::@ @->@ @=>@ (@span.kg-op@), keep short comma-free top-level groups
-- unbreakable (@span.kg-grp@), and for long signatures (> 52 visible chars)
-- mark a break point (@span.kg-nl@) before each top-level operator and after a
-- long forall or a type synonym @=@. The element gets @kg-multiline@ and a
-- @kg-len-N@ bucket (visible length rounded up to 4, capped at 128) so CSS can
-- hide the breaks when the signature fits its container. Applies to @p.src@,
-- @td.src@ and @dfn.src@.
breakLongSigs :: Text -> Text
breakLongSigs = mapSrcElems layoutElem
  where
    layoutElem open inner =
      let (inner', broke) = processSig inner
          open' = case broke of
            Just len ->
              T.replace
                "class=\"src\""
                ("class=\"src kg-multiline kg-len-" <> T.pack (show (bucket len)) <> "\"")
                open
            Nothing -> open
       in (open', inner')

    -- The signature in span.kg-sig, then its links (the chip trails the last
    -- line). The trailing rightedge span is dropped: its newline renders in
    -- pre-wrap.
    processSig inner =
      let (beforeLinks, links) = T.breakOn "<span class=\"kg-srclinks\">" inner
          sig = T.stripEnd (fst (T.breakOn Haddock.rightEdgeOpen beforeLinks))
          hasLinks = not (T.null links)
          len = visibleLength sig
          long = len > 52
          sig' = highlight (Layout long (forallLong sig)) sig
          out
            | hasLinks = "<span class=\"kg-sig\">" <> sig' <> "</span>" <> links
            | otherwise = sig'
       in (out, if long then Just len else Nothing)

    bucket len = min 128 (((len + 3) `div` 4) * 4)

    highlight ly = T.pack . go (Scan 0 False False False) . T.unpack
      where
        newline = "<span class=\"kg-nl\"></span>"
        go _ [] = []
        -- Tags pass through.
        go st ('<' : cs) =
          let (tag, rest) = break (== '>') cs
           in case rest of
                ('>' : rest') -> '<' : tag ++ '>' : go st rest'
                _ -> '<' : tag
        go st s@(c : cs)
          -- Top-level group: kept whole when comma-free and short.
          | isOpenBracket c
          , scDepth st == 0 =
              let keep = not (groupHasComma cs) && groupShort 30 cs
               in (if keep then "<span class=\"kg-grp\">" else "")
                    ++ c
                    : go st {scDepth = 1, scSeen = True, scGroup = keep} cs
          | isOpenBracket c = c : go st {scDepth = scDepth st + 1, scSeen = True} cs
          | isCloseBracket c =
              let d = max 0 (scDepth st - 1)
               in if d == 0
                    then c : (if scGroup st then "</span>" else "") ++ go st {scDepth = 0, scSeen = True, scGroup = False} cs
                    else c : go st {scDepth = d, scSeen = True} cs
          -- Fundep / constructor list: never break after a top-level '|'.
          | scDepth st == 0, c == '|' = c : go st {scSeen = True, scFundep = True} cs
          | Just (op, rest) <- opAt s =
              let brk
                    | scFundep st || not (lyLong ly && scDepth st == 0 && scSeen st) = ""
                    | otherwise = newline
               in brk ++ "<span class=\"kg-op\">" ++ op ++ "</span>" ++ go st {scSeen = True} rest
          -- Break after a top-level forall '.' or synonym '='. The space stays
          -- (before the marker) so the text is unchanged.
          | breakAfter c = c : ' ' : newline ++ go st {scSeen = True} (dropWhile (== ' ') cs)
          | c == ' ' || c == '\t' || c == '\n' = c : go st cs
          | otherwise = c : go st {scSeen = True} cs
          where
            breakAfter ch =
              scDepth st == 0
                && lyLong ly
                && not (scFundep st)
                && scSeen st
                && take 1 cs == " "
                && (ch == '=' || (ch == '.' && lyBreakForall ly))

        opAt s
          | "::" `isPrefixOf` s = Just ("::", drop 2 s)
          | "-&gt;" `isPrefixOf` s = Just ("-&gt;", drop 5 s)
          | "=&gt;" `isPrefixOf` s = Just ("=&gt;", drop 5 s)
          | otherwise = Nothing

        -- Comma at the group's own bracket level before it closes.
        groupHasComma = go' (0 :: Int)
          where
            go' _ [] = False
            go' d ('<' : t) = go' d (drop 1 (dropWhile (/= '>') t))
            go' d (x : xs)
              | isOpenBracket x = go' (d + 1) xs
              | isCloseBracket x = d /= 0 && go' (d - 1) xs
              | d == 0 && x == ',' = True
              | otherwise = go' d xs

        -- Group length <= lim up to its closing bracket. Tags skipped, entity = 1.
        groupShort lim = go' (0 :: Int) (0 :: Int)
          where
            go' _ n _ | n > lim = False
            go' _ _ [] = True
            go' d n ('<' : t) = go' d n (drop 1 (dropWhile (/= '>') t))
            go' d n ('&' : t) = go' d (n + 1) (drop 1 (dropWhile (/= ';') t))
            go' d n (x : xs)
              | isOpenBracket x = go' (d + 1) (n + 1) xs
              | isCloseBracket x = d == 0 || go' (d - 1) (n + 1) xs
              | otherwise = go' d (n + 1) xs

    isOpenBracket c = c == '(' || c == '['
    isCloseBracket c = c == ')' || c == ']'

    -- Quantifier (forall .. '. ') longer than 24 visible chars.
    forallLong sig = case T.breakOn "forall" (decodeEntities (stripTags sig)) of
      (_, rest)
        | T.null rest -> False
        | otherwise -> clause (0 :: Int) (0 :: Int) (T.unpack rest) > 24
      where
        clause _ n [] = n
        clause d n ('.' : ' ' : _) | d == 0 = n
        clause d n (x : xs)
          | isOpenBracket x = clause (d + 1) (n + 1) xs
          | isCloseBracket x = clause (max 0 (d - 1)) (n + 1) xs
          | otherwise = clause d (n + 1) xs
