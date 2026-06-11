#!/usr/bin/env bash
# Screenshot a themed Haddock page with headless Chrome, for eyeballing the
# theme during development.
#
#   ./example/screenshot.sh <url-or-file> [out.png] [width] [height]
#   ./example/screenshot.sh example/site/Showcase.html shot.png 1300 5200
#
# Notes on the flags below:
#   - Chrome's new headless hangs on --screenshot unless the compositor is
#     forced, hence --run-all-compositor-stages-before-draw plus a
#     --virtual-time-budget. We also guard with a self-kill timeout, because
#     Chrome can keep running after the PNG is written.
#   - It captures the page from the TOP. Scrolled-down or #anchored states come
#     back blank in this headless, so make the window tall enough to capture the
#     whole page in one shot rather than trying to scroll.
#   - This headless defaults to prefers-color-scheme: dark, so an "auto" themed
#     page renders dark. Theme with --default-theme light / dark to pin it.
set -euo pipefail

target="${1:?usage: screenshot.sh <url-or-file> [out.png] [width] [height]}"
out="${2:-screenshot.png}"
width="${3:-1300}"
height="${4:-3000}"

# Resolve a bare path to a file:// URL.
case "$target" in
  http://* | https://* | file://*) url="$target" ;;
  /*) url="file://$target" ;;
  *) url="file://$(cd "$(dirname "$target")" && pwd)/$(basename "$target")" ;;
esac

# Find a Chrome or Chromium binary.
chrome=""
for c in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "$(command -v google-chrome || true)" \
  "$(command -v chromium || true)" \
  "$(command -v chromium-browser || true)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then chrome="$c"; break; fi
done
[ -n "$chrome" ] || { echo "screenshot.sh: no Chrome/Chromium found" >&2; exit 1; }

prof="$(mktemp -d)"
trap 'rm -rf "$prof"' EXIT
rm -f "$out"

"$chrome" --headless=new --no-sandbox --user-data-dir="$prof" \
  --run-all-compositor-stages-before-draw --virtual-time-budget=8000 \
  --hide-scrollbars --window-size="$width,$height" \
  --screenshot="$out" "$url" >/dev/null 2>&1 &
pid=$!

# Poll for the file, then stop Chrome (it may hang after writing).
i=0
while [ "$i" -lt 20 ] && [ ! -s "$out" ]; do sleep 1; i=$((i + 1)); done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

if [ -s "$out" ]; then
  echo "wrote $out (${width}x${height}, $(wc -c < "$out" | tr -d ' ') bytes)"
else
  echo "screenshot.sh: failed, no output written" >&2
  exit 1
fi
