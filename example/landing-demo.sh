#!/usr/bin/env bash
# Demo the --landing feature. The regular example is a single package, but a
# landing page needs a multi-package tree (one subdirectory per package), so
# here we build the example modules twice under different package names, drop
# each into its own subdir, then generate a themed package landing page over the
# whole tree.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
src="$here/src"
out="$here/landing-site"

rm -rf "$out"
mkdir -p "$out/geometry" "$out/showcase"

echo ">> Building Haddocks for package 'geometry'..."
haddock --html --hyperlinked-source --quickjump \
  --odir="$out/geometry" --package-name=geometry --package-version=0.1.0 \
  --optghc=-i"$src" "$src/Geometry.hs" "$src/Geometry/Render.hs"

echo ">> Building Haddocks for package 'showcase'..."
haddock --html --hyperlinked-source --quickjump \
  --odir="$out/showcase" --package-name=showcase --package-version=0.1.0 \
  --optghc=-i"$src" "$src/Showcase.hs" "$src/Geometry.hs" "$src/Geometry/Render.hs"

echo ">> Theming the tree and generating the landing page..."
( cd "$root" && cabal run -v0 kedgeree -- "$out" --landing "Geometry Project" )

echo
echo "Done. Serve it (search needs HTTP, not file://):"
echo "  python3 -m http.server -d $out   # then open http://localhost:8000"
