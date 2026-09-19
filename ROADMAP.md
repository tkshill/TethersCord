# Roadmap

The backend (single Worker + Durable Object + D1) is stable. Everything here is
incremental work on top of it.

`DESIGN_PRINCIPLES.md` holds the ten core design principles every item is weighed
against.

**Phase 1** (sections 1–16, 19, 21, 22) is shipped — each section is the record
of what landed and the decisions taken along the way. **Phase 2** (sections
23–26) is the current plan: section 23 was a deliberate simplification for the
testing phase, moving stone and resource management onto the facilitator by hand
and rebuilding the view as three viewport-sized columns (section 24 then made it
two panels); section 26 gives the players their moves back and restores the
Overcome roll in a simpler form, and `RULES.md` states the resulting rules. **Phase 3**, at the end,
collects everything else still open, moved out of the Phase 1 sections so the
outstanding-but-not-next work sits in one list — it kept its original `P2.x`
item labels since they're referenced from `CLAUDE.md` and commit messages, so
those weren't renumbered when the phase was renamed. Sections whose entire
content was still open (17 Campaigns, 18 AI session summary, 20 Character
growth) moved wholesale into Phase 3, so those numbers are skipped below — the
section numbers are stable anchors, so nothing is renumbered.

# Phase 1 — shipped

## 1. Module structure — done

`client/src/Main.elm` had grown to a single ~900-line file holding flags, model,
messages, ports, every decoder, all HTTP commands, and the whole view. It is now
split into focused modules:

- [x] `Types.elm` — shared data types plus `Model` and `Msg`. `Model` / `Msg`
      live here rather than in `Main` (which the first draft of this plan
      assumed) because `View` needs them and `Main` imports `View`, so `View`
      cannot import `Main`. Depends only on `Roll` / `Http` / `Time` / `Json`.
- [x] `Api.elm` — every `Http.request` command and the JSON decoders they use.
      Commands take their result message constructor as an argument, so this
      module has no dependency on `Types.Msg`.
- [x] `Ports.elm` (`port module`) — the `toDiscord` / `fromDiscord` /
      `wsGameState` ports, `authorize`, and a typed `DiscordInbound` +
      `decodeInbound` in place of the old `decodeFromDiscord`. Ports declared
      here still surface on `app.ports`, so `main.ts` is unchanged.
- [x] `Format.elm` — `timestamp` (and a private `monthNumber`).
- [x] `Ui.elm` — the elm-ui visual system (see below).
- [x] `View.elm` — the view. Split in section 22 step 4 into a thin
      `View.elm` shell plus per-section `View/*` modules (`Session`, `Stones`,
      `Characters`, `Log`, `Moves`, `Entities`) over a shared `View/Helpers.elm`.
- [x] `Main.elm` — wiring only: `init`, `update`, `subscriptions`, `main`.

## 2. UI pass — `elm-ui` — done

The view was bare `elm/html` with class names but no stylesheet. It is rebuilt
with [`mdgriffith/elm-ui`](https://package.elm-lang.org/packages/mdgriffith/elm-ui/latest/)
`1.1.8` as a spare, paper-surfaced layout with a single slate accent.

- [x] `mdgriffith/elm-ui` added to `client/elm.json`; `Ui.elm` holds the
      palette, a `xs`/`sm`/`md`/`lg`/`xl` spacing scale, the type sizes, and the
      building blocks (`page`, `card`, `sectionTitle`, `primaryButton`,
      `ghostButton`, `stoneChip`, `banner`, `onEnter`, `onBlur`).
- [x] `view` is an `Element.layout` centred on a readable column: header, status
      banner, stones, characters, log, composer.
- [x] Message log: monospace timestamp column, facilitator lines tinted, wrapped
      paragraphs, its own `scrollbarY` region (`id "message-log"`) that `Main`
      pins to the bottom via `Browser.Dom.setViewportOf` on new messages.
- [x] Character sheets are bordered cards in a `wrappedRow` that collapses to a
      column when narrow; notes use a multiline input.
- [x] Stone pool and pending roll render as chips.
- [x] `model.status` renders as a quiet banner that tints red on failures.
- [x] Composer submits on Enter as well as the Send button.

### Follow-ups deferred from this pass

- [x] Load a real UI typeface (Inter). The latin subset ships as a single
      variable `.woff2` under `client/public/fonts/`, copied to the asset root
      by `client/scripts/build.mjs` and declared with `@font-face` in
      `client/index.html`. Self-hosted rather than pulled from Google Fonts so
      it loads under Discord's Activity CSP; `Ui.sans` keeps the system
      fallback, so a failed load degrades quietly.
- [x] The log only auto-scrolls to the bottom while the viewer is already
      there. `Model.logAtBottom` tracks it, fed by `Ui.onScrolledToBottom` on
      the log container (`LogScrolled`); posting a message snaps back down.

## 3. Stone model — favourable vs. negative outcomes — done

A stone now names its outcome: `Boon` is favourable, `Bane` is not. The rename
runs end to end — `Roll.Stone` and its `Api.elm` decoder, `StoneKind` and its
`"Boon" | "Bane"` wire strings, `INITIAL_STONE_POOL`, `describeStones`. The
`StoneState` in Durable Object storage under `KEY_STONES` is migrated as it
loads: `GameTable.loadStoneState` folds legacy `WhiteStone` / `BlackStone`
values (and a missing `committedBoons`) into the new shape, idempotently.
Historical log rows ("Rolled: White, Black") are left as plain text.

`Ui.stoneChip` is now a filled circle with the word captioned beneath it rather
than a colour-swatch pill.

## 4. Fate as a personal positive-stone pool — done

The game is loosely Fate-based, but runs on **boon stones a character holds and
spends** rather than one fate point. `CharacterSheet.fate` is kept as the
persisted integer (the D1 column is unchanged) but is now surfaced as "Boons"
and treated as that character's stock of favourable stones.

How a roll resolves, as built:

- The bag starts from `INITIAL_STONE_POOL` — two Boon, two Bane — every roll.
- `POST /stones/add-boon` (was `add-white`) adds a Boon to the shared table
  pool; it persists until a roll is accepted.
- A character pledges boons into the next roll with `POST /stones/commit`
  (`{ slot, delta }`), clamped to what they hold. Pledges are tracked in
  `GameState.committedBoons` (`{ slot, count }[]`, persisted in `StoneState`)
  and shown per sheet as "Pledged".
- `RollStones` / `RerollStones` draw two stones at random from
  `stonePool + (pledged Boons)`. More pledged boons means better odds; a reroll
  keeps the pledges.
- `AcceptRoll` spends each character's pledged boons from `fate` in D1, then
  resets the pool to the base four and clears all pledges.

Follow-ups:

- Facilitator-set difficulty (letting the facilitator add Bane stones to a roll
  from the fiction instead of the fixed two) was **superseded by section 19** —
  difficulty escalates on its own through the session pool carrying Banes
  between sessions, so no facilitator-set axis is planned; the fixed two Bane
  stay.
- [x] Bind a character sheet to a Discord user. `characters.discord_user_id`
      (migration `0006`, partial-unique per table); a player claims an unclaimed
      sheet with `POST /characters/:slot/claim` and drops it with `/release`
      (owner or facilitator). `/stones/commit` now takes only `{ delta }` and
      resolves the slot from the caller's claimed sheet — no slot picker.
      `/characters/:slot/update` is owner-or-facilitator (or anyone while the
      sheet is unclaimed); the client renders non-editable sheets read-only.
- [x] Where boons are earned: the sheet's boon `+` / `−` is now facilitator-only
      (section 5), so the facilitator grants boons. Player-initiated gains will
      come through the proposal flow (moves like Accept Compel).

## 5. Facilitator identity and the proposal model

Role is decided at auth time: `facilitator` if the Discord user id matches
`BOOTSTRAP_FACILITATOR_ID` **or** appears in the `facilitators` table, otherwise
`player` (`inferRole` in `oauth-discord.ts`, mirrored in
`GameTable.getAuthFromToken`).

The interface is **facilitator-driven**: the facilitator acts on shared game
state directly; a player who wants to change shared state makes a *proposal*
that the facilitator accepts or rejects, and only an accepted proposal updates
the broadcast `GameState`. Players still edit their own character sheets
directly — sheets are not shared state in that sense.

### Done

- [x] `BOOTSTRAP_FACILITATOR_ID` (a `wrangler.jsonc` var, overridable in
      `.dev.vars`) names the facilitator without a DB write. **Set it to your
      Discord user id — with it empty and no `facilitators` rows, everyone is a
      player and nobody can roll, grant boons, or clear the log.**
- [x] Facilitator-only routes, enforced in the Worker with a `facilitatorOnly`
      gate returning 403: `stones/roll`, `stones/reroll`, `stones/accept`,
      `characters/:slot/fate`, `messages/clear`, and `proposals/:id/{accept,reject}`.
- [x] Role-gated `View`: `isFacilitator model` hides the Roll / Reroll / Accept
      buttons, the boon `+` / `−`, and Clear log from players. The pool, the
      pending roll, and a player's own pledge control stay visible.

### The proposal flow — done

- [x] `GameState.proposals` — a `Proposal` list in the Durable Object's stone
      storage (`{ id, kind, proposerId, proposerName, slot, delta, createdAt }`),
      broadcast with the rest of the state.
- [x] Every player-side change to shared stone state is a proposal, one per
      click: `stones/add-boon` (player) and `stones/commit` (pledge, `delta` ±1)
      write a proposal instead of mutating. The facilitator's own `add-boon`
      still applies directly.
- [x] `proposals/:id/accept` applies the effect clamped to current state
      (`add-boon` → one Boon in the pool; `pledge` → adjust that slot's
      `committedBoons`), `/reject` just drops it; both leave the queue and
      broadcast. Accepting a roll clears any unresolved proposals.
- [x] Client: a facilitator-only **Proposals** panel in the stones card lists
      each as "*proposer* — *what*" with Accept / Reject; the proposer sees a
      muted "(n pending)" next to the control they used (no optimistic apply).

## 6. Message log hygiene

- [x] Facilitator-only `POST /api/table/:id/messages/clear` route
      (`handleClearMessages`): deletes the session's rows from D1, drops the
      Durable Object's in-memory `gameState.messages`, broadcasts. Surfaced as a
      "Clear log" button in the log card for the facilitator. This is the
      supported way to wipe a log; "Flushing test messages" below is the manual
      fallback.
- [x] Tell speakers apart by colour, not by a system/chat split. The play group
      is voice-first, so the log is almost all move and event lines rather than
      chat; a `kind` column was not worth it. `Ui.speakerColor` gives the
      facilitator and each player (in first-speak order) a stable name colour
      via `View.speakerColors`.
- [x] Day dividers: `Ui.divider` between messages whenever the calendar date
      changes (`View.logRows`); rows now show only `HH:MM` (`Format.clock`)
      since the divider carries the date.

## 7. Session / campaign structure

A **session** is one game day with a goal the players work toward, and it carries
its own stone pool that fills up from the rolls made during it.

- [x] **Session goal** in a `game_sessions` D1 row (`id`, `session_id`, `goal`,
      `started_at`, `ended_at`, `outcome`; migration `0007`). Shown to the whole
      table in a "Session" card for the session's duration.
- [x] **Start / end session** — facilitator-only `POST /session/start`
      (`{ goal }`) and `/session/end`. Start opens the goal and a fresh session
      pool; end runs the session roll. Each writes a system line to the log.
- [x] **Session stone pool** — separate from the per-roll bag, starts at two
      Boon + two Bane, held in the Durable Object's stone storage. **Section 19:**
      an accepted overcome roll now feeds it per the routing in that section (two
      of a kind whole; a mixed roll's Boon only), and the base four is joined by
      any Banes carried from the previous session.
- [x] **Session roll** — **superseded by section 19.** `/session/end` now draws
      **one** stone from the pool: a Boon means the goal is met, a Bane means it
      failed. The met / partial / failed tiers are retired; the pool's Banes
      carry between sessions and a failure flushes them, and a failed goal can
      untether a character.
- [x] Trim or paginate history — **done in section 15.** The DO now loads,
      holds, and broadcasts only the last `MESSAGE_WINDOW` (50) messages; older
      rows are fetched on demand through `GET /messages/history`.
- [x] Surface past `game_sessions` rows somewhere. The worker reads the last
      twenty completed sessions into `GameState.sessionHistory` (seeded on
      Durable Object start, refreshed on `/session/end`); the client shows them
      in the Session card as date / goal / outcome, newest first.

## 8. Connection polish

- [x] WebSocket state in the UI. `GameSocket.ts` reports `connected` /
      `reconnecting` / `offline` / `rejected` over a new `wsStatus` port;
      `Model.connection` drives a one-line note above the status banner (nothing
      shown while connected).
- [x] Retry the initial `getGameState` up to three times, two seconds apart
      (`Process.sleep` + `RetryGetGameState`), before parking on "Failed to load
      game state." The live socket remains the real source of state.

## 9. Character sheet layout and stone visualisation

The three sheets in a `wrappedRow` and the roll panel's text-and-number
summaries were getting dense. This pass is about seeing the current roll at a
glance.

- [x] **Tabbed character sheets.** Sheets show one at a time behind a tab strip
      (`Model.selectedSlot`, `Ui.tab`); claiming a sheet brings its tab forward.
      Tabs are labelled by character name, falling back to a slot number, with a
      "(you)" marker on the viewer's own sheet.
- [x] **Boons at the top of the sheet.** The boons block sits above the text
      fields now.
- [x] **Render a player's boons as circles** via `Ui.boonDot`, built from the
      same `Ui.stoneCircle` primitive as `Ui.stoneChip`.
- [x] **Mark the pledged ones.** Pledged boon circles carry an accent centre dot
      (`stoneCircle`'s `marked` flag); the separate "Pledged" count is gone.
- [x] **Pledged boons as shapes in the pool.** The roll panel appends one marked
      `Ui.pledgedStoneChip` per pledged boon to the bag; the caption is now just
      "Bag of N".

## 10. The overcome action and player moves — done

The rules layer over the roll mechanic. An **overcome** is the attempt to do
something risky; everything else here is how the other players feed into it.

### The overcome — done

- [x] Facilitator-only `POST /overcome/start` (`{ slot }`) names one character as
      the target; `/overcome/cancel` calls it off. Both `facilitatorOnly`.
- [x] `/stones/{roll,reroll}` move from `facilitatorOnly` to a `rollGate`: the
      facilitator always, plus the target's player while an overcome is open.
      `add-boon` was never gated, so any player still feeds the pool.
- [x] A Reroll while an overcome is open deducts `REROLL_COST` (2) boons from the
      target's `fate`, and is refused if they hold fewer. A plain (non-overcome)
      Reroll stays facilitator-only and free.
- [x] `gameState.overcome` (`{ targetSlot } | null`) lives in `KEY_STONES`
      storage next to `pendingRoll` and is broadcast in `GameState`. "Resolved"
      is modelled as cleared — accepting the roll (or `/overcome/cancel`) sets it
      back to `null` — with the verdict (succeeded / partial / failed) written to
      the log rather than kept as state.

### Special abilities — once per session each

Per character, reset when a session starts (section 7). Each is queued as a
proposal (section 5) and only marked used when the facilitator accepts;
`gameState.usedAbilities` holds the per-slot flags. All four need a running
session. Raised from the **Moves** card once a player holds a sheet.

- [x] **Help Out** — approved → the open overcome roll is rerolled for free
      (`drawFromBag`, no Press Fate cost). Available only while an overcome roll
      is on the table.
- [x] **Add a Detail** — approved with a context note the facilitator types →
      a `FloatingBoon` enters `gameState.floatingBoons`.
- [x] **Gain Insight** — same effect and note as Add a Detail; the "ask the
      facilitator a question" part is table talk.
- [x] **Suggest Compel** — `/abilities/use` with `{ kind, targetSlot }`, naming
      another player's character; approved → `SUGGEST_COMPEL_SUGGESTER_BOONS` (1)
      to the suggester and `SUGGEST_COMPEL_TARGET_BOONS` (2) to the compelled
      character. The compelee's consent is table talk, so it runs on the plain
      proposal / accept path — no separate handshake.

### Moves — no per-session limit

- [x] **Accept Compel** — `/moves/accept-compel`, queued as a proposal;
      approved → `ACCEPT_COMPEL_BOONS` (2) boons to the proposer.
- [x] **Highlight an Aspect** — section 4's pledge / `committedBoons` mechanic;
      the sheet control is now labelled "Highlight".
- [x] **Press Fate** — the overcome target's own Reroll, costing 2 boons
      (section "The overcome"); the target's reroll button now names it.

### What this needs in the model

- [x] Per-character, per-session ability-usage tracking. `gameState.usedAbilities`
      (`{ slot, kinds }[]`) in `KEY_STONES`, cleared on session start and end.
      Four flags: `help-out`, `add-detail`, `gain-insight`, `suggest-compel`.
- [x] Floating boons — `gameState.floatingBoons`, a `FloatingBoon` list distinct
      from `committedBoons`; each carries the facilitator's context note, is
      spent via a `use-floating` proposal, and is discarded at session end.
- [x] The section 5 proposal flow, extended with the `help-out`, `add-detail`,
      `gain-insight`, `suggest-compel`, `accept-compel`, and `use-floating` kinds.
- [x] The compel payouts run on the plain proposal / accept path: the compelee
      agreeing is handled at the table, so no suggest → accept → approve
      handshake was needed.

## 11. Effect pattern + a test suite across client and worker — done

The Effect refactor shipped and both suites run in CI.

This section started from no automated test anywhere in the project. `pnpm run
build` — an optimised Elm compile plus `tsc --noEmit` on both sides — was the
whole safety net, and it only catches type errors. Every gameplay rule (the
proposal queue, the overcome, the session lifecycle, once-per-session abilities,
fate costs) was checked by hand in a running Activity. This section built a suite
worth running before each new feature: pure Elm tests on the client, and
`workerd`-hosted tests on the Worker and Durable Object.

Sequenced after the gameplay sections above so the shape of `update` and of
`GameTable` has settled first. The client refactor and the first Elm tests are
one unit of work — the payoff of a pure `update` only lands once something
asserts on it.

### Client: the Effect pattern

`update` currently returns `( Model, Cmd Msg )` and reaches straight into `Api`,
`Ports`, and `Browser.Dom`. The [Effect pattern](https://elm-radio.com/episode/single-out-effects/)
swaps the `Cmd` for a custom `Effect Msg` that only *describes* a side effect,
leaving `update` a pure function that returns data a test can inspect.

- [x] `Effect.elm` — an `Effect` type with one constructor per side effect
      the app performs: `GetGameState`, `PostMessage`, `PostStones`,
      `PostCharacterUpdate`, `PostFate`, `PostCommitBoon`, `PostProposalDecision`,
      `PostAbility`, `PostSession`, `PostOvercome`, `Authorize`, `GetTimeZone`,
      `ScrollLogToBottom`, `None`, `Batch (List Effect)`. `Api` and `Ports`
      keep the "how"; `Effect` names the "what".
- [x] `Effect.perform : Flags -> Effect -> Cmd Msg` at the `Main` boundary,
      called once from `init` and once from the `update` wrapper.
      `update : Msg -> Model -> ( Model, Effect )` is now pure.
- [x] No behaviour change — `build:client` was the check. The diff was mechanical:
      each `Api.postX ... Ctor` became an `Effect` value.

### Client: Elm tests

- [x] `elm-explorations/test` `2.2.1` added to `client/elm.json`
      `test-dependencies`. `avh4/elm-program-test` (for flows that span several
      messages) is still deferred — the `update` tests fold `Main.update`
      directly for now.
- [x] Unit tests, no program harness (`client/tests/`, 42 tests):
  - `Api` decoders round-trip against captured `GameState` / message /
    character JSON, including the awkward cases: an open overcome, a pending
    roll, floating boons, a proposal of each `kind`.
  - `Main.applyServerState` keeps the sheet under the cursor when a server
    snapshot lands mid-edit, and takes the server copy otherwise.
  - the empty-message send guard in `update` (`SendMessage` with a blank
    `newMessage` yields `Effect.None`).
  - `Format.timestamp` and the `Roll` stone helpers.
- [x] `client/tests/`, run with the `elm-test` CLI invoked through the pinned
      `node_modules/elm/bin/elm` binary (`pnpm run test:client`), the way
      `build.mjs` does.

### Worker and Durable Object: Vitest in `workerd`

`@cloudflare/vitest-pool-workers` runs Vitest specs *inside* `workerd` with real
`env` bindings — a live `GameTable` Durable Object and a real D1 instance with
`worker/migrations/` applied — so tests exercise the actual storage and
hibernation paths, not a mock. It runs entirely locally, touches no Cloudflare
account, and costs nothing against the Free tier.

- [x] `worker/vitest.config.mts` using `defineWorkersConfig` (an `.mts` file —
      the pool package is ESM-only), pointed at `wrangler.jsonc` for bindings;
      `worker/test/apply-migrations.ts` applies `worker/migrations/` before each
      file so it starts from a migrated, empty database. `compatibilityDate` is
      pinned to `2026-08-22` because the pool bundles an older `workerd`.

### What the worker tests cover

- [x] **`GameTable` state machine**, driven through `SELF.fetch` against the DO:
  - proposal lifecycle — a player's `add-boon` appends a `Proposal` without
    touching the pool; `/proposals/:id/accept` applies it; `/reject` drops it
    with no effect; a facilitator's own `add-boon` applies directly. An
    accepted Suggest Compel pays `SUGGEST_COMPEL_SUGGESTER_BOONS` /
    `SUGGEST_COMPEL_TARGET_BOONS`.
  - session lifecycle — `/session/start` opens the goal; `/session/end` writes
    a `sessionHistory` row and clears `floatingBoons` + `usedAbilities`. An
    ability with no running session is refused (400).
  - once-per-session abilities — a second `gain-insight` from the same slot
    after an accepted one is refused (409).
- [x] **Auth gates** — every route rejects a missing / unknown / expired bearer
      token; `facilitatorOnly` routes 403 for a player and allow a
      `facilitators`-table facilitator; `rollGate` allows the facilitator always
      and the overcome target conditionally, rejecting another player.
- [x] **`withLock` serialisation** — three `add-boon` accepts fired concurrently
      at one DO leave the pool at +3; a lost update would leave fewer.
- [x] **The `index.ts` proxy** — `tableId` from the path overwrites any
      `?tableId=` in the query; `TABLE_ID_PATTERN` rejects an out-of-range id
      with 400; the path is rewritten before it reaches the stub.
- [x] **`oauth-discord.ts`** — `pruneExpiredSessions` deletes only rows past
      `expires_at`; `handleDiscordExchange` 400s a non-JSON body and a body with
      no code. `inferRole` is exercised indirectly through the `facilitators`
      table in the auth-gate tests; the `BOOTSTRAP_FACILITATOR_ID` path is not
      directly asserted.

### Shared fixtures

- [x] `worker/test/helpers.ts` (`seedAuth` — a `sessions_auth` / `facilitators`
      row; `call` / `claim` / `readState` — drive routes through `SELF.fetch`)
      and `client/tests/Fixtures.elm` (a full wire-snapshot `GameState`) cover
      this. A separate typed value-builder off `worker/src/types.ts` was not
      needed once the tests drive the real routes rather than construct state.

### Scripts and CI

- [x] `pnpm run test:client` (elm-test) and `pnpm run test:worker` (vitest),
      plus `pnpm run test` running both.
- [x] Fold `test` into `pnpm run build` after `typecheck`, so the pre-deploy
      gate runs the suite.
- [x] `.github/workflows/ci.yml` — `pnpm install --frozen-lockfile` then
      `pnpm run build` (client bundle + typecheck + tests) on push to `main` and
      on every PR. The first CI the project has.

## 12. Correctness, session lifecycle, and UX cleanup — done

Promoted ahead of the efficiency work. The findings from the September structure
audit, plus a firmer set of rules for the session lifecycle.

### Session lifecycle

- [x] **Starting and ending a session are facilitator-only.** Enforced —
      `facilitatorOnly` guards `/session/start` and `/session/end`, and the
      buttons render only for the facilitator in `View`. Recorded here as an
      invariant to preserve as the surrounding code changes; pinned by an
      `auth.test.ts` case.
- [x] **Ending a session clears every unresolved pending state.**
      `handleEndSession` and `handleStartSession` now null `overcome` /
      `pendingRoll`, empty `committedBoons` / `proposals`, and (as before) drop
      `floatingBoons` / `usedAbilities`. An overcome roll or a move proposal
      left open when the session ends is discarded; nothing from a closed
      session carries into the next one. Pinned by a `gameTable.test.ts` case
      that seeds all six and asserts the clear.
- [x] **The facilitator can edit the session goal at any time.**
      `POST /session/goal` (`{ goal }`, `facilitatorOnly`) updates the running
      `game_sessions` row and `gameState.session.goal`, logs `Goal updated`, and
      broadcasts. The Session card shows an editable goal field for the
      facilitator behind the confirm step below.
- [x] **Confirm destructive facilitator actions.** End session, Clear log, and
      edit-goal go behind a one-click arm/disarm step (`Ui.confirmButton`,
      `Model.confirming`): the button becomes a danger-tinted confirm beside a
      Cancel, and only the second click performs the action.

### Audit fixes

- [x] **Clean up a slot's pledges and proposals on claim / release.**
      `handleClaimSlot` / `handleReleaseSlot` run a shared
      `clearSlotPendingState` over every slot whose owner changed, dropping that
      slot's `committedBoons` entry and any proposal whose `slot` / `targetSlot`
      is it, then persist — so a sheet changing hands can no longer leave an
      accepted roll spending the wrong character's boons.
- [x] **Let a proposer withdraw their own proposal.** `POST
      /proposals/:id/withdraw`, gated on `proposerId` (not `facilitatorOnly`),
      with a "withdraw" link beside every "(pending)" hint that pulls the
      proposer's most recent proposal of that kind.
- [x] **Guard `/stones/accept` on a `pendingRoll`.** `handleAcceptRoll` returns
      400 when there is no roll, rather than silently resetting the pool and
      clearing the proposal queue.
- [x] **Surface silently-dropped accepts.** The `pledge` / `suggest-compel` /
      `accept-compel` / `use-floating` accept arms return 409
      (`proposalTargetGone`) and leave the proposal queued when their character
      or floating boon has gone, rather than removing it with no effect and no
      log line.
- [x] **Per-row context note.** `Model.proposalDraft : String` became
      `proposalDrafts : Dict String String` keyed by proposal id; each Add a
      Detail / Gain Insight row has its own field, and `ProposalResolved` now
      carries the id so only that row's draft is cleared.
- [x] **Status banner.** `Model.status` is now steady state only (auth,
      "Connected."); per-action failures go to `Model.error : Maybe String`,
      shown as a separate red line and auto-dismissed after ~6 s via a
      `DismissErrorIn` effect. Terminal auth / load failures stay on `status`.

## 13. Table entities beyond characters — NPCs and locations

The facilitator needs to record the cast and the map alongside the three player
sheets. Both are facilitator-owned reference data: broadcast to the whole table,
read-only for players.

- [x] **`npcs` and `locations` D1 tables** (append-only migration `0008`),
      scoped by `session_id` like `characters`: `id`, `session_id`, `name`,
      `notes`, `created_at`, `updated_at`. First cut is name + notes; an NPC
      `location_id`, a status field, and location nesting can come later.
- [x] **Facilitator-only routes** — `POST /npcs` (create), `POST
      /npcs/:id/update`, `POST /npcs/:id/delete`, and the same three for
      locations, all through `facilitatorOnly`.
- [x] **`GameState.npcs` / `GameState.locations`**, loaded on Durable Object
      cold start and broadcast with the rest of the state (their own patch kinds
      once section 15's delta broadcasts land).
- [x] **Client** — an "NPCs" card and a "Locations" card: an editable list for
      the facilitator, a plain read-only list for players, reusing the
      character-sheet field styling. The card is hidden from players while its
      list is empty.

## 14. Fewer requests per action — the Cloudflare Free budget

The Free plan is 100,000 requests/day and 10 ms CPU per request, shared across
the Worker and its Durable Object. Every table mutation currently costs at least
two counted requests — the Worker entry point and the `stub.fetch` subrequest
into the `GameTable` object — and a cold launch costs more again (the OAuth
exchange, `getGameState`, the socket upgrade, and up to three `getGameState`
retries). WebSocket broadcasts are outbound and do **not** count, so the lever
is the number of inbound HTTP calls, not the fan-out. Ordered by value over
effort.

- [x] **Drop the HTTP state seed on the happy path.** `GotBackendAuth` now
      schedules the `getGameState` seed as a fallback ~3 s out
      (`RetryGetGameStateIn`) instead of firing it immediately; `RetryGetGameState`
      only issues the request while `model.gameState` is still `Nothing`. The
      socket snapshot beats the timer in nearly every launch, so the read is
      skipped. Bounded retry cap kept. Saves one to four requests per launch.
- [x] **One character save per sheet, not per field.** `CharacterFieldInput`
      marks the slot dirty and arms a debounce (`FieldSaveDue`, token-guarded);
      `flushFieldSaves` sends one `/characters/:slot/update` per dirty sheet ~1 s
      after the last edit and on tab-away (`SelectSlot`). NPC / location rows
      (`dirtyEntities`) debounce the same way. `applyServerState` keeps the local
      copy of any dirty slot / id, not just the one under the cursor.
- [x] **De-duplicate in-flight mutations.** `Model.inflight : Set String` holds
      the action keys awaiting an ack; `guard` makes a second click a no-op and
      `View.press` renders the button disabled, cleared by prefix when the shared
      `…Updated` result lands. Closes the double-roll / double-proposal holes.
      (Visible pending state is wired for the roll panel and the proposal queue;
      the moves card relies on the `update`-layer guard for now.)
- [x] **Cache the auth lookup in the Durable Object.** `GameTable.resolveAuthToken`
      memoises token → `AuthInfo` in DO memory for `AUTH_CACHE_TTL_MS` (60 s);
      only positive results are cached, so a freshly minted or newly promoted
      token is picked up within the minute. One D1 read per token per minute.
- [x] **Coalesce Highlight churn.** `CommitBoonIncrement` / `Decrement` only
      nudge `pendingPledgeDelta` and arm a debounce (`PledgeDue`); one
      `/stones/commit` carrying the net delta is sent once the taps stop, and the
      control disables while `stones:pledge` is in flight. `/stones/commit` now
      takes any non-zero integer `delta`; `applyPledge` clamps to `[0, fate]`.

## 15. Zippier realtime updates

Perceived latency on a shared action is click → POST → 204 → DO broadcast →
socket → decode → re-render. The two network hops are inherent to the
facilitator-broadcast model; the payload size and the render cost are not.

- [x] **`Element.Lazy` the message log.** `View.lazyLogBody` (the `speakerColors`
      fold plus the day-divided `logRows`) is wrapped in `Element.Lazy.lazy2` on
      `zone` / `messages`, so a re-render that does not touch `messages`
      (composer typing, confirm arming, tab switch) skips refolding the list. A
      socket broadcast decodes a fresh list, so it does not help there.
- [x] **Instant local affordances.** Delivered by section 14's in-flight
      de-duplication: `View.press` renders a raising control disabled while its
      action key is in `model.inflight`, so it flips on click. Wired for the roll
      panel and the proposal queue; the moves card relies on the `update`-layer
      guard for now.
- [x] **Hold and send fewer messages.** `MESSAGE_WINDOW` (50) caps what the
      Durable Object loads, holds (`capMessages`), and broadcasts;
      `GET /messages/history?before=<createdAt>` (read-only, no lock, no
      broadcast) returns the previous page, prepended client-side behind a
      "Load earlier messages" affordance (`LoadEarlierMessages` /
      `GotEarlierMessages`). Supersedes the deferred pagination note in
      section 7.

## 16. Storage and write economy

Storage is nowhere near a limit today (~25 kB against a 5 GB account-wide SQLite
cap on Free), so this is low priority — revisit only if the Durable Object
metrics move.

- [x] **Write `KEY_STONES` only when stone state actually changed.**
      `saveStoneState` serialises the stone slice and compares it to
      `lastSavedStones` (seeded from the cold-start load); a byte-identical slice
      skips the `storage.put`. A chat post and other stone-inert mutations no
      longer rewrite the blob.
- [x] **Prune `messages` on the existing hourly cron.** `pruneOldMessages`
      (`worker/src/maintenance.ts`) runs `DELETE FROM messages WHERE created_at
      < ?` for a 30-day retention window, alongside `pruneExpiredSessions` in
      `scheduled`.

## 19. The overcome aftermath — aspects, conditions, and the tether

**Superseded, in part.** The session verdict, the carried-Bane count, and
untethering described below did not survive playtest and have been removed:
session goals are now plain text with no roll or verdict, the per-session pool
and the roll bag are merged into one pool that is never wholesale-reset (only
topped up to a 2 Boon / 2 Bane floor at session end), and there is currently no
mechanic that clears an aspect's accumulated Banes. Aspect-Bane tracking and
the overcome routing (two of a kind returns whole, a mixed roll's Bane onto a
random aspect) are unchanged and still described accurately below — only the
"session pool carries" and "Untethering" subsections are stale. See `CLAUDE.md`
for the current mechanic.

**Built** (feat/section-19-overcome-aftermath), minus the open playtest
questions. This is the rules layer that turns individual overcome outcomes into a
character's long arc, keeping what makes Burning Wheel, Pendragon and Archive of
the Sky work inside a rules-lite core.

Shipped: aspect-Bane tracking (`archetype_banes` / `desire_banes` /
`quest_banes`, migration `0009`; shown as dots on the sheet), the overcome
routing below, the carried session pool (`session.carriedBanes`), the
single-stone session verdict, untethering (`gameState.untether`), the
facilitator-only `POST /untether/resolve`, and the frenzy's Bane-to-pool
routing. Deferred to playtest: Highlight aspect-locking during a frenzy
(Highlights stay aspect-agnostic), the facilitator calling a foregone failure
early, any per-session compel cap, and cadence tuning.

### Overcome resolution

Every overcome draws two stones from the bag — base two Boon + two Bane, skewed
by any Highlights or rerolls (section 4).

- **Two Boons** → both go to the session pool.
- **Two Banes** → both go to the session pool.
- **Mixed** → the Boon goes to the session pool; the Bane is placed **at random**
  on one of the acting character's three aspects (Archetype / Desire / Quest).

The mixed roll is two-thirds of all draws, so the pool gains a Boon far more
often than a Bane while the cost lands on the character — sessions trend toward
success by design.

### The session pool carries (revises section 7)

- The pool's **Boons flush at the end of each session; its Banes carry over.**
- Session-goal success is **one stone drawn from the pool at session end** — a
  Boon means the goal is met, a Bane means it failed. No threshold, no
  comparison, and the met / partial / failed tiers are retired. (The earlier
  "Boons-vs-Banes comparison" wording was dropped for the draw during the
  build.)
- Because Banes carry and Boons do not, the odds of that draw coming up Bane
  climb each session, so **goals escalate in difficulty until a failure.** A
  failure flushes the pool completely back to the base four.
- The table can spend personal Boons on Highlights to push Boons into the pool
  and buy another session, or hoard them and let the reckoning come — the player
  economy paces the escalation, with no magic number anywhere in it.

### Aspects and the condition line

- Aspects are **always true**; a Highlight only makes that truth mechanically
  relevant for one roll (section 4's pledge).
- Aspects only ever accumulate **Banes**. The character sheet's existing
  `condition` field (migration `0003`, `ConditionField` in `Types.elm`) becomes
  one evolving sentence naming what the accumulated strain is doing to the
  character — rewritten after a Bane lands, always emotional or identity-level,
  never a number. Update it lazily, when the situation actually shifts, not once
  per Bane.
- This is the whole harm model. There is no separate consequence mechanic and
  **no death mechanic** — a character is hurt through failure, self-doubt,
  self-destruction, loss of identity, and the guilt of hurting others. Physical
  injury enters only as a beat that feeds one of those.

### Compels

- **Strictly positive and facilitator-gated.** The facilitator offers a
  fictional complication; the player who accepts takes `ACCEPT_COMPEL_BOONS` (2)
  Boons and no mechanical penalty. No hard per-session cap for now — a compel is
  meant to be substantial enough, and to open enough scene, to self-limit.
- This replaces the earlier "a compel adds a Bane" and "a compel may remove a
  Bane" ideas.

### Untethering

- Triggers **only when a session goal fails.**
- One Bane is drawn at random from the pool of **every Bane on every aspect of
  every player.** Its owner becomes **untethered** on that aspect. More Banes →
  likelier to be drawn; which player and which aspect are unknown until it
  happens.
- **One untethered character at a time**, and **nobody untethers on two
  consecutive failures.** A failure that lands while an untether is still
  unresolved produces no new untether.
- On that failure the session pool flushes and **all of the untethered player's
  aspect Banes clear.** Every other player keeps their aspect Banes and stays in
  the running for their own reckoning.
- **Resolution** is a facilitator-framed scene, concluded by the end of the
  following session, built so the fiction skews toward **transcendence or
  dissolution** (the Archive of the Sky move). Afterward the player **must
  rewrite or replace** the untethered aspect. Aspects are written at character
  creation to carry latent conflict with the world, so the scene always has
  something to pull on.

### The frenzy

While untethered, the character is in full focus the session after the trigger
and resolves by that session's end.

- The **broken aspect cannot be used to justify a Highlight**; the other two
  still can. The character keeps earning Boons (compels, once-per-session moves)
  and keeps rolling — they simply cannot lean on the broken part of themselves.
- An untethered character's own **mixed-roll Bane goes to the session pool**
  instead of onto an aspect; they accrue no new aspect strain mid-frenzy.

### What this supersedes

- Section 4's deferred "facilitator-set difficulty from the fiction" — difficulty
  now escalates on its own through the carried pool, so the facilitator needs no
  floating-bane axis.
- Section 7's placeholder met / partial / failed session thresholds.
- The earlier section 19 sketch (leftover stone to the target, Boons tagged to
  aspects, facilitator-held floating banes, compels removing banes).

## 21. Game text, tooltips, glossary, and aspect examples — done — *see also section 22*

**Built.** The player-facing copy was scattered through `client/src/View/*` as
string literals, and the game leans on terms (overcome, boon, bane, aspect,
compel, highlight, floating boon, untether) that a player new to TTRPGs has no
prior hook for. The near-term need was to run this game with **people unfamiliar
with TTRPGs**, so this section pulled the copy into one place, taught the terms
where players meet them, and gave a reference for writing aspects at character
creation.

Shipped across five branches off `main`: `Copy.elm` (21.1), `Copy/Terms.elm`
(21.2), `Ui.withTip` and the `View.Helpers` tooltip helpers (21.3), `View.Guide`
(21.4), and `ASPECTS.md` plus `Copy.aspectExamples` with an in-app expander
(21.5). No wire-format, D1, or `KEY_STONES` change anywhere in it.

Done after section 22 step 4 (the `View/` split) — step 4's record-props layout
is what the tooltip and glossary work built on.

### 21.1 — One editable copy source — `Copy.elm` — done

- [x] **`client/src/Copy.elm`** — named `String` constants for every
      player-facing string that was inline in `View.elm` and `View/*`: card
      titles, section hints ("Once per session", "Any time", "Start overcome",
      "Session pool", "Floating boons", "Bag of N"), empty states ("No session
      running.", "No messages yet.", "No character sheets."), placeholders
      ("Write a message…", "Session goal…", "Context this boon represents…"), the
      `describeProposal` phrases, the connection notes, the untether-banner
      sentence, and the game-action button labels (Roll, Reroll, Press Fate,
      Accept, Add boon, Help Out, Add a Detail, Gain Insight, Accept Compel, End
      session, Resolve untether, …). Grouped by card with comment headers; a few
      spliced-value strings (bag count, carried-Bane note, "Overcome — <name>",
      the Suggest Compel description) are small functions rather than constants.
- [x] Chosen over a `copy.json` compiled into the bundle: type-checked, no
      decoder, no runtime fetch, a missing key fails the build.
- [x] Each `View/*` module imports `Copy` and reads from it; no behaviour
      change, the client bundle and both test suites are the gate. Structural
      field labels that are not game vocabulary ("Name", "Notes") stay inline.

### 21.2 — Glossary content — `Copy.Terms` — done

- [x] **`Term = { term : String, short : String, long : String }`** with
      `terms` / `groupedTerms` / `termShort` in `client/src/Copy/Terms.elm` (its
      own module — pure data, and large). `short` is a one-line gloss for the
      tooltip; `long` is two to three sentences for the glossary card. One
      definition, two surfaces.
- [x] Covered, grouped in order of play: **Roles** — Table, Facilitator, Player;
      **The session** — Session, Goal, Session pool, Carry; **Stones & rolling**
      — Stone, Boon, Bane, The bag, Roll, Overcome, Highlight, Pledge, Proposal;
      **Aspects & growth** — Aspect, Archetype, Desire, Quest, Condition,
      Untether, Frenzy; **Moves & compels** — Compel, Accept Compel, Suggest
      Compel, Floating boon, Help Out, Add a Detail, Gain Insight.
- [x] `CopyTermsTest` pins that every term is filled in, names are unique, and
      the flat list matches the grouped one. The wording is meant to be revised
      freely.

### 21.3 — In-place tooltips — done

- [x] **`Ui.withTip : String -> Element msg -> Element msg`** — adds
      `Element.htmlAttribute (Html.Attributes.title …)`. No `Model` state; an
      empty gloss adds nothing.
- [x] **`View.Helpers.glossaryTitle` / `tip` / `tipAttrs`** — pair a label with
      its `Copy.Terms.termShort`. `glossaryTitle` for the Session / Stones /
      Characters card titles; `tip` wraps inline labels and buttons; `tipAttrs`
      drops the `title` attribute straight onto a full-width input so its layout
      is untouched. (No `sectionTitleTip` taking a `Term` — that would pull the
      glossary into `Ui`, which stays a leaf.)
- [x] Applied to the aspect fields, Condition, "Highlight", "Overcome — <name>",
      "Session pool", "Floating boons", and the once-per-session / compel move
      buttons.
- [x] Known limit: `title=` is hover-only — no touch, and it does not render in
      the Discord Activity webview at all. The glossary card below is the tap
      path; both shipped. A real tooltip element is parked as **P2.11**.

### 21.4 — "How to play" glossary card — done

- [x] **`client/src/View/Guide.elm`** — a section card, collapsed by default,
      rendering `Copy.Terms.groupedTerms` as `term — long` under each heading.
      Same `Ui.card` shell as the other sections; the header row is a ▸ / ▾
      toggle.
- [x] `Model.guideExpanded : Bool` (default `False` in `Main.init`) and a
      `ToggleGuide` message; `update` stays pure — it yields `Effect.None`.
      `UpdateTest` pins the toggle.
- [x] Slotted last in `View.view`'s section list, after the Log.

### 21.5 — Aspect examples — done

- [x] **`ASPECTS.md`** at the repo root (beside `DESIGN_PRINCIPLES.md`) — what
      makes a strong aspect (true now, at odds with the world as it is,
      something the table can pull on — per section 19), generous lists under
      **Archetype**, **Desire**, **Quest**, worked characters showing all three
      together, and a note on rewriting an aspect after an untether.
- [x] **`Copy.aspectExamples : Aspect -> List String`** — a curated six per
      aspect, a subset of `ASPECTS.md`.
- [x] **`View/Characters.elm` `aspectField`** — a "see examples" / "hide
      examples" toggle beneath each aspect input, expanding an indented bulleted
      list from `aspectExamples`. Shown only when the field is `editable`, so it
      is there for creation, revision, and the section 19 forced rewrite.
- [x] `Model.aspectExamplesOpen : Maybe ( Int, Aspect )` (one open at a time)
      and a `ToggleAspectExamples Int Aspect` message; pure `update` arm, pinned
      by `UpdateTest`.

### Sequencing

Each sub-step is its own branch off `main` with a professional commit message,
merged before the next starts. 21.1 first (the constants the rest read); 21.2
before 21.3 / 21.4 (the `Term` list); 21.3, 21.4, 21.5 are independent after
that. No wire-format, D1, or `KEY_STONES` change anywhere in this section;
`pnpm run build:client` is the gate for the mechanical parts, `pnpm run build`
before merge.

## 22. Maintainability pass — the view and the Durable Object

**Largely done.** Steps 1–5 and 7 shipped in full; step 6 shipped its low-risk
part (a `get game()` accessor, a `commit()` trailer helper, `Promise.all` on the
cold-start reads). The `GameTable.ts` module split — a route table and
`worker/src/handlers/*` — is carved out as its own effort (see Phase 2). No
gameplay change anywhere in this section; each step was its own branch merged
with `--no-ff`, guarded by the client bundle, both typecheckers, and both test
suites.

Nineteen sections of features have landed on a structure that was drawn for far
less. Complexity is now concentrated in two files that grow every time a rule is
added:

| File | Lines | Shape |
| --- | --- | --- |
| `worker/src/GameTable.ts` | ~2500 | one DO class, ~40 methods, a 230-line `fetch` if-ladder |
| `client/src/View.elm` | ~1550 | one module, ~40 functions, long positional argument lists |
| `client/src/Main.elm` | ~830 | `update` — one `case` with ~64 branches, ~70 of them boilerplate |
| `client/src/Api.elm` | ~670 | 24 near-identical `Http.request` builders |

Section 1 deferred the `View.elm` split "only if it grows further after future
UI work" — it has. This section acts on that, and on the equivalent split for
the Worker.

### Guiding rules

- **No behaviour change.** `pnpm run build` (optimised client bundle +
  `typecheck` both sides + both test suites) is the whole gate, plus new unit
  tests on each function that becomes pure. Prefer many small mechanical diffs
  over one rewrite.
- Sequenced sub-steps below, each its own branch off `main` with a professional
  commit message, merged before the next starts. The steps are independent
  except where noted, so the order can flex.
- The only wire-format change anywhere here is one *additive* field
  (`outcomeKind`, step 3); no D1 migration, no `KEY_STONES` shape change.

### Step 1 — client quick wins (low risk, independently shippable) — done

- [x] **`Api.elm` request helpers.** Collapse the 24 `Http.request` builders
      behind three privates — `postJson` / `postEmpty` / `get` — that own
      `method`, `authHeaders`, `jsonContentType`, `timeout`, `tracker`, and the
      `expectWhatever` / `expectJson`. `slotAction` already hints at this.
      Each endpoint becomes one line; the module roughly halves.
- [x] **Collapse the mutation-result branches in `update`.** The ~11
      `…Updated (Ok ()) -> ( clearInflight "x:" model, None )` /
      `(Err _) -> fail "…" (clearInflight "x:" model)` pairs become one
      `MutationDone { family : String, failMsg : String } (Result Http.Error ())`
      message (or a shared helper). Removes ~11 `Msg` constructors and their
      `Effect` → `Api` wiring, ~60 lines net.
- [x] **Unwrap `Maybe GameState` once** in `View.view`: a single top-level
      loading branch, and every section function takes `GameState`, not
      `Maybe GameState`. Removes the ~6 repeated `case maybeGs of Nothing …`
      blocks.
- [x] **`Format.pluralize : Int -> String -> String`** for the
      `"Bane" ++ (if n == 1 then "" else "s")` pattern (three sites in `View`,
      more in the Worker).
- [x] **`Types.characterAtSlot`** — one shared slot lookup, replacing
      `Main.findCharacterAtSlot` and `View.characterAtSlot`.

### Step 2 — typed proposal and ability kinds — done

- [x] **`ProposalKind` / `AbilityKind` custom types** with decoders, replacing
      `Proposal.kind : String` and the string-literal kind references across
      `View` and `Main` (`countProposals myId "add-boon"`,
      `abilityUsed slot "suggest-compel"`, the `describeProposal` string `case`).
      They live in a new `Kind.elm` rather than `Types.elm` because
      `SuggestCompel` / `AddBoon` already exist as `Msg` variants and Elm
      constructors must be unique per module; `ProposalKind` composes
      `AbilityKind` through an `AbilityProposal` constructor. `describeProposal`
      is now a total `case`. `Msg.UseAbility` and `Effect.PostUseAbility` carry
      an `AbilityKind`, encoded back to a string at the `Api` boundary.

### Step 3 — a structured session outcome — done

- [x] `View.verdictWord` / `verdictColor` parsed a prose outcome string
      (`String.contains "failed"`) that `handleEndSession` assembles in English.
      An additive `outcomeKind : "met" | "failed" | "partial"` field now rides on
      the broadcast `SessionSummary`, derived from the `outcome` text in
      `loadSessionHistory` (no `outcome_kind` column, no migration). The client
      decodes it to a `SessionOutcome` custom type the view switches on; the
      prose stays as `outcome`.

### Step 4 — split `View.elm` — done

- [x] **Per-section modules** under `client/src/View/`: `Session` (with the
      untether banner), `Stones`, `Characters`, `Log`, `Moves`, `Entities`. Each
      exposes `view : ViewContext -> <props record> -> GameState -> Element Msg`
      (`Moves` takes no extra props; `Entities` takes an `EntityKind`).
- [x] **Record props, not positional args.** A shared `ViewContext`
      (`{ facilitator, myId, zone }`) is computed once in `View.view` and
      threaded; each section adds its own small record for the model slices it
      needs. The old `sessionPanel : Bool -> Maybe String -> String -> …` chains
      are gone.
- [x] **`View.elm` keeps** `view` (the shell + the ordered section list), plus
      `header`, `connectionNote`, `composer`, `isFacilitator`, and `logDomId`
      (re-exported from `View.Log`, which owns it so `Effect` still imports
      `View`).
- [x] **Generic helpers moved.** `press` and `onlyWhen` are now in `Ui.elm`
      (`press` generalised over `msg`); the cross-section view helpers
      (`placeholder`, `inputAttrs`, `characterLabel`, `countProposals` /
      `latestProposalId`, `pendingHint` / `withdrawLink`, `stoneChip`) plus the
      `ViewContext` type live in `View/Helpers.elm`.
- [x] Section 1 note below and the `CLAUDE.md` module-layout list updated.

### Step 5 — worker pure-logic extraction (no behaviour change) — done

- [x] **`worker/src/gameLogic.ts`** — the pure helpers moved out of
      `GameTable.ts`: `applyPledge`, `routeOvercomeDraw`, `markAbilityUsed`,
      `clearSlotPendingState`, `aspectBaneBag`, `pickTwoRandom`, `randomInt`,
      `totalCommittedBoons`, `characterLabel`, `describeStones`, plus the
      `ASPECT_NAMES` constant. New `worker/test/gameLogic.test.ts` exercises
      them directly (10 cases); the two existing `routeOvercomeDraw` /
      `aspectBaneBag` tests re-point their import.
- [x] **`worker/src/characters.ts`** — the raw `characters` SQL: `setFate`,
      `setOwner`, `incrementAspectBane`, `clearAspectBanes`, `updateFields`,
      `rowToCharacterSheet` (+ the `CharacterRow` type and the private
      `ASPECT_BANE_COLUMNS` map). The four `UPDATE characters SET fate = ?`
      sites (`bumpFate`, the reroll cost, the pledge-spend loop,
      `handleUpdateFate`), the owner writes, the aspect-Bane increment, the
      untether clear, and the sheet-fields update all route through it.
- [x] **`migrateStoneState.ts`** — `StoneState` / `LegacyStoneKind` /
      `LegacyStoneState` / `migrateStoneKind` and the `?? default` fan-out are
      now a pure `migrateStoneState(stored, initialPool)`; `loadStoneState` is
      the storage read plus the cold-table `put`.

### Step 6 — split `GameTable.ts`

Part 1 — the low-risk items that need no module reshaping — done:

- [x] **`private get game(): GameState`** — the ~85 `this.gameState!` reads are
      now `this.game`; the one non-null assertion lives in the getter.
- [x] **`commit()` helper** — `commit(next, logLine?)` folds the
      `gameState = …; saveStoneState; appendMessage?; broadcast; ackResponse()`
      trailer. Every mutating handler now ends in one `return this.commit(…)`,
      so its diff is just the `next` it builds.
- [x] **`Promise.all` the independent cold-start reads** in `loadInitialState`
      (the messages query, `loadOrCreateCharacters`, `loadStoneState`,
      `loadSessionHistory`, the two `loadEntities`).
- [x] **`const UUID = "[0-9a-fA-F-]{36}"`** shared by the two id route regexes.

Part 2 — the module reshaping (route table + `worker/src/handlers/*`) — is in
Phase 2 (P2.2).

### Step 7 — smaller TS cleanup — done

- [x] The three hand-maintained Elm-port shapes (`ElmPorts` in
      `DiscordBridge.ts`, `GameSocketPorts` in `GameSocket.ts`, the inline shape
      in `main.ts`) are one `client/src/ports.ts` — `ElmPorts` plus a
      `SocketPorts = Pick<…>` for `GameSocket`.
- [x] `ports.ts` also carries a `declare global { interface Window }` for
      `DISCORD_CLIENT_ID` / `BACKEND_BASE_URL`, so the three `(window as any)`
      reads are now typed `window.` accesses.

### Relates to

- **Section 21** (game text / tooltips / glossary / aspect examples) — the
  copy-extraction step wants the new `View/` module layout to exist first, so do
  21 after step 4. Step 4 is done, so section 21 is unblocked.
- **Phase 2 P2.3** delta broadcasts — untouched here; the route table and
  `commit()` helper give it fewer call sites to rewrite when it lands.

# Phase 2 — facilitator-run resources and a three-column layout

## 23. Facilitator-run resources and a three-column layout — done

**Done — 23.1–23.7 all landed.** A deliberate simplification for the current
testing phase, in the spirit of `DESIGN_PRINCIPLES.md` #10 ("remove mechanics
until anything less would compromise the principles above") — the automatic
stone-routing and proposal/ability machinery built in sections 5, 10, and 19
asks the table to learn buttons before they've learned each other. This
section replaces most of that automation with the facilitator moving
resources by hand while everyone else plays the scene in voice, and rebuilds
the view around that: three viewport-sized columns (character sheets and the
facilitator panel; game state — NPCs, locations, session aspects; the event
log) under one top bar carrying the session text and the stone pool.

**This is explicitly a "for now."** The goal-directed and once-per-session
mechanics from sections 5, 10, and 19 are not deleted, only set aside — they
may come back once the table has played long enough with the manual version to
say what it actually needs. Every "open question" below is a real unknown, not
a placeholder for an answer already decided — capture what playtest says
rather than locking these in ahead of the table (per the project's working
notes on game design: loose ideas stay open questions until play settles
them).

### 23.1 The overcome roll: one click, draw two stones, touch nothing else — done

- [x] **The roll no longer touches the pool.** `pickTwoRandom`
      (`gameLogic.ts:56`) already sampled two stones without mutating its
      input; the new `/stones/draw` route (`handleDraw` in `GameTable.ts`)
      uses it through `drawFromBag` and passes `this.game` through unchanged
      to `commit` — a draw is a **read** of the current pool, not a write to
      it, full stop. `routeOvercomeDraw` and the `removeStones` call that fed
      it are gone from that path (`removeStones` itself stays, unused, as the
      removal half a future `/stones/remove` needs — see 23.2).
- [x] **That collapses the roll to one click, no reroll.** `pendingRoll`,
      `/stones/accept`, `/stones/reroll`, and the roll/reroll/accept
      three-step lifecycle are gone — `POST /stones/draw` (facilitator-only)
      is the one stateless action that draws and logs in the same click.
- [x] **Overcomes lose their target.** `Overcome`, `POST /overcome/start` /
      `/overcome/cancel`, and the target carve-out in `rollGate` are deleted
      (`rollGate` itself is gone — `/stones/draw` is a plain
      `facilitatorOnly` route now that there is no target to also admit). A
      draw is just a draw; bringing back a framed "start an overcome" beat
      later is additive, not a revert.
- [x] **Press Fate goes with the target.** `REROLL_COST` and the reroll-cost
      branch in the old roll handler are deleted outright.
- [x] **Aspect-Bane auto-marking goes with `routeOvercomeDraw`.**
      `archetype_banes` / `desire_banes` / `quest_banes` (migration `0009`)
      are no longer written by anything (`incrementAspectBane` stays defined,
      unused) — the columns and sheet dots stay in place, frozen at whatever
      they last held. Still an open question below which of the three
      outcomes that becomes permanently.
- [x] The draw is a **log line only**: `handleDraw` posts `Drew: <kind>,
      <kind>` and nothing else. `View/Stones.elm`'s two-state pending-roll UI
      collapsed to a single facilitator "Draw two stones" button as a direct
      consequence of `pendingRoll` leaving `GameState` — the result was
      always going to show up only in the log once there was no pending-roll
      state left to render inline. What the table decides those two stones
      mean for the pool, a sheet, or a session context is a separate,
      unconnected click through 23.2 (not yet built) — see that section for
      why the interface doesn't try to link the two.
- [x] **Help Out has nothing left to reroll.** `handleUseAbility` now refuses
      every `help-out` raise outright (400) instead of gating on
      `overcome`/`pendingRoll`, and the `help-out` arm of
      `handleProposalDecision` is unreachable dead code kept only so the
      switch stays exhaustive — per principle 10 this is interface
      subtraction, not schema deletion, so the `AbilityKind` / `ProposalKind`
      variant and the client's Help Out button (now permanently disabled,
      `View/Moves.elm`) stay in place.
- [x] **Pledges no longer have anything to spend into.** `committedBoons`
      still widens a draw's odds (`drawFromBag` adds one extra Boon per
      committed boon to the bag) but the accepted-roll step that used to
      deduct them from `fate` is gone with `handleAcceptRoll` — a pledge
      costs nothing right now. Flagged in the type doc comments
      (`worker/src/types.ts`, `client/src/Types.elm`) rather than resolved:
      this is the same "does pledge survive" open question below, not a new
      decision.

### 23.2 Facilitator: three free-standing resource actions — done

The facilitator's edits are **independent of each other and of a roll** — the
interface makes no attempt to associate a stone the facilitator adds to the
pool, or a session context they create, with the overcome that was just
drawn. That's deliberate, for now: the facilitator reads the table and the two
drawn stones, decides what they mean, and expresses that decision as any
number of these free, uncosted actions — clicking one has no effect on what
any of the others can do next. Read this as **one instance of a general
"the facilitator can hand-edit game state" capability**, not the whole of
it — anything shared that currently has no facilitator-write path is fair
game for this section; these three are just the ones known to need one today.

- [x] **Character sheets need no new route — they're already covered.**
      `/characters/:slot/update` (fields) and `/characters/:slot/fate`
      (boons, `{ delta }`, already signed either direction) are already
      owner-or-facilitator (section 4) and unchanged by this refactor:
      players keep editing their own sheets, and the facilitator keeps the
      existing edit rights over any sheet. **Adjusting a player's boons**
      already had its client affordance — the sheet's Grant `+` / `−`
      (`View/Characters.elm`'s `grantControls`) — predating this section; the
      pledge/proposal path it used to sit alongside is now disconnected
      too (see the open questions below), so Grant is the only way a boon
      moves onto a character.
- [x] **Add or remove a stone from the pool.** Facilitator-only
      `POST /stones/add` / `/stones/remove` (`handleAddStone` /
      `handleRemoveStone`, `GameTable.ts`), each taking
      `{ kind: "Boon" | "Bane" }`. `add` always succeeds; `remove` 400s if the
      pool holds none of that kind rather than silently broadcasting an
      unchanged pool. `removeStones` (`gameLogic.ts`) is the removal half,
      unused since 23.1 retired the roll's own pool write — this is its first
      real caller. Neither route posts a log line, matching the facilitator's
      existing direct `add-boon` (silent bookkeeping, not a narrated event).
- [x] **Add or remove a session context.** Facilitator-only
      `POST /stones/floating-boons` (`{ text }`) and
      `POST /stones/floating-boons/:id/delete` create and remove a
      `FloatingBoon` directly — the same shape an accepted Add a Detail /
      Gain Insight produces, without routing through that proposal. Both post
      a log line (`Session note added/removed — <text>`), unlike the pool
      routes, since a context note is worth recording. **Scope note:** this
      lands ahead of 23.3, so it creates/deletes today's Boon-only
      `FloatingBoon`, not yet the widened Boon-or-Bane shape 23.3 describes —
      widening the type will not need a new route, just a `kind` field on
      this one.
- [x] **Client wired up**, landing after the worker routes rather than in the
      same pass as originally sequenced below. `View/Stones.elm` gained
      facilitator-only pool controls (`poolControls` — Boon and Bane each get
      their own `+` / `−` pair, posting `AddStone Stone` / `RemoveStone Stone`)
      and, per floating boon, a facilitator "Remove" button, plus an
      always-visible (for the facilitator) "Add a floating boon…" field and
      button at the foot of the list — visible even with none yet, so there is
      always somewhere to add the first one. The player-facing "Add boon"
      button is gone entirely (see the resolved open question below); nothing
      else in the layout moved, since 23.5's three-column shell hasn't landed.
- [x] Resolved: the player-initiated `add-boon` proposal does not stay live.
      The "Add boon" button is removed from `View/Stones.elm` for everyone,
      player and facilitator alike — the facilitator now adds a Boon directly
      via `poolControls` instead of through a proposal. `Msg.AddBoon`,
      `Main.update`'s branch for it, and the worker's `applyAddBoon` /
      `proposeAddBoon` / `Kind.AddBoon` all stay in code, unreachable from any
      current UI, the same as `pledge` and Help Out.

### 23.3 Session aspects — floating boons *and* banes, with context — done

- [x] Widened `FloatingBoon` (`worker/src/types.ts`) with `kind: StoneKind`
      alongside its `text` / `createdByName`, so the facilitator can plant a
      floating **Bane** — a named complication hanging over the table — not
      only a floating Boon. A pre-23.3 blob has no `kind` on disk;
      `migrateStoneState` defaults every stored floating boon to `"Boon"`,
      since that was the only kind that could ever exist before now.
- [x] **The facilitator creates one directly**, typing the note and picking
      the kind on the spot (`POST /stones/floating-boons`, widened from
      23.2's Boon-only version to take `{ kind, text }`) — this direct path
      is what "make session aspects" means here. An accepted Add a Detail /
      Gain Insight still only ever produces a Boon (`handleProposalDecision`'s
      literal is unconditional); nothing currently lets a player raise one
      that comes out a Bane.
- [x] **`/stones/use-floating` is disconnected from the client**, by explicit
      call — its actual behaviour turned out not to depend on the
      accept-into-a-roll machinery 23.1 retired (it always added straight to
      the persistent pool, roll or no roll), so the roadmap's original
      reasoning for retiring it didn't hold. It's cut anyway, for the same
      reason `pledge` and `add-boon` were: a player-initiated action on
      shared state, in favour of the facilitator's direct create/delete. The
      "Use" button is gone from `View/Stones.elm`; `Msg.UseFloatingBoon`, its
      `Main.update` branch, `Effect.PostUseFloatingBoon`,
      `Api.postUseFloatingBoon`, and the worker's `handleUseFloating` /
      `"use-floating"` proposal accept are all untouched and fully
      functional, just unreachable from any current UI. A session context's
      lifecycle is now create and delete only, nothing in between.
- [x] Client: `View/Stones.elm`'s `floatingBoonsBlock` mixes both kinds now,
      styled by `kind` (a new `floatingBoonChip` — `Ui.pledgedStoneChip` in
      the Boon or Bane fill) — but it stays in the Stones card and keeps its
      "Floating boons" heading and glossary term for now (only the glossary
      *definition* text was updated, to describe Boon-or-Bane and the current
      create/delete-only lifecycle). The rename to "Session aspects" and the
      move into a centre game-state column are bundled with 23.5's layout
      rewrite, not done here. The facilitator's create row gained a Boon /
      Bane picker (`Ui.tab`-style toggle) next to the text field.

### 23.4 Moves: inert display, not code deletion — done

Per principle 10, this is subtraction from the interface, not from the
schema. The Moves card (Help Out, Add a Detail, Gain Insight, Suggest Compel —
section 10 — plus Accept Compel) stops being clickable and becomes plain
text: a reminder of what a player can *say* at the table, not a control that
posts anything. Nothing about it is deleted:

- [x] **The `Msg` constructors, `Effect`s, `Api` calls, and the worker's
      proposal / ability routes all stay in the code as-is**, just
      disconnected from any control the player can press. `client/src/View/
      Moves.elm` carries a single `-- OFF while testing simplified interface
      (roadmap section 23.4)` note in its module doc naming every disconnected
      `Msg` (`UseAbility`, `SuggestCompel`, `AcceptCompelMove`), so re-wiring
      later is a search for that string, not an archaeology dig through git
      blame.
- [x] `View.Moves` keeps its layout and copy but drops every button for a
      plain `moveLabel` text element (`used`-suffix logic unchanged, just no
      longer wired to an `onPress`) — the card reads as reference text, not
      affordances. The dead `overcomeRoll = False` branch 23.1 left behind
      (Help Out's click was already permanently refused) fell out with it,
      since nothing in the card is clickable to gate anymore.
- [x] The proposal-pending / withdraw affordance this card used to show
      inline (`latestProposalId`, `withdrawLink`) is gone with it — nothing
      here can queue a new proposal, so there is nothing left to withdraw
      from *this* card. The general Proposals panel in `View/Stones.elm` and
      `proposals/:id/{accept,reject,withdraw}` are untouched and still the
      place to resolve or withdraw anything already queued, for the same
      find-it-later reason as the rest of this section.

### 23.5 Layout: three columns, sized to the viewport — done except the narrow-viewport fallback

Today's `Ui.page` (`client/src/Ui.elm:242`) is a single centred column with
cards stacked top to bottom inside a document-height `Element.layout`; only
the message log scrolls on its own (`View/Log.elm`'s `scrollbarY` region).
This replaces that shell with three independently-scrolling columns filling
the viewport:

- [x] **`Ui.page` becomes a fixed-height, three-column row.** `html` / `body`
      — and `#root`, the div elm-ui mounts into: a bare `<div>` does not
      inherit a percentage height from its parent, so the `height: 100%`
      chain (`client/index.html`) needs it too — get an explicit height, the
      outer `Element.layout` gets `height fill`, and the current outer
      `Element.column` becomes an `Element.row [ height fill, width fill ]`
      of `Ui.scrollColumn`s (`Element.column [ height fill, scrollbarY, width
      (fillPortion n) ]`). One more piece the roadmap didn't anticipate:
      every flex item along a scrolling region's ancestry that is sized by
      `height fill` (rather than a row's cross-axis stretch) also needs
      `min-height: 0` (`Ui.shrinkable`) — CSS flex items default to
      `min-height: auto`, which refuses to shrink a flex-grow item below its
      content's natural size, so without it a column just grows to fit its
      content instead of clipping and scrolling. Verified with a throwaway
      Elm harness rendering the real `View.elm` against fixture data under
      headless Chrome (no Discord SDK involved) — confirmed the page itself
      no longer scrolls, each column scrolls independently once its content
      overflows, and the fix actually engages (a column's `scrollTop` is
      genuinely settable, not just visually clipped).
- [x] **Left — character sheets and the facilitator panel.** `View.Characters`
      moved here as-is: its tab strip (`View/Characters.elm:67`,
      `Model.selectedSlot`) already let any viewer, facilitator included,
      switch which sheet is showing, which is what covers "the facilitator
      can switch their view to see the player sheets" — no new switcher
      needed, just this column reusing the existing one. 23.2's facilitator
      controls (pool add/remove) became their own panel in this column,
      `View/FacilitatorPanel.elm`, visible only to the facilitator —
      adjusting a player's boons needed no new panel, since the sheet's Grant
      `+` / `−` (already in `View.Characters`) already lives in this column.
      `View.Moves` joined this column too (not specified by the roadmap, but
      it is about what a player can say with their own sheet, so it sits
      with it).
- [x] **Centre — game state.** NPCs (`View.Entities Npc`), Locations
      (`View.Entities Location`), and the new session-aspects list (23.3,
      extracted into its own `View/SessionAspects.elm` and renamed from
      "Floating boons" as 23.3 anticipated) — three things that already read
      as "reference state the facilitator curates." `View.Session` (now just
      the past-sessions history, its goal and controls having moved to the
      top bar — 23.6) and `View.Guide` joined this column too, for the same
      "nowhere else the roadmap assigned them" reason as Moves above.
- [x] **Right — the event log.** `View.Log` moved here close to unchanged; it
      already owned the `scrollbarY` region and DOM id the pin-to-bottom
      behaviour (`Effect.ScrollLogToBottom`) needs, which keeps working now
      that it's the whole column (via a new `Ui.cardFill`, a `card` that
      fills its column's height instead of shrinking to content) rather than
      one card among several with its own internal `maximum 360` cap.
- [x] **Composer** stays pinned under the log column, not the whole page.
- [x] **Narrow-viewport fallback — resolved by section 24**, not by adding a
      breakpoint to the three-column row: the row itself is retired in favour
      of a two-panel layout, sidestepping the question this bullet asked
      rather than answering it.

### 23.6 Top bar: session text and the pool — done

- [x] A persistent bar above the three columns (not inside any of them,
      `View/TopBar.elm`): the running session's goal text (previously the
      whole `View.Session` card) and the stone pool (previously the bag row
      inside the old `View.Stones`). Both kept their existing data source
      (`gs.session`, `gs.stonePool`) — a move, not a new field.
- [x] Session start / end / goal-edit controls (facilitator-only, section 12)
      sit behind a ▸/▾ expander (`Model.sessionControlsExpanded`, toggled by
      `ToggleSessionControls` — same purely-local-state pattern as
      `guideExpanded` / `ToggleGuide`) rather than full-width, so the bar
      stays one line at rest.
- [x] The old `View.Stones` card is gone, its pieces moved: the pool (chips
      read-only, no pledge summary — pledge did not survive as a
      player-initiated action, per 23.2's resolved open question) to the top
      bar, session aspects to the centre column (23.3/23.5), and the single
      one-click roll action (23.1) plus the pool add/remove edits and the
      proposal queue to the facilitator panel in the left column
      (`View/FacilitatorPanel.elm`, 23.5).

### 23.7 Overcome and roll results: log line only — done

- [x] Mechanically simple in the end, since 23.1 removed the pending/accept
      lifecycle entirely: the facilitator's click *is* the draw, so the only
      place its result can show up is wherever that click's handler writes a
      log line. There was no inline pending-roll rendering left to remove
      from `View/Stones.elm` (23.6 already removed the whole card) — just
      confirming the one-click worker handler (23.1) writes a log line
      itself: `handleDraw` (`worker/src/GameTable.ts`) posts a message
      (`Drew: <kind>, <kind>`, plus a committed-boons note) through the same
      `commit` path every other mutation uses, since the old `/stones/accept`
      was where that used to happen and it no longer exists.

### Sequencing

A bigger cut than sections 1–22: it changes a wire shape (`Overcome` drops
`targetSlot`, `FloatingBoon` gains `kind`), retires the whole pending-roll /
accept lifecycle along with `routeOvercomeDraw` and the target-paid reroll
cost, disconnects a whole client card from its handlers without deleting
them, and rebuilds the view shell from the ground up. Character sheet editing
(`/characters/:slot/update` and its client form) is untouched throughout —
it's the one piece of shared state this section doesn't touch. Suggested
order, each its own branch off `main`:

1. **23.1** (worker + minimal client) — done: the stateless one-click draw,
   with worker tests; the existing single-column UI now drives `/stones/draw`
   directly rather than the retired roll/reroll/accept lifecycle.
   **23.2** — done: the three free-standing facilitator routes (pool
   add/remove, session-context add/remove; player-boon adjustment needed no
   new route), with worker tests; the worker routes landed decoupled from any
   client change as planned, and the client (`View/Stones.elm`'s pool
   controls and session-context field, plus removing the player-facing "Add
   boon" button) followed as its own pass right after.
2. **23.3** (worker + client) — done: the `FloatingBoon` → Boon-or-Bane
   widening, isolated from the layout rewrite since it's the other
   wire-format change. The "Session aspects" rename and the move to a centre
   column are still bundled with 23.5, as originally planned, so the visible
   card heading and glossary term are unchanged for now — only the type, the
   facilitator's create route, and the client's kind-aware rendering landed.
3. **23.4** (client) — done: the Moves card and its proposal-posting controls
   are disconnected, marked with 23.4's `-- OFF while testing simplified
   interface` comment convention.
4. **23.5 + 23.6 + 23.7** (client) — done, all three together as sequenced:
   the three-column shell (`View/FacilitatorPanel.elm`, `View/SessionAspects.elm`
   new; `View/Stones.elm` gone), the top bar (`View/TopBar.elm` new;
   `View/Session.elm` trimmed to just the history card), and confirming the
   one-click draw already logs its own result.

### Open questions to settle before or during play

- [x] Resolved, for now: the facilitator absorbs pledging rather than
      `pledge` surviving as a player-initiated action. The Pledge
      ("Highlight") `+` / `−` control on the sheet is disconnected
      (`View/Characters.elm`'s `boonsBlock` no longer calls
      `pledgeControls`) — boon movement is left to the facilitator's Grant
      control exclusively. The underlying machinery is untouched and easy to
      re-wire: `Kind.Pledge`, `applyPledge`, `/stones/commit`, and
      `drawFromBag`'s committed-boons odds bump all stay in code, just
      unreachable from the current UI.
- [x] Resolved, for now, same as pledge: the player-initiated `add-boon`
      proposal does not stay live now that the facilitator has a direct
      `POST /stones/add`. The client's "Add boon" button is removed
      (`View/Stones.elm`); `Msg.AddBoon`, `Main.update`'s branch, and the
      worker's `proposeAddBoon` / `applyAddBoon` / `Kind.AddBoon` are
      untouched and unreachable from any current UI.
- [x] 23.1 resolved this one rather than leaving it open: `/overcome/start` /
      `/overcome/cancel` did not survive — a draw is just a draw, with no
      distinct "start an overcome" step. If the table finds it still wants an
      overcome framed as its own beat, that's a small addition back, not a
      revert.
- [x] Resolved, same reasoning as pledge and add-boon (23.3): `use-floating`
      does not stay live as a player-initiated action, even though — unlike
      those two — its own mechanics never actually depended on anything 23.1
      retired (it always added straight to the persistent pool). Cut anyway,
      for consistency with the direction the other two already set. The
      worker route and proposal accept are untouched and fully functional,
      just unreachable from the client.
- [x] Resolved by 23.4, uniformly with the rest of the Moves card rather than
      as a special case: Add a Detail / Gain Insight no longer survive as
      player-initiated proposals — `View/Moves.elm`'s `abilityRow` dropped
      the `onPress` off every entry alike (Help Out, Add a Detail, Gain
      Insight), so a session context now comes only from the facilitator's
      direct create (`View/SessionAspects.elm`, any kind) or from resolving
      whatever Add a Detail / Gain Insight proposals were already queued
      before 23.4 shipped. The proposal routes and `handleProposalDecision`'s
      Boon-only literal for an accepted one are untouched, just unreachable
      from any current UI.
- [ ] Does aspect-Bane tracking freeze as read-only history, become a manual
      facilitator field, or drop off the sheet display while nothing writes
      it?
- [x] The narrow-viewport fallback for the three-column shell (23.5's last
      item) — resolved by section 24, which retires the three-column shell
      rather than adding a fallback to it.

## 24. Two-panel layout, replacing the three-column shell — done

Where section 23 rebuilt the view as three viewport-sized columns, this
retires that shell in favour of two. Chosen from three directions sketched in
a design canvas (a steady scroll-stack left panel with a flat tab strip on
the right; both panels tabbed, player-sheet-first; an accordion left panel
with a draggable divider and the log pinned beneath a tab strip rather than
inside it) — the accordion-plus-divider direction ("1c" in that canvas), after
a first pass had already shipped and been reverted in favour of it. The top
bar is untouched (23.6's goal expander and the Facilitator panel's own Draw
button stay exactly where they were) — 1c's mockup also sketches an inline
top-bar goal editor and a top-bar Draw button, but that revisits an already-
shipped, separately-numbered decision rather than the three-vs-two-panel
question this section is about.

- [x] **Left panel: three collapsible accordion sections, not a fixed
      stack.** `View.FacilitatorPanel`, `View.Characters`, `View.Moves` keep
      their content exactly as 23.5 arranged it, but each card's own title is
      now also its accordion toggle — the same self-contained
      title-doubles-as-toggle pattern `View.Guide` already used, factored out
      as `View.Helpers.accordionHeader` / `accordionHeaderWith` (the `With`
      variant adds a trailing element, for Moves' "n of 4 left" once-per-
      session-abilities-remaining count, visible whether or not that section
      is open). Open/closed state is `Model.openLeftSections`
      (`LeftSections`), toggled by `ToggleLeftSection` (`LeftSection`);
      Facilitator and Characters default open, Moves closed, since a player
      checks their own sheet far more often than the Moves reminder card.
- [x] **The left/right split is mouse-draggable, not a fixed `fillPortion`.**
      `Model.leftPanelWidth` (a pixel width, defaulting to 420, clamped to
      280–640) sizes the left panel directly; `Ui.dragHandle`, a slim
      `cursor: col-resize` strip with a small grip mark, sits between the two
      panels and fires `DividerDragStarted` on mousedown. While
      `Model.draggingDivider` is true, `Main.subscriptions` adds
      `Browser.Events.onMouseMove` (reading the browser's own `movementX` off
      each event, so no element geometry needs measuring) and `onMouseUp`,
      posting `DividerDragged <deltaX>` / `DividerDragEnded`. No JS port
      needed — `Browser.Events` (already an `elm/browser` dependency) is
      enough on its own.
- [x] **Right panel: a three-tab strip over shared state, with the log pinned
      below it rather than inside it.** `RightPanelTab` — NPCs & Locations
      (`View.Entities Npc` + `View.Entities Location`); Session context
      (`View.SessionAspects` + `View.Session`); How to play (`View.Guide`,
      unchanged, including its own now slightly redundant expand/collapse —
      left alone rather than reworking its internal state for this pass) —
      switched by `SelectRightPanelTab`, defaulting to NPCs & Locations.
      Beneath the strip, `View.Log` is always visible regardless of which tab
      is selected, at roughly the mockup's 56/44 split (`fillPortion 5` for
      the tab content, `4` for the log). A tab's content is a plain
      `Ui.scrollArea` stack of the cards it combines — the non-`fillPortion`
      half of what `Ui.scrollColumn` already did, factored out so a region
      can scroll independently of the panel hosting it without pretending to
      be one of the page's own top-level columns.
- [x] **Composer moves off the log column onto the page.** With the log no
      longer confined to one tab's worth of visibility, and the whole point
      of pinning it beneath the strip being that it's never hidden, the
      composer follows it out to page level anyway — sending a message
      should not depend on which tab is showing above the log. `Ui.page`
      gains a third region, `bottom`, rendered under the columns row with a
      hairline top border (hidden entirely when empty, as during the
      pre-game-state loading screen); the composer is its only occupant.
- [x] Verified by rendering the real `View.view` against a hand-built fixture
      in a throwaway Elm harness under headless Chrome (same verification
      approach 23.5 used) — checked all three right-panel tabs with the log
      pinned beneath, the accordion both open and closed (including Moves'
      remaining-count summary), and both roles, with tab/accordion state
      changed through the real `Main.update` rather than a hardcoded
      snapshot. The drag interaction itself was not driven by a script (a
      static screenshot can't show motion); its mouse-subscription gating
      follows the same pattern already exercised elsewhere in `Main.update`.

## 25. Architecture review follow-ups — deferred until section 26 lands

**Reassess after section 26.** Section 26 (player moves and the Overcome loop)
goes first and reshapes the very handlers 25.1 restructures — the proposal kinds,
the roll lifecycle, and the session reset. Its worker tests are what will protect
25.1's restructuring. 25.3 and 25.4 are client-only and independent; 25.4 is
scheduled as the first step of 26.3. 25.5 and 25.7 are largely reshaped by 26.2
(see section 26).

An architecture review (2026-09-18) looked for places where a module's
interface is as wide as its implementation, where a rule lives in several
hand-synced copies, and where a seam is missing. It ranked seven candidates and
recommended one — a pure rules core behind `GameTable` — as the only one that
changes the test surface, and as the one that must be decided *before* P2.2
would split the handlers in place.

**Re-baseline before starting.** The review read `main @ dee429e`
(2026-09-10), which predates section 23. Section 23 retired the roll / reroll /
accept lifecycle, the `Overcome` concept, the session verdict and untethering,
and the `View.Stones` card; section 24 replaced the three-column shell. So parts
of the review's "before" pictures no longer exist (`handleAcceptRoll`,
`routeOvercomeDraw`, `deriveOutcomeKind`, the `carriedBanes` /
`lastSessionFailed` DO fields, `SessionOutcomeKind`). Each item below is stated
against the current code, with what the review found and what is left of it. The
review also refers to a "plan file" and an ADR-0001 recording the settled design
for candidate 1; neither is in this repository. Re-derive or recover that design
(a short design pass, not code) before 25.1 starts, and land it as an ADR here.

Same conventions as the rest of the roadmap: one branch per item off `main`,
`DESIGN_PRINCIPLES.md` as the yardstick, and no behaviour change — every item is
a restructuring, verified by the existing suites plus the new tests it makes
possible.

- [ ] **25.1 — A pure rules core behind `GameTable`** (the review's top
      recommendation). Today the rules are interleaved with D1 awaits: a handler
      does its D1 write, then updates memory, then commits (storage put, message
      insert, broadcast), so a throw between the two leaves D1 ahead of memory,
      and the rules are reachable only through `SELF.fetch`. The review's shape:
      a `rules/` module exposing `transition(state, command, deps)` over a
      `Command` union, with injected dependencies (the RNG, the clock) and a
      return of `{ next, log?, writes[] } | Refusal`. `GameTable` keeps auth,
      `withLock`, body parsing, turning a request into a `Command`, flushing the
      `writes` in one `DB.batch`, the storage put, and the broadcast. Internal
      seams: session, stones, proposals, characters. What it buys: every rule in
      one module (locality), tests that seed the RNG and call `transition`
      directly with no `workerd` or HTTP loop (leverage), and one D1 write path.
      Still true after section 23: `handleProposalDecision` (`GameTable.ts`
      1050–1233) is the largest interleave, and `gameLogic.ts` is mostly single-
      caller leaf helpers. No longer true: the two DO-owned fields outside
      `GameState` (only the legacy read in `migrateStoneState.ts` remains).
      **Supersedes P2.2** — that split relocates the interleave into five
      handler files; this removes it. The route table half of P2.2 survives on
      its own.
- [ ] **25.2 — One "change a sheet" seam** (absorbed by 25.1). Four handlers
      hand-copy the replace-by-slot `characters.map` over `this.game.characters`
      (`GameTable.ts` 1283, 1600, 1638, 1677, 1715) beside the one-statement D1
      wrappers in `characters.ts` (`setFate`, `setOwner`, `updateFields`,
      `incrementAspectBane` — the last has no writer since 23.1). The review's
      fix is a `patchSheet(state, slot, patch)` that returns the next state and
      queues the write as data, so the in-memory and D1 halves cannot diverge.
      The review counted nine copies; fewer remain now that the roll paths are
      gone, but the shape is the same.
- [ ] **25.3 — A named edit cursor on the client.** "What is locally edited and
      unsaved" has no name or type: `Model` carries `editingSlot`,
      `editingEntity` and the dirty sets (`Types.elm`), and `applyServerState`
      merges the character half and the entity half as near-verbatim copies. The
      entity half has no tests. Add an `EditCursor` module owning those fields
      and the protect-merge (`startEditing`, `markDirty`, `blur`, `flushed`,
      `protect : EditCursor -> GameState -> GameState -> GameState`), generic
      over slot / entity id, so the entity half inherits the character tests and
      `Model` loses several fields for one. Independent of 25.1 — client only,
      can go first.
- [ ] **25.4 — Typed in-flight action keys.** In-flight state is a
      `Set String` keyed by strings like `"stones:add-boon"`, matched by prefix
      across `Main` (`clearInflight`), `Effect` and the views, so a typo compiles
      and a family clear is a `String.startsWith`. Replace the key with an
      `Action` custom type owned by `Effect` and carried in `ViewContext`, so the
      compiler checks every key and every section can grey its own button, not
      only the ones handed `inflight` today. `Main.guard` keeps its call sites.
      Independent of 25.1 — client only. Re-check which `View.*` modules take
      `inflight` now that `View.Stones` is gone (`SessionAspects` and the
      top-bar / facilitator views do).
- [ ] **25.5 — Session reset as data.** Only half of the review's finding
      survives: the outcome half (`deriveOutcomeKind` recovering a kind by
      substring search on a sentence) went away with the session verdict. What
      remains is that "nothing carries between sessions" is two hand-synced
      lists — the same four fields (`usedAbilities`, `floatingBoons`,
      `committedBoons`, `proposals`) reset separately in `handleStartSession` and
      `handleEndSession` — and the "Session start / end clear pending state"
      note in `CLAUDE.md` must be kept in step with both. One
      `clearSessionState : GameState -> GameState`. Absorbed by 25.1; if 25.1 is
      delayed, this is small enough to land alone.
- [ ] **25.6 — Narrow `Effect`'s backend half** (speculative). The backend half
      of `Effect.elm` is one constructor per `Api` call — roughly two dozen
      `Post*` constructors — so it is as wide as its implementation, and some
      carry raw route data (`PostStones Auth String` a path,
      `PostProposalDecision` an `"accept"` / `"reject"` string). The review's
      option: one `Post Auth Request` constructor over a request-description type
      built in `Api`, keeping the task / port constructors, which are where tests
      get their leverage. A new endpoint would touch `Api` only and route strings
      would leave `Main`. Speculative: do it only if the wide constructor list
      keeps costing edits after 25.3 / 25.4.
- [ ] **25.7 — Worker `Proposal` as a discriminated union** (absorbed by 25.1's
      proposals branch). The client already models the union (`Kind.elm`); the
      worker flattens it to nullable columns and re-checks per arm
      (`slot: number | null`, `floatingId`, `targetSlot`, the `proposal.slot ??
      -1` sentinel at `GameTable.ts:1116`), and `switch (kind)` has no
      exhaustiveness check, so a missing arm accepts silently. Target shape:
      `AddBoon | Pledge {slot} | Ability {slot, kind, target?} | UseFloating
      {slot, floatingId}` with a `never` check. `migrateStoneState.ts` must read
      already-stored flat proposals into it.

### Sequencing

- **25.3 and 25.4** are client-only, independent of everything else, and can
  ship in either order at any time.
- **25.1** is the big one and needs its design pass first; **25.2, 25.5 and
  25.7** ride with it (each is a step it makes cheap, and each can also land as
  a preparatory PR ahead of it if that keeps the diff reviewable).
- **25.6** waits.
- P2.2 stays on the Phase 3 list only for its route-table half; retire it once
  25.1 lands.

### Open questions

- [ ] Recover or re-derive the 25.1 design (the review's plan file / ADR-0001);
      decide the `Command` and `writes` shapes, and whether `writes` are
      `DB.batch` statements or a higher-level record.
- [ ] Does moving to one `DB.batch` change any failure ordering the current
      D1-then-memory sequence relies on? Settle before touching a handler.
- [ ] Where do the pure-rules tests live — under `worker/test/` with
      `gameLogic.test.ts`, run without `workerd` — and does `vitest` need a
      second, plain-Node project for them?

## 26. Player moves and the Overcome loop — next

Section 23 moved every stone and boon onto the facilitator's hands for the
testing phase, and section 24 fixed the layout. Playtest said what that cost:

- **Leftover stones skewed the pool.** Boons and Banes left in the shared pool
  after a roll compounded over a session and skewed later results heavily.
- **Players missed pressing buttons.** With the facilitator doing every
  manipulation, players had nothing to trigger.
- **Some Moves UI was stale** (copy naming abilities that no longer exist,
  controls that do nothing), and the layout was clunky, which section 24 already
  addressed.

This section gives the players their moves back, restores the roll lifecycle in
a simpler form, and makes the pool reset itself. **`RULES.md` is the canonical
statement of the rules this section builds; this section is the plan, not the
rules.** It was settled in a design interview (2026-09-18); the decisions below
are recorded so the reasoning survives.

### Decisions

- **Five official move names, used in copy and code alike:** Highlight,
  Overcome, Complicate, Add Detail, Alter Fate. "Pledge" and "compel" are retired
  everywhere; so are Gain Insight (folded into Add Detail) and Accept Compel
  (Complicate replaces every compel reference).
- **Every player move needs facilitator approval**, except editing a sheet and
  sending messages, plus **Overcome**, which any player may press with no
  approval. Both halves of every move (the proposal and its resolution) write a
  message-log line.
- **No once-per-session limits.** Moves are limited by cost only, plus Alter
  Fate's own rules (only during a pending roll, once per player per Overcome, one
  pending at a time).
- **Costs are checked at proposal time** (the client disables the button when the
  player's boons are too few; the worker also refuses the proposal with a 400) and
  **again at accept time** (409, proposal stays queued). Costs are **paid on
  approval only**. Highlight costs 1, Add Detail costs 1, Alter Fate costs 2.
  Complicate and Overcome are free.
- **The Overcome loop:** prepare the pool → one player rolls → optional Alter
  Fate rerolls → the facilitator accepts or rejects. Accept **resets the pool to
  two Boon and two Bane** and auto-creates a session boon or bane from a pair.
  Reject discards the roll and changes nothing else. One roll pending at a time.
- **"No pool changes after the roll" is a table rule**, not a worker guard.
- **Session boons and banes** replace floating boons: one `SessionAspect` type
  with a `consumed` flag. Spending marks consumed instead of deleting; a consumed
  one cannot be spent again; the facilitator can unconsume, as a correction.
  They persist across sessions. Players spend session boons through a proposal;
  the facilitator uses session banes (or boons) directly.
- **Sessions do nothing special on start or end** beyond recording the goal and
  dates. No verdict, no pool top-up, no clearing of anything else. The message
  log is the persistent record; real session logs come later.
- **No aspect Banes.** Nothing writes them and the sheet display is left alone
  until advancement is designed.
- **Work order: this section before section 25.** Section 25 is reassessed once
  this lands.

### What this reverses or supersedes

- **§23.1's stateless draw.** `/stones/draw`, "a draw touches nothing", and the
  facilitator-only gate give way to a stateful pending roll. The roll/reroll/
  accept *lifecycle* returns; `Overcome`-as-a-targeted-action and Press Fate's
  target-paid reroll do not (Alter Fate replaces both).
- **§23.4's inert Moves card** and the pledge / add-boon / use-floating
  disconnections recorded in §23's open questions. The player-initiated
  `add-boon` proposal stays cut; the facilitator's direct add stays.
- **P2.12** (Complicate's suggester payout) — resolved: only the target is paid.
- **P2.13's Moves count item** ("n of 4 left") — moot with once-per-session gone.
  Its collapsed-Facilitator-header proposal count is folded into 26.3.
- **Section 25.5** (session reset as data) is mostly moot: sessions no longer
  clear anything. **25.7** (proposal discriminated union) gets cheaper because
  the kinds are being reshaped here anyway.

### 26.1 Vocabulary rename and `RULES.md` — no behaviour change

One branch, mechanical, so it is easy to review; the existing test suites must
pass unchanged apart from renamed identifiers.

- [ ] **`RULES.md`** at the repo root (drafted with this section); a
      `CLAUDE.md` convention that any rules change updates it and that
      `Copy/Terms.elm` follows.
- [ ] **Rename through types, `Kind`, `Msg`, `Effect`, `Api`, route paths, and
      stored proposal `kind` strings.** Proposed mapping (finalise on the
      branch; the client and Worker deploy together, so a wire rename is safe):

      | Now | Becomes |
      | --- | --- |
      | `Pledge`, `CommitBoon*`, `/stones/commit`, `PledgeDue` | `Highlight`, `/moves/highlight` |
      | `SuggestCompel` (`suggest-compel`), `targetSlot` | `Complicate` (`complicate`) |
      | `HelpOut` (`help-out`) | `Alter` (`alter`); copy says "Alter Fate" |
      | `AddDetail` (`add-detail`) | `AddDetail`, `/moves/add-detail` |
      | `FloatingBoon`, `floatingBoons`, `UseFloating`, `/stones/floating-boons` | `SessionAspect`, `sessionAspects`, `UseSessionBoon`, `/session-aspects` |
      | `/stones/draw` | `/overcome/roll` |

- [ ] **`migrateStoneState.ts` reads the old shapes**: old proposal `kind`
      strings map to the new ones, old floating boons become session aspects with
      `consumed: false` (and `kind` defaulting to `"Boon"`, as today). Old message
      rows are not rewritten.
- [ ] **Copy rename only**: `Copy.elm` / `Copy/Terms.elm` use the five names and
      drop "pledge" and "compel"; the card title becomes "Session boons & banes"
      (veto welcome). The *mechanics* copy is rewritten in 26.4, once they exist.
- [ ] Check that `/stones/add-boon` (the facilitator's direct action) is not
      redundant with `/stones/add`; keep it if it is not, note the reason here if
      it is dropped.
- [ ] Update the `CLAUDE.md` route lists and naming as part of the rename.

### 26.2 Worker: the rules — test-first

The interesting branch. Build each rule as pure functions in `gameLogic.ts` first
(with plain unit tests that need no `workerd`), then wire them into `GameTable`.
Section 25.1 will later restructure the handlers; these tests are what protect it.

- [ ] **Pending roll** in `KEY_STONES` next to the proposals:
      `{ stones, rolledBy, rerolls } | null`, broadcast in `GameState`.
      `POST /overcome/roll` (any authenticated player): 409 if one is pending;
      draws two stones from the pool without touching it; logs the roll.
- [ ] **`POST /overcome/reroll`** (`facilitatorOnly`, needs a pending roll):
      free, immediate, logs.
- [ ] **`POST /overcome/accept`** (`facilitatorOnly`): resets the pool to
      `INITIAL_STONE_POOL`; a Boon+Boon draw creates a session boon, a Bane+Bane
      draw a session bane (default text, `createdByName` = the roller); clears the
      pending roll and the per-overcome Alter flags; withdraws any queued Alter
      proposals; logs the final result. **`POST /overcome/reject`**: discards the
      pending roll, clears the flags, withdraws queued Alter proposals, changes
      nothing else, logs.
- [ ] **`Proposal` kinds**: `Highlight`, `Complicate`, `AddDetail`, `Alter`,
      `UseSessionBoon`, one route each under `/moves/`. Each requires a claimed
      sheet, checks its cost at proposal time (400), and again at accept (409).
      Cost is deducted on approval only.
      - `Highlight`: proposer's `fate` −1, pool +1 Boon.
      - `Complicate` (`{ targetSlot }`): target's `fate` +2; the suggester is
        not paid; `SUGGEST_COMPEL_SUGGESTER_BOONS` is deleted.
      - `AddDetail` (`{ text? }`, blank allowed): `fate` −1; creates a session
        boon; the facilitator's accept may carry edited text.
      - `Alter`: requires a pending roll, no other pending `Alter`, and the
        proposer not already in this Overcome's used set; `fate` −2; rerolls;
        marks the proposer used. A rejection changes nothing and does not mark
        them used.
      - `UseSessionBoon` (`{ id }`): 409 if already consumed or gone; marks
        consumed; pool +1 Boon.
- [ ] **Session aspects**: `consumed: boolean`. Facilitator routes: create, edit
      text, delete, `use` (direct: marks consumed, adds its kind to the pool, no
      approval), and `unconsume`. Both create and use write log lines.
- [ ] **Delete** what no longer has a reason to exist: `usedAbilities` and its
      `KEY_STONES` field, `committedBoons` and `drawFromBag`'s odds bump,
      `GainInsight`, `AcceptCompel` and `/moves/accept-compel`,
      `SUGGEST_COMPEL_SUGGESTER_BOONS`, the `help-out` always-400 branch, and the
      old stateless `/stones/draw`. Session start/end stops clearing pending
      state and stops topping up the pool.
- [ ] **Tests** (`worker/test/`): the full loop end to end — prepare, roll, Alter
      accepted, Alter rejected (not counted), second Alter by the same player
      refused, facilitator reroll, accept (pool reset, session aspect created for
      a pair, none for a mixed draw), reject (pool untouched) — plus every cost
      boundary (exactly enough, one short), the 409 re-check at accept, and
      `migrateStoneState` over an old blob.
- [ ] Update `CLAUDE.md`'s "Realtime" section and the facilitator-only route
      list for the new routes and the retired ones; add a `CHANGELOG.md` bullet.

### 26.3 Client: moves, Overcome, and the facilitator queue

- [ ] **Prototype first** (`/prototype`, throwaway): the top bar carrying the
      Overcome button and the pending roll beside the pool. Settle the layout
      before wiring it.
- [ ] **Do roadmap 25.4 first** (typed in-flight action keys), so the new buttons
      get their greyed-while-in-flight state from the compiler rather than a
      string prefix.
- [ ] **Top bar**: Overcome button (any player), the pending roll's stones and
      rerolls visible to everyone, and the facilitator's Accept / Reject / Reroll.
- [ ] **Moves accordion**: real buttons for Highlight, Complicate (with a
      target picker over the other claimed sheets), Add Detail (with a text
      field), Alter Fate (visible only while a roll is pending), and a "Use" on
      each unconsumed session boon. Each button is disabled when the player's
      boons are too few, matching the worker's proposal check. No "n of 4 left".
- [ ] **Facilitator accordion**: the proposal queue for the new kinds, with an
      editable text field on Add Detail, and a **pending-count in the header** so
      a collapsed panel still signals a waiting proposal (P2.13).
- [ ] **Session boons & banes card**: kind-coloured chips with a visible
      consumed state; facilitator-only Use / Unconsume / Delete / edit text and the
      always-visible add row that already exists.
- [ ] Tests: `Api.decodeGameState` over a snapshot with a pending roll and a
      consumed session aspect; `Main.update` guards and the `Effect` each new `Msg`
      yields.

### 26.4 Copy, glossary, and a real playtest

- [ ] Rewrite `Copy.elm` and `Copy/Terms.elm` to the mechanics in `RULES.md`
      (cost text on each move, the Overcome loop, Alter Fate's conditions);
      remove every stale reference (once-per-session, compel, floating boon,
      pledge).
- [ ] Sweep the Moves and Facilitator UI for the "outdated elements" the
      playtest flagged; fix what is found.
- [ ] `pnpm run build` green, then one **table playtest** against the checklist
      below, and record what it showed here.

### Manual playtest checklist

- A player Highlights, is accepted, and the pool visibly gains a Boon.
- A player cannot press a move whose cost they cannot pay.
- Two players press Overcome at once: one wins, the other sees a refusal.
- Roll → Alter Fate → accepted: the log shows roll, reroll, then the accepted
  result. A rejected Alter Fate costs the player nothing and they can try again.
- A second Alter Fate from the same player in one Overcome is refused.
- Accept with two Boons → a session boon appears; accept with a mixed draw → none;
  either way the pool is 2/2.
- Reject → nothing changes and the roll can be pressed again.
- A session boon is used, shows consumed, cannot be used twice, and the
  facilitator can unconsume it.
- Ending a session changes nothing except the history.

### Sequencing

Branches 26.1 → 26.2 → 26.3 → 26.4, each off `main`, merged before the next
starts; a section-26 docs branch (this file and `RULES.md`) goes first. §25.4
lands as the first commit of 26.3. Nothing deploys until asked.

### Open questions

- [ ] **Two proposals pending against the same boons.** A player with two boons
      can queue Alter Fate (2) and Highlight (1); both pass the proposal check,
      and the second accept 409s. Tolerated for now. If it bites at the table,
      count the player's own pending costs against what the buttons allow.
- [ ] **Add Detail's text on a blank proposal and a blank accept.** The worker
      falls back to a default (`Detail from <name>`); revisit the wording in play.
- [ ] **Where rolled stones sit in the log.** The log carries each roll and
      reroll as its own line; whether the UI should also fold them into one
      "Overcome" entry is a presentation question for 26.3.
- [ ] Aspect Banes and advancement — deliberately unresolved (see `RULES.md`).

# Phase 3 — potential future plans

Everything still open, moved out of the Phase 1 sections above so it sits in one
list. Same conventions: each item is its own branch off `main` with a
professional commit message, and `DESIGN_PRINCIPLES.md` is the yardstick. Items
are roughly in value-over-effort order; the last two are explicitly not planned
or not scheduled. Section 26 above (Phase 2) is next; everything here is
further out.

## P2.1 — Remaining test coverage (from §11)

The Effect refactor and both `pnpm run test` suites shipped in CI; these gaps
remain.

- [ ] **`avh4/elm-program-test` flows**, for paths that span several messages
      (the current tests fold `Main.update` directly):
  - auth → `GetGameState` → `GotGameState` seeds the board; a later socket
    snapshot wins over a slower `GET /messages` (`GotGameState` guards on
    `model.gameState`).
  - raising a move queues it and shows the "(pending)" hint without touching
    shared state.
- [ ] **Discord `fetch` stub.** Stub `fetch` to `discord.com` in a setup file so
      the worker suite is fully offline; `handleDiscordExchange` gets a canned
      token + `users/@me` response for the happy-path exchange. The `oauth`
      tests currently cover only `pruneExpiredSessions` and the
      input-validation paths, which never reach `discord.com`.
- [ ] **Extra `GameTable` coverage:** cold-start load (seed `messages` /
      `characters` in D1, assert the first snapshot), the overcome reroll
      `REROLL_COST` deduction, `/stones/accept` clearing the overcome, the Accept
      Compel payout, and the section-12 session-end clear of `overcome` /
      `pendingRoll` / `committedBoons` / unresolved `proposals`.

## P2.2 — Split `GameTable.ts` — section 22 step 6 Part 2 (from §22)

The module reshaping, deferred as its own effort so it gets the dedicated
test-coverage pass the "no behaviour change" gate needs — the existing suite
does not touch every handler path.

**Largely superseded by section 25.1.** An architecture review found that
splitting the handlers into `worker/src/handlers/` relocates the D1-await /
rules interleave into five files rather than removing it; 25.1's pure rules
core removes it. Only the route-table item below survives independently. Do not
start the handler split before 25.1 is decided.

- [ ] **Route table.** Replace the `fetch` if-ladder with a declarative `ROUTES`
      array — `{ method, path: string | RegExp, gate?: "facilitator" | "roll",
      handler }` — matched in a loop, plus a `parseSlot` helper.
- [ ] **Handler modules** under `worker/src/handlers/`: `stones`, `session`,
      `characters`, `entities`, `proposals`. Each takes a `HandlerContext`
      (`{ game, env, commit, appendMessage, broadcast }`, plus a way to write
      back the `carriedBanes` / `lastSessionFailed` instance fields). The DO
      class keeps routing, lifecycle, `withLock`, auth, and the context. This
      also absorbs section 22 step 5's `handleProposalDecision` per-kind
      resolver extraction, whose arms lean on `drawFromBag` / `bumpFate` /
      `readJson`.
- [ ] Update the `GameTable` description in `CLAUDE.md` and the test-coverage
      notes for the new module layout.
- Target: no file in `worker/src/` over ~500 lines. `GameTable.ts` is ~2200
  after Part 1 — the reshaping is what shrinks it.

## P2.3 — Delta broadcasts (from §15)

- [ ] Replace the whole-`GameState` push on every mutation with a tagged patch
      — `{ t: "message", message }`, `{ t: "stones", … }`,
      `{ t: "proposals", proposals }`, and so on — that the client folds into its
      local state. Keep `{ t: "snapshot", state }` for connect and an explicit
      resync. Cuts the client-side decode.

The largest and riskiest item on the list: it rewrites the wire protocol, every
broadcast call site, and the client fold, and it does not reduce request count.
The 50-message window (§15) already shrank the payload. Section 22's route table
and `commit()` helper give it fewer call sites to rewrite when it lands.

## P2.4 — Reuse a still-valid `sessionToken` across reloads (from §14)

- [ ] Persist the `sessionToken` in `localStorage`; on reload, skip
      `/api/oauth/discord/exchange` while `expires_at` is still in the future.

Lower value — Activities usually launch fresh rather than reload — but one
request saved when they don't. Needs a new port + a `DiscordBridge` change, so
its own branch.

## P2.5 — Self-serve facilitator claiming (from §5)

- [ ] The first authenticated user at a `tableId` with no facilitator claims it,
      stored per-table (new migration).

Needs a hand-off path; the obvious failure mode is a player launching first. Not
needed while `BOOTSTRAP_FACILITATOR_ID` covers a single known facilitator.

## P2.6 — Overcome-aftermath playtest questions (from §19)

The section-19 rules shipped; these stay open until the table has played with
them.

- [ ] **Cadence.** At base rates a failure lands roughly every ~3 sessions and
      each character reckons every ~6–9; Highlights lengthen the cycle, hoarding
      Boons shortens it. Check this feels right at the table.
- [ ] Whether compels need a per-session cap after all.
- [ ] The exact frenzy lockout — broken-aspect-only, or broader.
- [ ] Whether the facilitator may call a foregone-failure session early — once
      the carried Bane debt exceeds a session's realistic Boon ceiling — and cut
      straight to the untether scene.

## P2.7 — Character growth on the sheet (from §20)

Largely absorbed into §19: growth **is** the untether resolution — the forced
rewrite or replacement of an aspect after a reckoning — with the `condition`
line as the visible running record of strain between reckonings. A rewrite
changes what an aspect *means*; it never adds a rating (principle 5, "grow in
depth, not strength").

- [ ] Pin down what a rewrite may do: reword the aspect only, swap an ability
      tied to it, or retire the character outright.
- [ ] Decide whether anything persists across a reckoning besides the rewritten
      aspect — all Banes clear, but does the character keep any marker of what
      they went through?

## P2.8 — Campaigns: multiple games per facilitator (from §17, not scheduled)

Today `tableId` (`guildId-channelId`) is the unit of persistence: one Durable
Object per channel owns one set of characters, one message log, one session
history. A **campaign** would become the real container — a named game a
facilitator creates and manages, owning its characters, NPCs, locations, session
history, and log — and the facilitator would pick which campaign is active for
the channel at Activity start.

This is a large reshaping. It touches the Durable Object's binding model (the
object is keyed by `tableId` and eagerly loads everything for it), needs a
`campaigns` table and an active-campaign pointer per table, a campaign-selection
screen, and a migration path for existing single-campaign tables.

- [ ] Design the data model and the DO-binding change before committing to it.

## P2.9 — AI session summary (from §18, exploratory)

A short written recap of each session, generated when the facilitator ends it
and stored on the `game_sessions` row for the history view.

The open question is the input. Sessions run two to three hours of mostly voice,
and there is no obviously free way to transcribe that live. But the message log
already captures moves, rolls, overcomes, the session goal, and any chat — an
LLM summary of a session's log rows may be a rich enough record without
transcribing voice at all. Settle that before reaching for transcription
(browser `SpeechRecognition` is free but needs a live foreground tab and is
unreliable over hours; hosted Whisper-class APIs are not free at that length).

- [ ] Spike: summarise a completed session from its log rows with a single
      Claude API call at `/session/end`, and judge whether the log alone carries
      the session.

## P2.10 — Split `KEY_STONES` storage (from §16, not planned)

- [ ] Split `KEY_STONES` into `stones` / `proposals` / `session` / `overcome`
      keys so adding a proposal does not rewrite the whole blob.

**Not planned** — the write-skip in §16 already removes the no-op rewrites;
revisit only if Durable Object write metrics move.

## P2.11 — A real tooltip element (from §21.3)

The §21.3 tooltips are the native `title=` attribute only (`Ui.withTip`, applied
through `View.Helpers.glossaryTitle` / `tip` / `tipAttrs`). That is hover-only
and mouse-only: it needs about a second of a stationary pointer, shows nothing on
tap or keyboard focus, and in practice does not render at all inside the Discord
Activity webview — so in the shipping context the glosses are effectively
invisible and the §21.4 "How to play" card is carrying all of the load. The
built bundle is correct; this is a limitation of the mechanism, not a bug.

- [ ] Replace `Ui.withTip` with a real tooltip in `Ui` — a small bubble shown on
      hover, tap, and focus, positioned near the trigger, dismissed on blur /
      Escape / outside tap. No `Model` state if it can be done with a CSS
      `:hover` / `:focus-within` sibling; a lightweight `Model` open-id
      otherwise, following the `aspectExamplesOpen` pattern.
- [ ] Keep the call sites (`glossaryTitle` / `tip` / `tipAttrs`) and their
      `Copy.Terms.termShort` source unchanged so only the leaf rendering moves.
- [ ] Verify it actually appears inside the Discord Activity, not just a desktop
      browser tab.

## P2.12 — Complicate drops the suggester's own payout (from the Alter/Complicate copy pass)

The Moves card and Guide now describe the former Suggest Compel move under a
new name, **Complicate**: "Suggest a way a character could do something
dangerous, destructive, or derailing. That character's player gains two
boons." That description no longer mentions a payout to the suggester — only
the copy changed here; `GameTable.ts`'s `SUGGEST_COMPEL_SUGGESTER_BOONS` (1)
and `SUGGEST_COMPEL_TARGET_BOONS` (2), and `Copy.proposalSuggestCompelOn`'s
"(+1 / +2 boons)" facilitator-queue text, still pay the suggester too — both
are unreachable from the current inert Moves card (23.4) regardless.

- [ ] When Moves are re-wired, drop `SUGGEST_COMPEL_SUGGESTER_BOONS` and pay
      only the compelled character, to match the Complicate description.

## P2.13 — Section 24 follow-ups (from code review)

Findings from a post-merge review of section 24 (two-panel layout). None block
the section as shipped; captured here as explicit cleanup.

- [ ] **Moves' "n of 4 left" over-counts.** `allAbilities`
      (`client/src/View/Moves.elm:30`) still includes `Kind.HelpOut`, but
      `worker/src/GameTable.ts:904-910` unconditionally 400s every `help-out`
      raise (23.1). `remainingSummary` (`Moves.elm:67-73`) can never actually
      reach "4 of 4" — the real ceiling is 3. Either drop `HelpOut` from the
      counted set or special-case it out of `remainingSummary` until it's
      re-wired.
- [ ] **Divider drag can stick outside the Discord iframe.** Dragging
      `Ui.dragHandle` (`Ui.elm:524`) past the Activity iframe's edge and
      releasing there means `Browser.Events.onMouseUp` (`Main.elm:280`) never
      fires, since it only sees events inside the document — `draggingDivider`
      stays `true` and further mouse movement keeps being read as a drag until
      the pointer re-enters the iframe and clicks. Needs a fallback release
      (e.g. clear `draggingDivider` on blur, or a pointer-capture-based
      approach) that doesn't depend on the mouseup landing inside the iframe.
- [ ] **Collapsed Facilitator panel hides pending proposals with no cue.**
      `proposalsPanel` (`client/src/View/FacilitatorPanel.elm:38`) only renders
      when the accordion section is open, and its header carries no count —
      unlike Moves' `accordionHeaderWith`, which shows a trailing "n of 4 left"
      for exactly this reason. A facilitator who collapses the panel gets no
      signal that a player has a proposal waiting. Give the Facilitator header
      a pending-proposal count the same way.
- [ ] **`Ui.onlyWhen` reimplemented inline in three places.** `(if props.open
      then [ ... ] else [])` in `client/src/View/Moves.elm:44`,
      `View/FacilitatorPanel.elm:38-49`, and `View/Characters.elm:778-800` each
      duplicate `Ui.onlyWhen : Bool -> List (Element msg) -> List (Element
      msg)` (`Ui.elm:83`). Replace with `Ui.onlyWhen props.open [ ... ]` at all
      three sites.
- [ ] **`View.Guide`'s header still hand-rolled.** Section 24 factored the
      title-doubles-as-toggle pattern out of `View.Guide` into
      `View.Helpers.accordionHeader` / `accordionHeaderWith`, but
      `View.Guide.header` (`Guide.elm:35-51`) never switched over to calling
      it — it still builds its own `Input.button` + marker row. Point it at
      `View.Helpers.accordionHeader` so the accordion look has one
      implementation.
- [ ] **No `Main.update` tests for section 24's five new `Msg` constructors.**
      `SelectRightPanelTab`, `ToggleLeftSection`, `DividerDragStarted`,
      `DividerDragged`, and `DividerDragEnded` (`Main.elm:295-313`) have none,
      breaking the one-test-per-toggle convention every prior toggle `Msg` in
      `client/tests/UpdateTest.elm` follows (e.g. `ToggleGuide`,
      `ToggleSessionControls`, `ToggleAspectExamples` around line 270). Add
      tests covering the drag clamp bounds and that the right section/tab
      toggles.
- [ ] **280px minimum left-panel width can starve the right panel.** 23.5's
      narrow-viewport item was marked resolved by section 24 "by retiring the
      three-column shell," but `minLeftPanelWidth = 280` (`Main.elm:219`) plus
      the drag handle and row padding can still squeeze `rightPanel` (plain
      `width fill`, no minimum) down to near-unusable widths on narrow
      Activity embeds. Revisit whether the right panel also needs a minimum,
      or whether the two-panel layout needs its own narrow-viewport fallback
      after all.

---

## Flushing test messages before the campaign

The facilitator's "Clear log" button (the `messages/clear` route) is the normal
way to wipe a log. To do it by hand instead — the Durable Object only reads
`messages` from D1 on a cold start, so the in-memory copy must be evicted too:

1. Make sure no one is connected to the table (close all Activity windows).
2. Delete the rows from the deployed database:
   ```bash
   pnpm exec wrangler d1 execute ttrpg-activity-db --remote \
     --command "DELETE FROM messages"
   ```
   To clear a single table only, add `WHERE session_id = '<tableId>'`.
3. Force the Durable Object to restart so it reloads an empty log:
   `pnpm run deploy` (a new deployment cycles DO instances), or wait several
   minutes for the idle table to hibernate and evict.

Local dev database uses the same command with `--local` instead of `--remote`.
