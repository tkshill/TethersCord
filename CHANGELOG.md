# Changelog

What has shipped, newest first. Entries are grouped under the deploy that
carried them (`pnpm run deploy`); [Unreleased](#unreleased) is what is built and
merged but not yet deployed. Roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); there is no semantic
version yet, so headings are dates.

## [Unreleased]

### Added

- The overcome aftermath — aspects and a single persistent stone pool:
  - **Aspects accumulate Banes.** A mixed overcome roll (one Boon, one Bane)
    drops the Bane onto one of the acting character's three aspects —
    Archetype / Desire / Quest — at random, and returns the Boon to the pool.
    New `archetype_banes` / `desire_banes` / `quest_banes` columns on
    `characters` (migration `0009`); the counts show as dots beneath each
    aspect on the sheet. Two Boons or two Banes both return to the pool whole.
  - **One shared stone pool, never reset.** The roll bag and the old
    per-session pool are now the same pool (`gameState.stonePool`). A roll's
    two drawn stones leave the pool and only the routed subset returns —
    there is no more wholesale reset on accept. Session goals are plain text
    with no roll or verdict; ending a session (`POST /api/table/:id/session/end`)
    only tops the pool back up to at least two Boon and two Bane if either has
    run short, so overcomes can draw the pool down without a facilitator ever
    running dry.
  - Retired: the session-end verdict (met / failed), the carried-Bane count,
    and the untethering / reckoning mechanic that followed a failed goal.
    Aspect Banes still accumulate; nothing currently clears them.
- NPCs and locations (roadmap section 13). Two new facilitator-owned reference
  collections, backed by the `npcs` / `locations` D1 tables (migration `0008`,
  scoped by `session_id` like `characters`) and carried in
  `GameState.npcs` / `GameState.locations`. Facilitator-only routes
  `POST /api/table/:id/{npcs,locations}` (create a blank row),
  `.../:entityId/update` (name + notes), and `.../:entityId/delete`. The client
  shows an "NPCs" card and a "Locations" card: an editable list with Add and
  Delete for the facilitator, a plain read-only list for players (hidden while
  empty). First cut is name + notes only.
- Mid-session goal edits (roadmap section 12). A new facilitator-only
  `POST /api/table/:id/session/goal` rewrites the running session's goal; the
  Session card shows an editable goal field for the facilitator, behind the same
  confirm step as End session.
- Proposal withdraw (roadmap section 12). `POST /api/table/:id/proposals/:id/withdraw`
  lets the proposer pull back their own still-pending proposal (gated on the
  proposer, not the facilitator). A "withdraw" link sits beside every "(pending)"
  hint — Add boon, Highlight, the once-per-session abilities, Suggest Compel, and
  Accept Compel — and pulls the proposer's most recent proposal of that kind.

### Added

- **Glossary terms, in-place tooltips, and a "How to play" card** (roadmap
  section 21, steps 2–4).
  - `client/src/Copy/Terms.elm` holds the game's ~30 player-facing terms, each
    with a one-line gloss and a two-to-three-sentence definition.
  - `Ui.withTip` attaches a native browser tooltip (the HTML `title` attribute)
    to an element; the card titles Session / Stones / Characters, the aspect and
    Condition fields, "Highlight", "Session pool", "Floating boons", the
    open-overcome line, and the once-per-session / compel move buttons now carry
    the matching gloss on hover.
  - `View.Guide` is a new section card at the foot of the Activity — collapsed
    by default (`Model.guideExpanded`, `ToggleGuide`), it lays out every term
    grouped in order of play. It is the path for touch, where `title` tooltips
    do not fire.
- **Aspect examples for character creation** (roadmap section 21, step 5).
  `ASPECTS.md` at the repo root is a bank of example Archetypes, Desires, and
  Quests with guidance on writing strong ones and a set of worked characters.
  A curated subset (`Copy.aspectExamples`) shows in the Activity under a "see
  examples" toggle on each aspect field while the sheet is editable
  (`Model.aspectExamplesOpen`, `ToggleAspectExamples`, one open at a time).

### Changed

- **Player-facing copy pulled into one `client/src/Copy.elm`** (roadmap section
  21, step 1). Every card title, hint line, empty state, placeholder, proposal
  description, connection note, and game-action button label the view rendered
  as a string literal is now a named constant (or a small formatting function
  where a value is spliced in), grouped by card. `View.elm` and every `View/*`
  module read from `Copy`; structural field labels that are not game vocabulary
  ("Name", "Notes") stay inline. No behaviour change — the client bundle and the
  Elm test suite are the gate.
- Maintainability pass — client quick wins (roadmap section 22, step 1). No
  behaviour change; the client bundle, both typecheckers, and both test suites
  are the gate.
  - **`Api.elm` collapsed behind three request helpers** — `get` / `postEmpty`
    / `postJson` — that own the URL shape, auth header, JSON content type,
    `expect`, and timeout / tracker. Each of the 24 endpoints is now one line
    over them.
  - **The ten acknowledge-only mutation results merged into one `MutationDone`
    message** carrying a `{ family, failMsg }` record, replacing
    `StonesUpdated` / `SessionUpdated` / `EntityMutated` and seven siblings
    along with their per-result `update` branches and `Effect` wiring.
  - **`View.view` unwraps `Maybe GameState` once** into a single loading
    branch; the section functions now take `GameState`, dropping their repeated
    `case maybeGs of Nothing …` blocks.
  - **`Format.pluralize`** replaces the inline `"Bane" ++ (if n == 1 …)`
    pattern, and **`Types.characterAtSlot`** is the one shared slot lookup for
    `Main` and `View`.
- Maintainability pass — typed proposal / ability kinds (roadmap section 22,
  step 2). A new `Kind.elm` module gives the client `ProposalKind` and
  `AbilityKind` custom types with decoders, at parity with the Worker's
  `types.ts` unions. `Proposal.kind` and `UsedAbility.kinds` are typed rather
  than raw strings, `Msg.UseAbility` carries an `AbilityKind`, and
  `View.describeProposal` is now a total `case` with no string fall-through, so
  a new kind produces a compile error at every site that must handle it. No
  behaviour change.
- Maintainability pass — structured session outcome (roadmap section 22,
  step 3). The broadcast `SessionSummary` gains an additive
  `outcomeKind : "met" | "failed" | "partial"`, derived from the existing
  `outcome` sentence in `loadSessionHistory` (no D1 column, no migration). The
  client decodes it to a `SessionOutcome` type and `View.verdictWord` /
  `verdictColor` switch on it instead of parsing the prose with
  `String.contains`. No behaviour change.
- Maintainability pass — client TS tidy-up (roadmap section 22, step 7). The
  three hand-copied Elm-port shapes (`DiscordBridge.ts`, `GameSocket.ts`,
  `main.ts`) are one `client/src/ports.ts` (`ElmPorts` + a `SocketPorts`
  pick), which also declares `Window.DISCORD_CLIENT_ID` /
  `Window.BACKEND_BASE_URL` so the `(window as any)` reads are typed. No
  behaviour change.
- Maintainability pass — `GameTable.ts` trailer and accessor cleanup (roadmap
  section 22, step 6 part 1). No behaviour change; the module reshaping (a
  route table, `worker/src/handlers/*`) is deferred to its own effort.
  - **`private get game()`** replaces the ~85 `this.gameState!` non-null
    assertions with one.
  - **`commit(next, logLine?)`** folds the shared handler trailer
    (`gameState = …` → `saveStoneState` → optional `appendMessage` →
    `broadcast` → `204`); every mutating handler now ends in one
    `return this.commit(…)`.
  - **`loadInitialState` runs its six independent cold-start reads through
    `Promise.all`** instead of in series — the Free-tier cold path.
- Maintainability pass — worker pure-logic extraction (roadmap section 22,
  step 5). `GameTable.ts` sheds three files' worth of code with no behaviour
  change:
  - **`worker/src/gameLogic.ts`** — the pure rules helpers (`applyPledge`,
    `routeOvercomeDraw`, `aspectBaneBag`, `markAbilityUsed`,
    `clearSlotPendingState`, `pickTwoRandom`, `randomInt`, `describeStones`,
    `characterLabel`, `totalCommittedBoons`), now unit-tested directly in
    `worker/test/gameLogic.test.ts`.
  - **`worker/src/characters.ts`** — every write to the `characters` table
    behind a named helper (`setFate`, `setOwner`, `incrementAspectBane`,
    `clearAspectBanes`, `updateFields`, `rowToCharacterSheet`); the four
    copies of `UPDATE characters SET fate = ?` are now one path.
  - **`worker/src/migrateStoneState.ts`** — the `KEY_STONES` load-time
    compatibility handling (colour-named stones, defaulted fields) as a pure
    `migrateStoneState(stored, initialPool)`.
- Maintainability pass — `View.elm` split (roadmap section 22, step 4). The
  ~1500-line single view module is now a thin `View.elm` shell (the page
  frame, `header`, `connectionNote`, `composer`, and the ordered section list)
  over six per-section modules under `client/src/View/` — `Session`, `Stones`,
  `Characters`, `Log`, `Moves`, `Entities` — and a shared `View/Helpers.elm`. A
  `ViewContext` record (`facilitator` / `myId` / `zone`), computed once, is
  threaded to each section in place of the old positional argument chains;
  `press` and `onlyWhen` moved to `Ui.elm`. Largest view module is now ~330
  lines. No behaviour change.
- Storage and write economy (roadmap section 16):
  - **`saveStoneState` skips the write when nothing changed.** The stone slice
    is serialised and compared to the last write (seeded from the cold-start
    load); a byte-identical slice is not re-persisted, so a chat post and other
    stone-inert mutations no longer rewrite the `KEY_STONES` blob.
  - **The hourly cron now prunes old messages.** `pruneOldMessages`
    (`worker/src/maintenance.ts`) deletes `messages` rows older than 30 days so
    the table cannot grow unbounded toward the account SQLite cap.
- Snappier realtime updates (roadmap section 15):
  - **The connect snapshot and every broadcast now carry only the last 50
    messages** (`MESSAGE_WINDOW`), not 200 — a smaller payload and a smaller
    re-render on every table action. A new read-only
    `GET /api/table/:id/messages/history?before=<createdAt>` returns the
    preceding page, behind a "Load earlier messages" affordance at the top of
    the log. Supersedes the section 7 pagination note.
  - **The message log renders behind `Element.Lazy`**, so a re-render that does
    not change `messages` (typing in the composer, arming a confirm, switching a
    character tab) no longer refolds the speaker-colour map and the day-divided
    rows over the whole list.
  - **Buttons that raise a proposal or move flip to a disabled/pending state on
    click** rather than after the round-trip (delivered by the section 14
    in-flight de-duplication; wired for the roll panel and the proposal queue).
- Fewer counted requests per action, to stay well inside the Cloudflare Free
  budget (roadmap section 14):
  - **Cold launch.** The client no longer spends an HTTP `getGameState` on the
    happy path. The live socket sends a full snapshot before its first `await`,
    so the seed load is now only a fallback fired ~3 s later if no snapshot has
    arrived; the old immediate fetch plus 3×/2 s retry loop is gone. Saves one
    to four requests per launch.
  - **Character sheets and reference rows** save once, debounced ~1 s after the
    last keystroke (and on tab-away), as a single write per dirty sheet — not
    one `POST /characters/:slot/update` per field blur. NPC / location edits
    debounce the same way.
  - **Every mutation is de-duplicated in flight**: an action whose request has
    not yet come back is a no-op on a second click, and its button renders
    disabled. This also closes the double-roll / double-proposal holes from the
    September audit.
  - **Highlight +/- taps coalesce** into one `/stones/commit` carrying the net
    delta after a short pause, rather than one proposal per tap. `/stones/commit`
    now accepts any non-zero integer `delta` (was ±1 only); `applyPledge` already
    clamps the effect to `[0, fate]`.
  - **The Durable Object caches the auth lookup.** `getAuthFromToken`'s
    `sessions_auth` ⋈ `facilitators` query ran on every `/api/table/*` call; a
    resolved token → `AuthInfo` is now memoised in DO memory for 60 s, so it is
    one D1 read per token per minute.
- Ending a session now discards **every** unresolved pending state, not just
  floating boons and used abilities: an open overcome, a roll left on the table,
  pledged boons, and any proposal the facilitator never resolved. Starting a
  session clears pledges and the proposal queue too. Nothing from a closed
  session carries into the next one (roadmap section 12).
- End session and Clear log now take a confirm step — the button arms on the
  first click and performs on the second, with a Cancel beside it (roadmap
  section 12).
- Claiming or releasing a character sheet now clears that slot's pledged boons
  and any proposal aimed at it, so a sheet changing hands can no longer leave an
  accepted roll or proposal spending the wrong character's boons (roadmap
  section 12).
- The status line is split in two: a quiet steady-state line (auth, "Connected.")
  and a separate red error line for per-action failures that dismisses itself
  after a few seconds. The Add a Detail / Gain Insight context note is now
  per-proposal rather than one field shared across the queue (roadmap section 12).

### Fixed

- `POST /stones/accept` with no roll on the table now returns 400 instead of
  silently resetting the pool and dropping the proposal queue (roadmap
  section 12).
- Accepting a proposal whose target character or floating boon has since gone
  now returns an error and leaves the proposal queued, rather than removing it
  with no effect and no log line (roadmap section 12).

- A test suite (roadmap section 11). `pnpm run test` runs the client suite
  (`elm-test` over `client/tests/`: `Api.decodeGameState` against a full wire
  snapshot, `Main.applyServerState`'s edit-cursor merge, `Main.update` guards
  and the `Effect` each `Msg` yields, the `Format` / `Roll` helpers) then the
  worker suite (`vitest` via `@cloudflare/vitest-pool-workers` over
  `worker/test/`, running inside `workerd` with a real `GameTable` Durable
  Object and a migrated D1: the `index.ts` proxy, the auth / facilitator /
  roll gates, the proposal / session / ability state machine, `withLock`
  serialisation, and `oauth-discord`). It is folded into `pnpm run build`
  after `typecheck`, and a new `.github/workflows/ci.yml` runs `pnpm run build`
  on push and PR — the project's first CI. `avh4/elm-program-test` is still to
  come.
- `DESIGN_PRINCIPLES.md` — the ten core design principles the game is measured
  against, recorded as a stable reference alongside the forward-looking
  `ROADMAP.md` and the historical `CHANGELOG.md`.
- Player moves and abilities (roadmap section 10). A new **Moves** card offers
  each player, once they hold a sheet: the once-per-session abilities **Help
  Out** (reroll an overcome), **Add a Detail** and **Gain Insight** (each mints a
  *floating boon*), **Suggest Compel** (name another player's character; approved
  → +1 boon to you, +2 to them), and the **Accept Compel** move (take a
  complication for 2 boons). Every one is queued as a proposal the facilitator
  accepts or rejects; abilities are only marked used on approval and reset when a
  session starts. A **floating boon** is a boon owned by nobody, created with a
  context note the facilitator attaches on approval; it sits in the Stones card
  until a player spends it on a roll (a facilitator-approved Highlight) and is
  discarded at session end. The sheet's pledge control is now labelled
  **Highlight**, and the overcome target's reroll button reads **Press Fate**.
  Suggest Compel treats the compelee's consent as table talk rather than a
  modelled handshake.
- The overcome: the facilitator frames a risky attempt and names one character
  as its target (`POST /api/table/:id/overcome/{start,cancel}`, new
  `GameState.overcome`). While an overcome is open, the target's player — not
  just the facilitator — may Roll and Reroll to resolve it, and a Reroll costs
  the target 2 boons. Accepting the roll resolves the overcome and logs whether
  it succeeded, was partial, or failed. Shown as an "Overcome — <name>" line in
  the Stones card.
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

- The client `update` is now a pure function returning `( Model, Effect )`
  instead of `( Model, Cmd Msg )`. A new `Effect` module names each side effect
  as data; `Effect.perform` turns it into a `Cmd` once, at the `Main` boundary.
  No behaviour change — the refactor exists so `update` can be tested without
  mocking `Cmd`.
- `ROADMAP.md` sections 19–20 rewritten around a settled overcome-aftermath
  design: aspects accumulate Banes only, the sheet's `condition` line is the
  whole harm model, the session pool keeps its Banes between sessions so goals
  escalate until a failure, and a failed session untethers one player (weighted
  random draw across every aspect Bane) into a forced aspect rewrite. Supersedes
  the old section 19 sketch, section 7's met/partial/failed thresholds, and
  section 4's deferred facilitator-set difficulty.
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
