#!/usr/bin/env bash
# Generate Haddock docs for the example package and apply the Kedgeree theme.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
src="$here/src"
out="$here/site"

rm -rf "$out"
mkdir -p "$out"

echo ">> Generating Haddock HTML…"
haddock \
  --html \
  --hyperlinked-source \
  --quickjump \
  --odir="$out" \
  --package-name=geometry \
  --package-version=0.1.0 \
  --optghc=-i"$src" \
  "$src/Geometry.hs" \
  "$src/Geometry/Render.hs" \
  "$src/Showcase.hs"

echo ">> Applying the Kedgeree theme…"
( cd "$root" && cabal run -v0 kedgeree -- "$out" )

echo
echo "Done. Serve it (search needs HTTP, not file://):"
echo "  python3 -m http.server -d $out   # then open http://localhost:8000"
