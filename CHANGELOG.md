# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.0 — unreleased

Initial release.

- Themes a directory of Haddock HTML in place: light/dark/auto color scheme,
  sticky sidebar with scroll-spy, keyboard search overlay, bundled IBM Plex
  Sans and JetBrains Mono, and restyled hyperlinked-source pages.
- Walks directories recursively, so it handles a single package or a whole
  `cabal haddock-project` / `stack haddock` tree.
- `--landing` generates a themed front page for a multi-package tree, with
  package synopses read from the project's `.cabal` files.
- Idempotent and version-aware: re-running is a no-op, and a page themed by an
  older version is re-themed.
- Options to override the accent color and fonts, hide the module-info badge,
  and skip the source pages.
- Long signatures break at their operators only when they do not fit the
  column (a container query), so most read on one line at desktop width.
- Readable defaults: a 40rem prose measure, quiet inline code, full-contrast
  sub-item docs, a heading outline (module title as `h1`, sections as `h2`),
  and a print stylesheet.
- Accessible controls: every collapse toggle is a focusable button with
  `aria-expanded`, the sidebar precedes the content in tab order and follows
  the reader, and section headings show their anchor on hover.
