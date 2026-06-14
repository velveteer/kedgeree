#!/usr/bin/env bash
# Demo the real `cabal haddock-project` -> kedgeree flow. We scaffold a tiny
# 3-package cabal project (acme-widgets <- acme-gadgets <- acme-app, sharing a
# Renderable class across packages), let cabal build the multi-package doc tree
# for us, then theme it and generate the landing page. No bespoke assembly.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
proj="$here/hp-demo"

rm -rf "$proj"
mkdir -p "$proj/acme-widgets/src/Acme" \
         "$proj/acme-gadgets/src/Acme" \
         "$proj/acme-app/src/Acme"

cat > "$proj/cabal.project" <<'EOF'
packages: acme-widgets acme-gadgets acme-app
EOF

# ---- acme-widgets : the core package ---------------------------------------
cat > "$proj/acme-widgets/acme-widgets.cabal" <<'EOF'
cabal-version:      2.4
name:               acme-widgets
version:            0.1.0
synopsis:           Core widget types and rendering
build-type:         Simple
library
  hs-source-dirs:   src
  exposed-modules:  Acme.Widget
  build-depends:    base
  default-language: Haskell2010
EOF
cat > "$proj/acme-widgets/src/Acme/Widget.hs" <<'EOF'
-- | Core widget types and the 'Renderable' class.
module Acme.Widget
  ( Widget (..)
  , Renderable (..)
  , defaultWidget
  ) where

-- | A user-interface widget.
data Widget
  = Button String
  | Slider Int Int
  deriving (Show, Eq)

-- | Things that can be rendered to a 'String'. Implemented across the other
-- packages too, so the instance list links between packages.
class Renderable a where
  render :: a -> String

instance Renderable Widget where
  render (Button label) = "[" ++ label ++ "]"
  render (Slider lo hi) = show lo ++ ".." ++ show hi

-- | A sensible default 'Widget'.
defaultWidget :: Widget
defaultWidget = Button "OK"
EOF

# ---- acme-gadgets : depends on acme-widgets --------------------------------
cat > "$proj/acme-gadgets/acme-gadgets.cabal" <<'EOF'
cabal-version:      2.4
name:               acme-gadgets
version:            0.1.0
synopsis:           Gadgets assembled from widgets
build-type:         Simple
library
  hs-source-dirs:   src
  exposed-modules:  Acme.Gadget
  build-depends:    base, acme-widgets
  default-language: Haskell2010
EOF
cat > "$proj/acme-gadgets/src/Acme/Gadget.hs" <<'EOF'
-- | A 'Gadget' wraps a 'Widget' with a label.
module Acme.Gadget
  ( Gadget (..)
  , wrap
  ) where

import Acme.Widget (Renderable (..), Widget)

-- | A labelled wrapper around a 'Widget'.
data Gadget = Gadget
  { gadgetWidget :: Widget
  , gadgetLabel :: String
  }

instance Renderable Gadget where
  render (Gadget w l) = l ++ ": " ++ render w

-- | Wrap a 'Widget' into a labelled 'Gadget'.
wrap :: String -> Widget -> Gadget
wrap = flip Gadget
EOF

# ---- acme-app : depends on both -------------------------------------------
cat > "$proj/acme-app/acme-app.cabal" <<'EOF'
cabal-version:      2.4
name:               acme-app
version:            0.1.0
synopsis:           Demo application tying the packages together
build-type:         Simple
library
  hs-source-dirs:   src
  exposed-modules:  Acme.App
  build-depends:    base, acme-widgets, acme-gadgets
  default-language: Haskell2010
EOF
cat > "$proj/acme-app/src/Acme/App.hs" <<'EOF'
-- | The demo application entry point.
module Acme.App
  ( app
  , demo
  ) where

import Acme.Gadget (Gadget, wrap)
import Acme.Widget (Renderable (..), defaultWidget)

-- | Render and print the 'demo' gadget.
app :: IO ()
app = putStrLn (render demo)

-- | A demo 'Gadget' built from the default widget.
demo :: Gadget
demo = wrap "panel" defaultWidget
EOF

echo ">> cabal haddock-project (builds the multi-package doc tree)..."
# --hackage links dependency docs (base, ...) to Hackage instead of building
# them, so we only build our three packages. haddock-project hyperlinks source
# by default; --quickjump (for kedgeree's search) is passed through to haddock.
# Default output is ./haddocks.
( cd "$proj" && cabal haddock-project --hackage --haddock-options=--quickjump )

doc="$proj/haddocks"
echo ">> theming the tree + generating the landing page..."
( cd "$root" && cabal run -v0 kedgeree -- "$doc" --landing "Acme" )

echo
echo "Tree that cabal produced (one subdir per package + an index):"
( cd "$doc" && ls -1 )
echo
echo "Serve it (search needs HTTP, not file://):"
echo "  python3 -m http.server -d $doc   # then open http://localhost:8000"
