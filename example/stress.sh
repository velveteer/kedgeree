#!/usr/bin/env bash
# Build a real Hackage package's Haddocks and theme them with kedgeree, as a
# stress test against complex real-world docs: deep class hierarchies, hundreds
# of instances, long constraint contexts and optic signatures.
#
#   ./example/stress.sh            # defaults to lens
#   ./example/stress.sh aeson
#   ./example/stress.sh lens ~/tmp/lens-docs
#
# Building a big package's docs (and its dependencies') can take several minutes
# the first time.
set -euo pipefail

pkg="${1:-lens}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
work="${2:-$root/stress}"

rm -rf "$work"
mkdir -p "$work"

echo ">> Fetching $pkg..."
( cd "$work" && cabal get "$pkg" )
src="$(find "$work" -maxdepth 1 -type d -name "$pkg-*" | head -1)"
[ -n "$src" ] || { echo "kedgeree: could not fetch $pkg" >&2; exit 1; }

echo ">> Building Haddocks for $pkg (this can take a few minutes)..."
( cd "$src" && cabal haddock --haddock-hyperlink-source --haddock-quickjump )

doc="$(find "$src/dist-newstyle" -type d -path "*/doc/html/$pkg" | head -1)"
[ -n "$doc" ] || { echo "kedgeree: no Haddock output found under $src" >&2; exit 1; }

echo ">> Theming with kedgeree..."
( cd "$root" && cabal run -v0 kedgeree -- "$doc" )

echo
echo "Done. Serve it (search needs HTTP, not file://):"
echo "  python3 -m http.server -d $doc   # then open http://localhost:8000"
