{-# LANGUAGE OverloadedStrings #-}

-- | Generic text-level HTML editing. Pages are edited as text, not parsed and
-- re-serialised, so untouched markup stays byte-identical. Haddock-specific
-- markup is described in "Kedgeree.Haddock".
module Kedgeree.Html
  ( -- * Escaping and measuring
    htmlEscape
  , stripTags
  , decodeEntities
  , visibleLength

    -- * Splicing
  , insertAfterTag
  , insertBeforeClose
  , addBodyClass

    -- * Editing tags
  , rewriteTags
  , removeTagsWhere
  , removeElementsWithAttribute
  ) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Minimal HTML-text escaping for values placed in element content or
-- attribute values.
htmlEscape :: Text -> Text
htmlEscape =
  T.replace "\"" "&quot;"
    . T.replace ">" "&gt;"
    . T.replace "<" "&lt;"
    . T.replace "&" "&amp;"

-- | Drop every tag, keeping only text content.
stripTags :: Text -> Text
stripTags t = case T.breakOn "<" t of
  (a, b)
    | T.null b -> a
    | otherwise -> a <> stripTags (T.drop 1 (snd (T.breakOn ">" b)))

-- | Decode the few entities Haddock emits inside signatures.
decodeEntities :: Text -> Text
decodeEntities = T.replace "&gt;" ">" . T.replace "&lt;" "<" . T.replace "&amp;" "&"

-- | The rendered length of a fragment: tags dropped, entities decoded.
visibleLength :: Text -> Int
visibleLength = T.length . decodeEntities . stripTags

-- | Insert @ins@ after the first tag containing @anchor@ (a lead like @"<head"@
-- or an attribute like @id="page-menu"@). Unchanged if absent.
insertAfterTag :: Text -> Text -> Text -> Text
insertAfterTag anchor ins html =
  case T.breakOn anchor html of
    (before, rest)
      | T.null rest -> html
      | otherwise -> case T.breakOn ">" rest of
          (tag, after)
            | T.null after -> html
            | otherwise -> before <> tag <> ">" <> ins <> T.drop 1 after

-- | Insert @ins@ immediately before the first occurrence of @close@ (a closing
-- tag such as @"</head>"@). Unchanged if @close@ is absent.
insertBeforeClose :: Text -> Text -> Text -> Text
insertBeforeClose close ins html = case T.breakOn close html of
  (before, rest)
    | T.null rest -> html
    | otherwise -> before <> ins <> rest

-- | Add a class to @<body>@, merging into an existing @class@ attribute. No-op
-- if already present.
addBodyClass :: Text -> Text -> Text
addBodyClass klass html =
  case T.breakOn "<body" html of
    (before, rest)
      | T.null rest -> html
      | otherwise -> case T.breakOn ">" rest of
          (tag, after)
            | T.null after -> html
            | klass `elem` classesOf tag -> html
            | otherwise -> before <> mergeClass tag <> after
  where
    classAttr = "class=\""
    classesOf tag = case T.breakOn classAttr tag of
      (_, c)
        | T.null c -> []
        | otherwise -> T.words (T.takeWhile (/= '"') (T.drop (T.length classAttr) c))
    mergeClass tag =
      case T.breakOn classAttr tag of
        (b, c)
          | T.null c -> tag <> " " <> classAttr <> klass <> "\""
          | otherwise ->
              b <> classAttr <> klass <> " " <> T.drop (T.length classAttr) c

-- | For each tag starting with @lead@, @edit tag rest@ returns the replacement
-- and where to resume. Everything else is copied through.
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

-- | Remove every tag starting with @lead@ that satisfies the predicate. Tag
-- only, so for void elements.
removeTagsWhere :: Text -> (Text -> Bool) -> Text -> Text
removeTagsWhere lead p = rewriteTags lead $ \tag rest ->
  if p tag then ("", rest) else (tag, rest)

-- | Remove every element whose opening tag carries the attribute, content and
-- close included. Same-name nesting is balanced. Text occurrences are ignored.
removeElementsWithAttribute :: Text -> Text -> Text
removeElementsWithAttribute attr = go
  where
    go t =
      case T.breakOn attr t of
        (pre, suf)
          | T.null suf -> t
          | otherwise ->
              let (beforeLt, tagHead) = T.breakOnEnd "<" pre
               in -- Inside a tag iff a '<' precedes with no '>' in between.
                  if T.null beforeLt || ">" `T.isInfixOf` tagHead
                    then pre <> attr <> go (T.drop (T.length attr) suf)
                    else
                      let before = T.dropEnd 1 beforeLt
                          name = T.takeWhile isNameChar tagHead
                          element = "<" <> tagHead <> suf
                       in before <> go (dropElement name element)

    -- @element@ starts at the tag's '<'. Return the text after the element.
    dropElement name element
      | name `elem` voidEls = afterFirstGt element
      | otherwise = skipNested name (0 :: Int) (afterFirstGt element)

    -- Past the close balancing the consumed open. Unclosed: rest of document.
    skipNested name depth t = case T.breakOn "<" t of
      (_, rest)
        | T.null rest -> rest
        | close `T.isPrefixOf` rest ->
            let after = T.drop (T.length close) rest
             in if depth == 0 then after else skipNested name (depth - 1) after
        | isOpenTag rest -> skipNested name (depth + 1) (afterFirstGt rest)
        | otherwise -> skipNested name depth (T.drop 1 rest)
      where
        close = "</" <> name <> ">"
        -- @<name@ then a name terminator (@<li@ must not match @<link@).
        isOpenTag r =
          ("<" <> name) `T.isPrefixOf` r
            && maybe False ((`elem` (" \t\r\n>/" :: String)) . fst) (T.uncons (T.drop (T.length name + 1) r))

    afterFirstGt s = T.drop 1 (snd (T.breakOn ">" s))
    voidEls = ["link", "meta", "br", "img", "input", "hr", "source"]
    isNameChar c = c `notElem` (" \t\r\n>/" :: String)
