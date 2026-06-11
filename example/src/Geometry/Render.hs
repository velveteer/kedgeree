-- | Rendering 'Shape's to simple textual descriptions.
--
-- This module imports "Geometry", so the hyperlinked-source view has
-- cross-module links to follow.
module Geometry.Render
  ( -- * Descriptions
    describe
  , describeAll

    -- * Styling
  , Style (..)
  , defaultStyle
  ) where

import Geometry (Measurable (..), Shape (..))

-- | How to render a description.
data Style = Style
  { styleUnit :: String
  -- ^ unit suffix appended to measurements, e.g. @\"cm\"@
  , stylePrecision :: Int
  -- ^ number of decimal places
  }
  deriving (Eq, Show)

-- | A reasonable default: centimetres, two decimals.
defaultStyle :: Style
defaultStyle = Style {styleUnit = "cm", stylePrecision = 2}

-- | Describe a single shape's area and perimeter.
describe :: Style -> Shape -> String
describe style shape =
  kind shape
    ++ ": area "
    ++ render (area shape)
    ++ ", perimeter "
    ++ render (perimeter shape)
  where
    kind (Circle _ _) = "circle"
    kind (Rectangle _ _) = "rectangle"
    render x = show (roundTo (stylePrecision style) x) ++ styleUnit style

-- | Describe many shapes, one per line.
describeAll :: Style -> [Shape] -> String
describeAll style = unlines . map (describe style)

roundTo :: Int -> Double -> Double
roundTo n x = fromIntegral (round (x * f) :: Integer) / f
  where
    f = 10 ^^ n
