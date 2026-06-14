{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}

-- | __Showcase__ — a deliberately pathological module that exercises as many
-- Haddock doc features as possible, so the Kedgeree theme can be checked
-- against all of them at once.
--
-- This first paragraph is intentionally long so we can watch how body prose
-- wraps across the full content width. It mixes __bold text__, /italicised
-- text/, @inline code@, a 'reallyLongFunctionNameThatGoesOnForQuiteAWhile'
-- identifier link, a "Geometry" module link, and an external
-- <https://www.haskell.org Haskell home page> link, all in one breath.
--
-- === A documentation sub-heading
--
-- Some text underneath a sub-heading, to check heading rhythm inside docs.
--
-- A bullet list:
--
--     * a short item
--     * a much longer item, written to be long enough that it wraps onto more
--       than one line so we can confirm list items indent their wrapped lines
--       correctly
--
--         * a nested item
--         * another nested item
--
--     * a final top-level item
--
-- A numbered list:
--
--     1. first
--     2. second
--     3. third
--
-- A definition list:
--
--     [@Functor@] things you can map over
--     [@Monad@] things you can sequence, with a deliberately long description
--       that should wrap to exercise definition-list wrapping
--
-- A code block written with bird tracks:
--
-- > main :: IO ()
-- > main = putStrLn "a code block whose contents are wide enough to overflow horizontally on a narrow screen xxxxxxxxxxxxxxxxxxxxxxxx"
--
-- Interactive examples:
--
-- >>> 1 + 1
-- 2
-- >>> map (* 2) [1, 2, 3]
-- [2,4,6]
--
-- Inline math \(e^{i\pi} + 1 = 0\), and a display equation:
--
-- \[ \sum_{i=1}^{n} i = \frac{n (n + 1)}{2} \]
--
-- A grid table:
--
-- +------------+----------------------+
-- | Operation  | Complexity           |
-- +============+======================+
-- | lookup     | /O(log n)/           |
-- +------------+----------------------+
-- | insert     | /O(log n)/           |
-- +------------+----------------------+
module Showcase
  ( -- * A large record
    Config (..)
  , defaultConfig

    -- * Long signatures & per-argument docs
  , reallyLongFunctionNameThatGoesOnForQuiteAWhile
  , withArgumentDocs
  , withLongArgumentTypes

    -- * Type classes
  , Container (..)
  , Convert (..)
  , Describe (..)
  , Tabulate (..)

    -- * GADTs & existentials
  , Expr (..)
  , Showable (..)

    -- * Operators
  , (>+<)

    -- * Deprecated things
  , oldFunction

    -- * Re-exported modules

    -- | The whole "Geometry" module is re-exported here, which Haddock renders
    -- as a @module Geometry@ entry rather than inlining its declarations.
  , module Geometry
  ) where

import Geometry

-- | A large configuration record with many fields, some carrying long types
-- and long per-field descriptions — a good stress test for record rendering.
--
-- @since 1.0.0
data Config = Config
  { configName :: String
  -- ^ A human-readable name for this configuration. This field description is
  -- intentionally verbose so we can see how a long field doc renders relative
  -- to its signature, especially once it wraps.
  , configRetryPolicy :: Int -> Maybe (Int, Int)
  -- ^ A retry policy: given an attempt number, optionally produce a
  -- @(delayMilliseconds, jitter)@ pair. Note the function-typed field.
  , configExtraHeaders :: [(String, String)]
  -- ^ Extra headers attached to every outgoing request.
  , configConnectTimeoutMicroseconds :: Int
  -- ^ Connection timeout, in microseconds.
  , configVerbose :: Bool
  -- ^ Whether to emit verbose diagnostic logging.
  , configOnEvent :: forall a. (Show a) => a -> IO ()
  -- ^ A rank-2 callback invoked on every event — the type uses an explicit
  -- @forall@ and a constraint, making it pleasantly long.
  , configResultHandler :: Either String (Maybe [(String, Int)]) -> IO (Either String (Maybe [(Int, Int)]))
  -- ^ A handler with a long, deeply nested type, so we can see how a long
  -- record-field signature renders when it has to wrap.
  }

-- | A sensible 'Config' to start from.
--
-- @since 1.0.0
defaultConfig :: Config
defaultConfig =
  Config
    { configName = "default"
    , configRetryPolicy = const Nothing
    , configExtraHeaders = []
    , configConnectTimeoutMicroseconds = 1000000
    , configVerbose = False
    , configOnEvent = const (pure ())
    , configResultHandler = const (pure (Right Nothing))
    }

-- | A function with an absurdly long name and a long, multi-constraint type
-- signature that will almost certainly need to scroll horizontally on a narrow
-- screen.
--
-- @since 2.1.0
reallyLongFunctionNameThatGoesOnForQuiteAWhile
  :: (Eq a, Num a, Ord a, Show a)
  => a
  -> a
  -> a
  -> Either String (a, a, a)
reallyLongFunctionNameThatGoesOnForQuiteAWhile x y z = Right (x, y, z)

-- | A function that documents each of its arguments individually, which
-- Haddock renders as an argument table.
--
-- ==== __Examples__
--
-- A plain call assembles the label and count:
--
-- >>> withArgumentDocs 3 "tries" False
-- "tries3"
--
-- Turning on @loud@ prefixes a bang:
--
-- >>> withArgumentDocs 3 "tries" True
-- "!tries3"
withArgumentDocs
  :: Int
  -- ^ the /count/, which must be positive
  -> String
  -- ^ a __label__ for the result
  -> Bool
  -- ^ whether to shout
  -> String
  -- ^ the resulting, fully assembled description
withArgumentDocs n label loud = (if loud then "!" else "") ++ label ++ show n

-- | A per-argument-documented function whose argument /types/ are deliberately
-- long and nested — the pathological case for the argument table. With the
-- type and its description side by side, a type like the second argument's
-- would crowd the prose into a sliver — stacking each argument (type on its own
-- line, description below) keeps both readable.
withLongArgumentTypes
  :: Config
  -- ^ the configuration record to apply before running
  -> (Int -> Either String (Maybe [(String, String)]))
  -- ^ a callback with a long, deeply nested type whose rendering would
  -- otherwise push the per-argument description off the side of the page
  -> [(String, Int -> IO ())]
  -- ^ an association list mapping names to effectful, integer-taking callbacks
  -> IO ()
withLongArgumentTypes _ _ _ = pure ()

-- | A type class with a superclass constraint, an associated type family, a
-- couple of methods, and a method with a default implementation.
--
-- @since 0.3.0
class (Show (Elem c)) => Container c where
  -- | The element type of the container.
  type Elem c

  -- | The empty container.
  empty :: c

  -- | Insert an element at the front.
  insert :: Elem c -> c -> c

  -- | The number of elements. Has a default of @0@.
  size :: c -> Int
  size _ = 0

-- | Lists are containers.
--
-- @since 0.3.0
instance (Show a) => Container [a] where
  type Elem [a] = a
  empty = []
  insert = (:)
  size = length

-- | 'Maybe' is a (degenerate) container holding at most one element.
--
-- @since 0.3.0
instance (Show a) => Container (Maybe a) where
  type Elem (Maybe a) = a
  empty = Nothing
  insert x _ = Just x
  size = maybe 0 (const 1)

-- | A multi-parameter type class for lossy conversions.
class Convert a b where
  -- | Convert from @a@ to @b@.
  convert :: a -> b

-- | A conversion with a deliberately long instance head, to exercise how a long
-- instance signature renders when it wraps.
instance Convert (Either String (Maybe (Int, Int))) (Either String (Maybe [(String, [Bool])])) where
  convert _ = Right Nothing

-- | A class with a deliberately long list of instances, so the stacked instance
-- accordions can be seen en masse on a single page.
--
-- @since 0.4.0
class Describe a where
  -- | Render a one-line human description.
  describe :: a -> String

instance Describe Bool where
  describe b = if b then "true" else "false"

instance Describe Char where
  describe c = [c]

instance Describe Int where
  describe = show

instance Describe Integer where
  describe = show

instance Describe Float where
  describe = show

instance Describe Double where
  describe = show

instance Describe Ordering where
  describe = show

instance Describe () where
  describe _ = "()"

instance (Describe a) => Describe [a] where
  describe = unwords . map describe

instance (Describe a) => Describe (Maybe a) where
  describe = maybe "nothing" describe

instance (Describe a, Describe b) => Describe (Either a b) where
  describe = either describe describe

instance (Describe a, Describe b) => Describe (a, b) where
  describe (a, b) = describe a ++ ", " ++ describe b

instance (Describe a, Describe b, Describe c) => Describe (a, b, c) where
  describe (a, b, c) = describe a ++ ", " ++ describe b ++ ", " ++ describe c

instance Describe Point where
  describe (Point x y) = "(" ++ show x ++ ", " ++ show y ++ ")"

-- | A class with a deliberately long superclass context, to stress how a wide
-- constraint tuple renders in the class header (and how it wraps on a narrow
-- screen).
--
-- @since 0.5.0
class
  (Eq a, Ord a, Show a, Read a, Enum a, Bounded a, Num a, Real a, Integral a) =>
  Tabulate a
  where
  -- | Render the value as a fixed-width table cell.
  tabulate :: a -> String
  tabulate = show

instance Tabulate Int

-- | A simple, type-indexed expression GADT.
--
-- @since 1.2.0
data Expr a where
  -- | An integer literal.
  IntLit :: Int -> Expr Int
  -- | A boolean literal.
  BoolLit :: Bool -> Expr Bool
  -- | Addition of two integer expressions.
  Add :: Expr Int -> Expr Int -> Expr Int
  -- | A conditional whose branches must agree, with a longish signature.
  If :: Expr Bool -> Expr a -> Expr a -> Expr a
  -- | A constructor with a deliberately long, nested signature, to show how a
  -- long GADT constructor type renders when it wraps.
  Annotated :: String -> [(String, String)] -> Either String (Maybe (Expr a)) -> Maybe (Int, Int) -> Expr a

-- | An existential box around anything 'Show'able.
data Showable = forall a. (Show a) => MkShowable a

-- | Concatenate two lists with a custom right-associative operator.
--
-- @since 0.1.0
(>+<) :: [a] -> [a] -> [a]
(>+<) = (++)

infixr 5 >+<

-- | Points form a semigroup under componentwise addition. Both 'Point' and
-- 'Semigroup' are defined elsewhere, so Haddock lists this under a separate
-- /Orphan instances/ section at the foot of the page.
instance Semigroup Point where
  Point ax ay <> Point bx by = Point (ax + bx) (ay + by)

-- | An old function that should no longer be used.
oldFunction :: Int -> Int
oldFunction = (+ 1)
{-# DEPRECATED
  oldFunction
  "Use a newer function instead. This deprecation message is intentionally long so we can see how a multi-line warning notice renders once it wraps."
  #-}
