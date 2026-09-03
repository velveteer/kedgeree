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
