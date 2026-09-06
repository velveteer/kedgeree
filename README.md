<h1 align="center">
  <img src="https://raw.githubusercontent.com/velveteer/kedgeree/main/logo.png" alt="Kedgeree" width="96" /><br>
  kedgeree
</h1>

<p align="center">Haskell documentation made <em>delicious</em></p>

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

Generate Haddock HTML the way you normally do, then point `kedgeree` at the
output directory. It rewrites every page in place and drops the shared theme
assets alongside them.

### Cabal, a single package

```sh
cabal haddock --haddock-hyperlink-source --haddock-quickjump
# cabal prints "Documentation created: <dir>". Theme that directory:
kedgeree dist-newstyle/build/*/ghc-*/<pkg>-*/doc/html/<pkg>
```

### Cabal, a whole project

`cabal haddock-project` builds the multi-package layout for you, one
subdirectory per package plus an index, with no manual assembly.

```sh
cabal haddock-project --hackage --haddock-options=--quickjump
kedgeree ./haddocks --landing "My project"
```

`--hackage` documents your packages and links their dependencies to Hackage.
`--landing` writes a themed front page listing the packages (see below), each
with the one-line `synopsis` read from its `.cabal`. Leave `--landing` off and
kedgeree simply themes the index `haddock-project` already wrote.

### Stack

```sh
stack haddock --haddock-arguments "--quickjump"
kedgeree "$(stack path --local-doc-root)" --landing "My project"
```

`stack haddock` hyperlinks source by default and writes one subdirectory per
package under the local doc root. Add `--haddock-deps` to document dependencies
too, then use `--package` to keep the landing to your own packages.

### Plain Haddock

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
  --landing TITLE                   Generate a landing page (index.html) for a multi-package tree
  --landing-description TEXT        One-line project description shown under the landing title
  --package NAME                    Curate and order the --landing list (repeatable)
  --project-root DIR                Override the auto-detected project root for landing synopses
```

### A multi-package landing page

For a tree with one subdirectory per package (a `haddock-project` build, or
docs assembled by hand), `--landing` writes a themed `index.html` at the root
that lists every package and links to its docs:

```sh
kedgeree ./site --landing "My project"
```

By default it lists every package directory it finds, alphabetically. Pass
`--package` (repeatable) to choose exactly which packages appear, in the order
you give, so internal packages like test or bench suites can be left off:

```sh
kedgeree ./site --landing "My project" \
  --package project-core \
  --package project-pkg \
  --package project-acme
```

Each package's one-line description comes from the `synopsis` field of its
`.cabal`, matched by package name. Kedgeree finds the sources automatically by
walking up from the doc tree to the nearest `cabal.project`, `stack.yaml`, or
`.cabal`, so no flag is needed when the docs live inside the project. Pass
`--project-root DIR` only to point it somewhere else. Packages with no synopsis
just show the name.

Add `--landing-description "..."` for a one-line description of the project
itself, shown under the title:

```sh
kedgeree ./site --landing "My project" \
  --landing-description "A short tagline for the whole project."
```

Kedgeree bundles **IBM Plex Sans** (UI/prose) and **JetBrains Mono** (code)
(~120 KB total), so pages render fully offline with a consistent, modern look
on every platform. Override either with `--font` / `--mono-font` (any CSS
font-family list). By default the external Google Fonts link Haddock emits is
stripped. MathJax is left untouched.

## Develop

```sh
cabal build
cabal test                              # golden + unit tests
./example/build-demo.sh                 # themed docs for the demo modules only (fast)
python3 -m http.server -d example/site  # then open http://localhost:8000
```

The demo modules exercise sections, records, classes, instances, operators and
source rendering: a good page to iterate the theme against, and `build-demo.sh`
rebuilds them in a second or two.

`./example/build-site.sh` builds the deployed site instead: a multi-package
landing with `kedgeree-demo` alongside a few real Hackage libraries (lens,
aeson, containers), so the theme is shown on real-world docs too. The first run
builds those packages (cached afterwards under `.landing-build/`). This is what
the Pages workflow publishes.

### Layout

| Module | Role |
| --- | --- |
| `Kedgeree.Haddock` | Every id, class and tag shape assumed of Haddock's HTML. Start here when a Haddock release changes its markup. |
| `Kedgeree.Html` | Generic text-level HTML editing. |
| `Kedgeree.Inject` | The `<head>` injection, version stamp, and re-run clearing. |
| `Kedgeree.Assets` | The theme assets (CSS, JS, fonts, icons, favicon), embedded at build time. |
| `Kedgeree.Chrome` | Server-rendered header, Instances control and sidebar. |
| `Kedgeree.Sidebar` | Sidebar nav, parsed with tagsoup and rendered with lucid. |
| `Kedgeree.Signature` | Source-link grouping, argument inlining, long-signature breaking. |
| `Kedgeree.Rewrite` | The per-page pipeline. |
| `Kedgeree.Landing` | The `--landing` page and `.cabal` synopsis discovery. |
| `Kedgeree.Process` | Directory walk, concurrency, progress, asset writing. |

### Tests

`test/fixtures/` holds unmodified Haddock output for the demo modules. Each
golden test themes a fixture and compares it with `test/golden/`. After an
intentional change to the output:

```sh
cabal run kedgeree-test -- --accept
git diff test/golden
```

The suite also checks that re-running on themed output is a no-op, that a page
themed by an older version (or with `--force`) is re-themed to exactly the fresh
output, and unit-tests the Haddock probes and text helpers.
