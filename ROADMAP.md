# Roadmap

The backend (single Worker + Durable Object + D1) is stable. Everything below is
incremental work on top of it, roughly in priority order.

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
- [x] `View.elm` — the whole view. Split into `View/Messages.elm` etc. only if
      it grows further after future UI work.
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

- [ ] Facilitator-set difficulty: let the facilitator add Bane stones to a roll
      from the fiction instead of the fixed two. Deferred — the fixed two Bane
      stay for now.
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

### Deferred

- [ ] **Self-serve claiming** — first authenticated user at a `tableId` with no
      facilitator claims it, stored per-table (new migration). Needs a hand-off
      path; obvious failure mode is a player launching first. Not needed while
      `BOOTSTRAP_FACILITATOR_ID` covers a single known facilitator.

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
      Boon + two Bane, held in the Durable Object's stone storage. Each accepted
      roll adds one of that roll's two result stones, chosen at random.
- [x] **Session roll** — `/session/end` draws two from the session pool: two
      Boon → `met`, one → `partial`, none → `failed`. Written to
      `game_sessions.outcome` and logged. (The met/partial/failed thresholds are
      a placeholder pending playtesting.)
- [ ] Trim or paginate history — the DO currently loads the last 200 messages
      and the client keeps 200. Fine for now; revisit if a campaign outgrows it.
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

## 11. Effect pattern + tests

`update` currently returns `( Model, Cmd Msg )` and calls `Api` / `Ports` /
`Browser.Dom` directly. The [Effect pattern](https://elm-radio.com/episode/single-out-effects/)
replaces the `Cmd` with a custom `Effect Msg` type that only *describes* side
effects, turning `update` into a pure function that returns data.

Worth doing, but the main payoff — a `update` that can be asserted on without
mocking `Cmd` — only lands with a test suite, so treat these as one unit of
work rather than a standalone reorganisation. Sequenced after the gameplay
sections above so the shape of `update` has settled first.

- [ ] `Effect.elm` — an `Effect msg` type with one constructor per side effect
      the app performs (`GetGameState`, `PostMessage`, `PostStones`,
      `PostCharacterUpdate`, `PostFate`, `Authorize`, `GetTimeZone`,
      `ScrollLogToBottom`, `None`, `Batch`). `Api` and `Ports` keep the "how";
      `Effect` names the "what".
- [ ] `Effect.perform : Effect Msg -> Cmd Msg`, called once at the `Main`
      boundary. `update : Msg -> Model -> ( Model, Effect Msg )`.
- [ ] Add `elm-explorations/test` and `avh4/elm-program-test`; cover the
      snapshot-merge logic in `Main.applyServerState` (keeping the sheet under
      the cursor), the empty-message send guard, and the auth → load-state
      sequence.
- [ ] Wire `pnpm run test:client` into `pnpm run build`.

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
