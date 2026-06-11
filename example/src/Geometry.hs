{-# LANGUAGE DeriveFunctor #-}

-- | 2D geometry primitives — a small module used to show off the
-- __Kedgeree__ Haddock theme.
--
-- It exercises the things a theme has to get right: section headings,
-- data declarations with record fields, type classes with methods and
-- instances, operators, and inline @code@ / code blocks.
--
-- > let unit = Circle origin 1
-- > area unit  -- ≈ 3.14159
--
-- Bold like __this__, emphasis like /this/, and a link to 'Shape'.
module Geometry
  ( -- * Points
    Point (..)
  , origin
  , translate
  , (.+.)

    -- * Shapes
  , Shape (..)
  , circle
  , rectangle

    -- * Measuring things
  , Measurable (..)
  ) where

-- | A point in the plane.
data Point = Point
  { px :: !Double
  -- ^ the x coordinate
  , py :: !Double
  -- ^ the y coordinate
  }
  deriving (Eq, Show)

-- | The origin, @Point 0 0@.
origin :: Point
origin = Point 0 0

-- | Move a point by a delta given as another point.
--
-- @since 0.1.0
translate :: Point -> Point -> Point
translate (Point dx dy) (Point x y) = Point (x + dx) (y + dy)

-- | Infix alias for 'translate'.
(.+.) :: Point -> Point -> Point
(.+.) = translate

infixl 6 .+.

-- | A geometric shape.
data Shape
  = -- | a circle given its centre and radius
    Circle Point Double
  | -- | an axis-aligned rectangle given two opposite corners
    Rectangle Point Point
  deriving (Eq, Show)

-- | Smart constructor for a circle.
circle :: Point -> Double -> Shape
circle = Circle

-- | Smart constructor for a rectangle from its width and height,
-- anchored at the 'origin'.
rectangle :: Double -> Double -> Shape
rectangle w h = Rectangle origin (Point w h)

-- | Things that have an 'area' and a 'perimeter'.
class Measurable a where
  -- | The enclosed area.
  area :: a -> Double

  -- | The length of the boundary.
  perimeter :: a -> Double

instance Measurable Shape where
  area (Circle _ r) = pi * r * r
  area (Rectangle (Point x0 y0) (Point x1 y1)) = abs (x1 - x0) * abs (y1 - y0)

  perimeter (Circle _ r) = 2 * pi * r
  perimeter (Rectangle (Point x0 y0) (Point x1 y1)) =
    2 * (abs (x1 - x0) + abs (y1 - y0))
