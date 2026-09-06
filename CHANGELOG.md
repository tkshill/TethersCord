# Changelog

What has shipped, newest first. Entries are grouped under the deploy that
carried them (`pnpm run deploy`); [Unreleased](#unreleased) is what is built and
merged but not yet deployed. Roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); there is no semantic
version yet, so headings are dates.

## [Unreleased]

### Added

- Character sheets are shown one at a time behind a tab strip (`Model.selectedSlot`)
  instead of three columns that collapsed to a cramped stack. Claiming a sheet
  brings its tab forward.
- A character's boons now render as a row of circles at the top of the sheet,
  above the text fields, so a player sees their spendable stones in the context
  of the current roll. Boons pledged into the next roll are marked with a centre
  dot rather than a separate "Pledged" count, and the roll panel likewise draws
  pledged boons as marked stones in the bag instead of a "(N boon pledged)"
  caption. The sheet's `+` / `−` controls are now labelled "Grant" (facilitator)
  and "Pledge" (owner).
- Session history: the Session card now lists the table's completed sessions
  (start date, goal, and met / partial / failed outcome), newest first. The
  worker reads the last twenty `game_sessions` rows into a new
  `GameState.sessionHistory`, seeded on Durable Object start and refreshed when a
  session ends.
- Characters can pledge their boons into a roll: a "Pledged" control on each
  sheet (`POST /api/table/:id/stones/commit`), tracked in
  `GameState.committedBoons`. A roll draws two stones at random from the shared
  pool plus every pledged boon, so pledging shifts the odds toward Boon;
  accepting the roll spends the pledged boons from each character's stock.
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

- Stones now name their outcome instead of a colour: `Boon` (favourable) and
  `Bane` replace `WhiteStone` / `BlackStone` across the client, the worker, and
  the `"Boon" | "Bane"` wire format. Durable Object stone storage is migrated
  from the old names as it loads. `Ui.stoneChip` renders a filled circle with a
  caption rather than a colour-swatch pill, and a character's `fate` count is
  now labelled "Boons". The `add-white` stone route is renamed `add-boon`.
- Split the client into focused modules. `client/src/Main.elm` went from a
  single ~900-line file to wiring only (`init` / `update` / `subscriptions` /
  `main`); domain types and `Model` / `Msg` moved to `Types.elm`, HTTP and
  decoders to `Api.elm`, interop to `Ports.elm`, time formatting to
  `Format.elm`, and the view to `View.elm`.
- Pinned Elm back to 0.19.1 (npm `elm@0.19.1-5`, `elm-version` `0.19.1`). The
  repo had moved to the `elm@0.19.2-0` prerelease, which local editor tooling
  (elm-language-server / Lamdera, both 0.19.1) rejects with a version mismatch.
