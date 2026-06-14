#!/usr/bin/env bash
# Build the deployed example site: a multi-package landing page themed by
# kedgeree. The hand-built demo (kedgeree-demo: Geometry + Showcase) sits
# alongside a few real Hackage libraries, so the theme is shown both on modules
# crafted to exercise every feature and on real-world docs with deep class
# hierarchies, hundreds of instances and long signatures. The Pages workflow
# runs this script. For fast theme iteration on the demo alone, use
# build-demo.sh instead.
#
# Real packages are fetched and built once into .landing-build/ (reused on
# re-runs, cached in CI), so only the first run pays the build cost.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
src="$here/src"
out="$here/site"
work="$root/.landing-build"
meta="$work/cabal-meta"

# Real Hackage packages to feature, in landing order after the demo.
hackage_pkgs=(lens aeson containers)

rm -rf "$out"
mkdir -p "$out/kedgeree-demo" "$meta"

# ---- kedgeree-demo : the hand-built modules --------------------------------
echo ">> Building kedgeree-demo (Geometry, Showcase)..."
haddock --html --hyperlinked-source --quickjump \
  --odir="$out/kedgeree-demo" \
  --package-name=kedgeree-demo --package-version=0.1.0 \
  --optghc=-i"$src" \
  "$src/Geometry.hs" "$src/Geometry/Render.hs" "$src/Showcase.hs"

# A synopsis for the demo, so its landing cell reads like the real packages'.
# The landing reads synopses from .cabal files under --project-root, so we point
# it at a small directory holding one .cabal per package.
cat > "$meta/kedgeree-demo.cabal" <<'EOF'
name:     kedgeree-demo
version:  0.1.0
synopsis: Hand-built modules exercising every corner of the theme
EOF

# ---- real Hackage packages -------------------------------------------------
for pkg in "${hackage_pkgs[@]}"; do
  pdir="$(find "$work" -maxdepth 1 -type d -name "$pkg-*" | head -1)"
  if [ -z "$pdir" ]; then
    echo ">> Fetching $pkg..."
    ( cd "$work" && cabal get "$pkg" )
    pdir="$(find "$work" -maxdepth 1 -type d -name "$pkg-*" | head -1)"
  fi
  [ -n "$pdir" ] || { echo "kedgeree: could not fetch $pkg" >&2; exit 1; }

  echo ">> Building Haddocks for $pkg (first run can take a few minutes)..."
  ( cd "$pdir" && cabal haddock --haddock-hyperlink-source --haddock-quickjump )

  doc="$(find "$pdir/dist-newstyle" -type d -path "*/doc/html/$pkg" | head -1)"
  [ -n "$doc" ] || { echo "kedgeree: no Haddock output for $pkg" >&2; exit 1; }

  mkdir -p "$out/$pkg"
  cp -R "$doc/." "$out/$pkg/"
  cp "$pdir"/*.cabal "$meta/"
done

# ---- theme everything + generate the landing -------------------------------
echo ">> Theming the tree and generating the landing page..."
pkg_flags=(--package kedgeree-demo)
for pkg in "${hackage_pkgs[@]}"; do pkg_flags+=(--package "$pkg"); done

( cd "$root" && cabal run -v0 kedgeree -- "$out" \
    --landing "kedgeree" \
    --landing-description "A modern Haddock theme. Shown here on its own demo modules and a few real-world libraries." \
    --project-root "$meta" \
    "${pkg_flags[@]}" )

echo
echo "Done. Serve it (search needs HTTP, not file://):"
echo "  python3 -m http.server -d $out   # then open http://localhost:8000"
