{-# LANGUAGE OverloadedStrings #-}

-- | Server-side signature layout: group Source/# links, inline per-argument
-- type bars, break long signatures at top-level operators. Output is unmarked,
-- so 'wrapSignatures' recognises an already-processed page.
module Kedgeree.Signature
  ( wrapSignatures
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

-- | All three passes. No-op on a page that already carries @kg-srclinks@.
wrapSignatures :: Text -> Text
wrapSignatures html
  | "kg-srclinks" `T.isInfixOf` html = html
  | otherwise = breakLongSigs (wrapArgSigs (wrapSourceLinks html))

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

    classAttr c = "class=\"" <> c <> "\""

    -- Anchor element through its @</a>@.
    takeAnchor t = case T.breakOn "</a>" t of
      (a, b)
        | T.null b -> (a, b)
        | otherwise -> (a <> "</a>", T.drop 4 b)

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
  , lyWrapped :: !Bool
  -- ^ signature sits in @span.kg-sig@ (hanging indent via CSS, bare @\\n@ breaks)
  }

-- | Color @::@ @->@ @=>@ (@span.kg-op@), keep short comma-free top-level groups
-- unbreakable (@span.kg-grp@), and for long signatures (> 52 visible chars)
-- break before each top-level operator and after a long forall or a type
-- synonym @=@, marking the element @kg-multiline@. Applies to @p.src@, @td.src@
-- and @dfn.src@.
breakLongSigs :: Text -> Text
breakLongSigs =
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
                (inner', broke) = processSig inner
                open'
                  | broke = T.replace "class=\"src\"" "class=\"src kg-multiline\"" open
                  | otherwise = open
             in before <> open' <> inner' <> close <> goElem open close (T.drop (T.length close) afterInner)

    -- Links first (CSS floats them), then the signature in span.kg-sig. The
    -- trailing rightedge span is dropped: its newline renders in pre-wrap.
    processSig inner =
      let (beforeLinks, links) = T.breakOn "<span class=\"kg-srclinks\">" inner
          sig = T.stripEnd (fst (T.breakOn Haddock.rightEdgeOpen beforeLinks))
          hasLinks = not (T.null links)
          long = visibleLength sig > 52
          sig' = highlight (Layout long (forallLong sig) hasLinks) sig
          out
            | hasLinks = links <> "<span class=\"kg-sig\">" <> sig' <> "</span>"
            | otherwise = sig'
       in (out, long)

    highlight ly = T.pack . go (Scan 0 False False False) . T.unpack
      where
        newline
          | lyWrapped ly = "\n"
          | otherwise = "\n  "
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
          -- Break after a top-level forall '.' or synonym '='.
          | breakAfter c = c : newline ++ go st {scSeen = True} (dropWhile (== ' ') cs)
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
