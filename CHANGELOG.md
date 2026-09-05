# Changelog

What has shipped, newest first. Entries are grouped under the deploy that
carried them (`pnpm run deploy`); [Unreleased](#unreleased) is what is built and
merged but not yet deployed. Roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); there is no semantic
version yet, so headings are dates.

## [Unreleased]

### Added

- Message log entries now show a timestamp (`YYYY-MM-DD HH:MM`, in the viewer's
  local time zone). The date is included because a table's log persists across
  real-world days.
- New `elm-ui`-based interface (`mdgriffith/elm-ui` 1.1.8): a spare,
  paper-surfaced layout with a single slate accent, a shared `Ui` module for the
  palette / spacing / type scale, character sheets as cards, stones as chips, a
  quiet status banner that tints on failure, and a message log that stays pinned
  to the bottom on new messages.
- Composer sends on Enter as well as the Send button.
- `ROADMAP.md` and this changelog.

### Changed

- Split the client into focused modules. `client/src/Main.elm` went from a
  single ~900-line file to wiring only (`init` / `update` / `subscriptions` /
  `main`); domain types and `Model` / `Msg` moved to `Types.elm`, HTTP and
  decoders to `Api.elm`, interop to `Ports.elm`, time formatting to
  `Format.elm`, and the view to `View.elm`.
- Pinned Elm back to 0.19.1 (npm `elm@0.19.1-5`, `elm-version` `0.19.1`). The
  repo had moved to the `elm@0.19.2-0` prerelease, which local editor tooling
  (elm-language-server / Lamdera, both 0.19.1) rejects with a version mismatch.
