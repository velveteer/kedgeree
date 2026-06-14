{-# LANGUAGE OverloadedStrings #-}

-- | @kedgeree@ — apply a modern theme to a directory of Haddock HTML.
module Main (main) where

import qualified Data.Text as T
import Options.Applicative

import Kedgeree.Process (Options (..), run)

main :: IO ()
main = run =<< execParser parserInfo

parserInfo :: ParserInfo Options
parserInfo =
  info
    (optionsParser <**> helper)
    ( fullDesc
        <> header "kedgeree - a modern theme for Haddock documentation"
        <> progDesc
          "Post-process a directory of generated Haddock HTML in place: \
          \inject a modern light/dark/auto theme, a sticky sidebar, keyboard \
          \search, and polished source pages."
    )

optionsParser :: Parser Options
optionsParser =
  Options
    <$> argument
      str
      ( metavar "DOC_HTML_DIR"
          <> help "Directory of generated Haddock HTML (e.g. the doc/html/<pkg> dir)."
      )
    <*> ( T.pack
            <$> strOption
              ( long "default-theme"
                  <> metavar "auto|light|dark"
                  <> value "auto"
                  <> showDefault
                  <> help "Theme used before the visitor chooses one."
              )
        )
    <*> optional
      ( T.pack
          <$> strOption
            ( long "accent"
                <> metavar "CSSCOLOR"
                <> help "Override the accent color (any CSS color)."
            )
      )
    <*> optional
      ( T.pack
          <$> strOption
            ( long "font"
                <> metavar "FAMILY"
                <> help "Override the UI/prose font-family (CSS font-family list)."
            )
      )
    <*> optional
      ( T.pack
          <$> strOption
            ( long "mono-font"
                <> metavar "FAMILY"
                <> help "Override the monospace font-family (CSS font-family list)."
            )
      )
    <*> switch
      ( long "no-source"
          <> help "Do not theme the hyperlinked-source pages under src/."
      )
    <*> ( not
            <$> switch
              ( long "show-module-info"
                  <> help "Show Haddock's module-info badge (Safe Haskell, Language, Extensions). Hidden by default."
              )
        )
    <*> switch
      ( long "force"
          <> help "Re-theme pages already themed at this version (e.g. after changing options)."
      )
    <*> optional
      ( T.pack
          <$> strOption
            ( long "landing"
                <> metavar "TITLE"
                <> help
                  "Generate a themed landing page (index.html) at the root listing every \
                  \package subdirectory, headed by TITLE. For multi-package trees."
            )
      )
    <*> many
      ( T.pack
          <$> strOption
            ( long "package"
                <> metavar "NAME"
                <> help
                  "Restrict and order the --landing list to this package directory \
                  \(repeatable). Omit to list all discovered packages alphabetically."
            )
      )
    <*> optional
      ( strOption
          ( long "project-root"
              <> metavar "DIR"
              <> help
                "Override the auto-detected project root used to read package \
                \synopses for the --landing page. Normally found by walking up \
                \from the doc tree to the nearest cabal.project / stack.yaml / .cabal."
          )
      )
    <*> optional
      ( T.pack
          <$> strOption
            ( long "landing-description"
                <> metavar "TEXT"
                <> help "A one-line project description shown under the --landing page title."
            )
      )
