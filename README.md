<div align="center">

# kedgeree

<img src="logo.png" alt="Kedgeree" width="120" />

Haskell documentation made _delicious_

</div>


---

## What it does

`kedgeree` is a tiny post-processor. You generate Haddock HTML the normal way,
then run `kedgeree` on the output directory. It drops in a modern CSS + JS theme
and rewrites each page's `<head>` to load it. No Haddock fork, no plugin.

It is **idempotent** (safe to re-run) and walks directories **recursively**, so
it themes a single package *or* a whole `cabal haddock-project` tree.

## Install

```sh
cabal install kedgeree
```

Kedgeree is a single self-contained binary, with the theme assets embedded.

## Usage

### A single package

```sh
cabal haddock --haddock-hyperlink-source --haddock-quickjump
# point kedgeree at the generated html directory, e.g.
kedgeree dist-newstyle/build/*/ghc-*/<pkg>-*/doc/html/<pkg>
```

### A whole project (`haddock-project`)

```sh
cabal haddock-project --local
kedgeree ./haddocks
```

### Plain Haddock (no cabal)

```sh
haddock --html --hyperlinked-source --quickjump --odir=out *.hs
kedgeree out
open out/index.html
```

> **Tip:** `--hyperlinked-source` enables the source pages and `--quickjump`
> emits the `doc-index.json` that powers search. Both are recommended.
>
> The keyboard-search overlay fetches `doc-index.json`, so it needs the docs
> served over HTTP(S). Opened straight from disk
> (`file://`) it falls back to Haddock's static index page.

## Options

```
kedgeree [OPTIONS] DOC_HTML_DIR

  --default-theme auto|light|dark   Theme before the visitor chooses (default: auto)
  --accent CSSCOLOR                 Override the accent color
  --font FAMILY                     Override the UI/prose font-family
  --mono-font FAMILY                Override the monospace font-family
  --no-source                       Don't theme the hyperlinked-source pages
  --show-module-info                Show the module-info badge (Safe Haskell etc.), off by default
  --force                           Re-theme pages already themed at this version
```

Kedgeree bundles **IBM Plex Sans** (UI/prose) and **JetBrains Mono** (code)
(~120 KB total), so pages render fully offline with a consistent, modern look
on every platform. Override either with `--font` / `--mono-font` (any CSS
font-family list). By default the external Google Fonts link Haddock emits is
stripped. MathJax is left untouched.

## Develop

```sh
cabal build
./example/build-demo.sh                 # generate themed docs for the example package
python3 -m http.server -d example/site  # then open http://localhost:8000
```

The `example/` package exercises sections, records, classes, instances,
operators and source rendering: a good page to iterate the theme against.
