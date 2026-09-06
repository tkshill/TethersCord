# Roadmap

The backend (single Worker + Durable Object + D1) is stable. Everything below is
incremental work on top of it, roughly in priority order.

`DESIGN_PRINCIPLES.md` holds the ten core design principles every item here is
weighed against.

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
      stay for now. **Superseded by section 19:** difficulty escalates on its own
      through the session pool carrying Banes between sessions, so no
      facilitator-set axis is planned.
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
      a placeholder pending playtesting.) **Section 19 revises this:** the tiers
      go away, success is a Boons-vs-Banes comparison of the whole pool, and the
      pool's Banes carry between sessions until a failure flushes them.
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

## 12. Correctness, session lifecycle, and UX cleanup

Promoted ahead of the efficiency work. The findings from the September structure
audit, plus a firmer set of rules for the session lifecycle.

### Session lifecycle

- [ ] **Starting and ending a session are facilitator-only.** Already enforced —
      `facilitatorOnly` guards `/session/start` and `/session/end`, and the
      buttons render only for the facilitator in `View`. Recorded here as an
      invariant to preserve as the surrounding code changes.
- [ ] **Ending a session clears every unresolved pending state.**
      `handleEndSession` already drops `floatingBoons` and `usedAbilities`; it
      must also clear `overcome`, `pendingRoll`, `committedBoons`, and any
      `proposals` that were never accepted or rejected — an overcome roll or a
      move proposal left open when the session ends is discarded, and unspent
      floating boons disappear. Nothing from a closed session carries into the
      next one. (`handleStartSession` should clear `committedBoons` and
      `proposals` as well, belt and braces.)
- [ ] **The facilitator can edit the session goal at any time.** A new
      facilitator-only `POST /session/goal` (`{ goal }`) updates the running
      `game_sessions` row and `gameState.session.goal` and broadcasts. It
      rewrites live shared state, so the control sits behind the confirmation
      step below.
- [ ] **Confirm destructive facilitator actions.** End session, Clear log, and
      edit-goal each go behind a confirm step.

### Audit fixes

- [ ] **Clean up a slot's pledges and proposals on claim / release.**
      `handleClaimSlot` / `handleReleaseSlot` leave `committedBoons` and in-flight
      proposals pointing at a slot the caller no longer owns; an accepted roll
      then spends the wrong character's boons.
- [ ] **Let a proposer withdraw their own proposal.** `POST
      /proposals/:id/withdraw`, gated on `proposerId`, with a control beside the
      "(pending)" hint. Today a mis-aimed Suggest Compel can only be undone by
      the facilitator rejecting it.
- [ ] **Guard `/stones/accept` on a `pendingRoll`.** Reject with 400 rather than
      silently resetting the pool and clearing the proposal queue.
- [ ] **Surface silently-dropped accepts.** When an accepted proposal's target
      no longer exists, return an error and keep the proposal, rather than
      removing it with no effect and no log line.
- [ ] **Per-row context note.** The Add a Detail / Gain Insight note input is
      bound to one shared `proposalDraft`; give each queued proposal its own.
- [ ] **Status banner.** Separate transient errors from steady state, and
      auto-dismiss the errors.

## 13. Table entities beyond characters — NPCs and locations

The facilitator needs to record the cast and the map alongside the three player
sheets. Both are facilitator-owned reference data: broadcast to the whole table,
read-only for players.

- [ ] **`npcs` and `locations` D1 tables** (append-only migration `0008`),
      scoped by `session_id` like `characters`: `id`, `session_id`, `name`,
      `notes`, `created_at`, `updated_at`. Keep the first cut to name + notes;
      an NPC `location_id`, a status field, and location nesting can come later.
- [ ] **Facilitator-only routes** — `POST /npcs` (create), `POST
      /npcs/:id/update`, `POST /npcs/:id/delete`, and the same three for
      locations, all through `facilitatorOnly`.
- [ ] **`GameState.npcs` / `GameState.locations`**, loaded on Durable Object
      cold start and broadcast with the rest of the state (their own patch kinds
      once section 15's delta broadcasts land).
- [ ] **Client** — an "NPCs" card and a "Locations" card: an editable list for
      the facilitator, a plain read-only list for players, reusing the
      character-sheet field styling.

## 14. Fewer requests per action — the Cloudflare Free budget

The Free plan is 100,000 requests/day and 10 ms CPU per request, shared across
the Worker and its Durable Object. Every table mutation currently costs at least
two counted requests — the Worker entry point and the `stub.fetch` subrequest
into the `GameTable` object — and a cold launch costs more again (the OAuth
exchange, `getGameState`, the socket upgrade, and up to three `getGameState`
retries). WebSocket broadcasts are outbound and do **not** count, so the lever
is the number of inbound HTTP calls, not the fan-out. Ordered by value over
effort.

- [ ] **Drop the HTTP state seed on the happy path.** `handleConnect` already
      sends a full `GameState` before its first `await`, and `GotGameState (Ok
      _)` is a no-op whenever that snapshot beat it — which is nearly always.
      Fire `getGameState` only as a fallback, after ~3 s with no snapshot, and
      delete the 3×/2 s retry loop. Saves one to four requests per launch.
- [ ] **One character save per sheet, not per field.** `CharacterFieldBlur`
      POSTs `/characters/:slot/update` on every field's blur, so editing a whole
      sheet is seven requests. Debounce to a single write ~1 s after the last
      edit (flushing on tab-away and unload), sending the full sheet.
- [ ] **De-duplicate in-flight mutations.** Track pending action keys in the
      model, or disable the control until its `…Updated` message lands, so an
      impatient double-click cannot fire the same POST twice. This also closes
      the double-roll and double-proposal correctness holes from the audit.
- [ ] **Cache the auth lookup in the Durable Object.** `getAuthFromToken` runs a
      `sessions_auth` ⋈ `facilitators` query on every `/api/table/*` call.
      Memoise token → `AuthInfo` in DO memory with a ~60 s TTL: one D1 read per
      token per minute instead of per request.
- [ ] **Coalesce Highlight churn.** The pledge `+` / `−` each raise their own
      proposal. Debounce to the net delta and disable the control while one is
      queued.
- [ ] **Reuse a still-valid `sessionToken` across reloads.** Persist it in
      `localStorage`; on reload, skip `/api/oauth/discord/exchange` while
      `expires_at` is still in the future. Lower value — Activities usually
      launch fresh rather than reload — but one request saved when they don't.

## 15. Zippier realtime updates

Perceived latency on a shared action is click → POST → 204 → DO broadcast →
socket → decode → re-render. The two network hops are inherent to the
facilitator-broadcast model; the payload size and the render cost are not.

- [ ] **Delta broadcasts.** Replace the whole-`GameState` push on every mutation
      with a tagged patch — `{ t: "message", message }`, `{ t: "stones", … }`,
      `{ t: "proposals", proposals }`, and so on — that the client folds into its
      local state. Keep `{ t: "snapshot", state }` for connect and an explicit
      resync. Shrinks a chat line from a 200-message blob to a single row and
      cuts the client-side decode.
- [ ] **`Element.Lazy` the message log.** `speakerColors` and `logRows` refold
      the entire list on every render, so an unrelated stone roll re-lays 200
      rows. Wrap the log column in `Element.Lazy.lazy` keyed on `messages`.
- [ ] **Instant local affordances.** No optimistic apply of shared effects, but
      the button that raises a proposal or move should flip to its "(pending)"
      state on click rather than after the round-trip.
- [ ] **Hold and send fewer messages.** Load and broadcast the last ~50
      messages, not 200; older history moves behind a "load more" HTTP fetch.
      Smaller connect snapshot, smaller re-renders. Supersedes the deferred
      pagination note in section 7.

## 16. Storage and write economy

Storage is nowhere near a limit today (~25 kB against a 5 GB account-wide SQLite
cap on Free), so this is low priority — revisit only if the Durable Object
metrics move.

- [ ] **Write `KEY_STONES` only when stone state actually changed.** A chat post
      calls `saveStoneState` even though it touches nothing there. Gate the
      write on a real stone / proposal / session / overcome change.
- [ ] **Prune `messages` on the existing hourly cron.** Add a `DELETE FROM
      messages WHERE created_at < ?` (keep ~30 days, or the last N per table) so
      the table cannot grow unbounded toward the account cap.
- [ ] **Optionally split `KEY_STONES`** into `stones` / `proposals` / `session`
      / `overcome` keys so adding a proposal does not rewrite the whole blob.
      Only worth it if write volume shows up in metrics.

## 17. Campaigns — multiple games per facilitator (not scheduled)

Today `tableId` (`guildId-channelId`) is the unit of persistence: one Durable
Object per channel owns one set of characters, one message log, one session
history. A **campaign** would become the real container — a named game a
facilitator creates and manages, owning its characters, NPCs, locations, session
history, and log — and the facilitator would pick which campaign is active for
the channel at Activity start.

This is a large reshaping and is **not scheduled**. It touches the Durable
Object's binding model (the object is keyed by `tableId` and eagerly loads
everything for it), needs a `campaigns` table and an active-campaign pointer per
table, a campaign-selection screen, and a migration path for existing
single-campaign tables.

- [ ] Design the data model and the DO-binding change before committing to it.

## 18. AI session summary (exploratory)

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

## 19. The overcome aftermath — aspects, conditions, and the tether

**Converging.** The shape below is stable enough to build against; the checked
items near the end are the parts to settle in playtest. This is the rules layer
that turns individual overcome outcomes into a character's long arc, keeping what
makes Burning Wheel, Pendragon and Archive of the Sky work inside a rules-lite
core.

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
- Session-goal success is the Boons-vs-Banes comparison in the pool at session
  end — no threshold, and the met / partial / failed tiers are retired.
- Because Banes carry and Boons do not, **session goals escalate in difficulty
  until a failure.** A failure flushes the pool completely back to the base four.
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

### To confirm in playtest

- [ ] Cadence. At base rates a failure lands roughly every ~3 sessions and each
      character reckons every ~6–9; Highlights lengthen the cycle, hoarding
      Boons shortens it. Check this feels right at the table.
- [ ] Whether compels need a per-session cap after all.
- [ ] The exact frenzy lockout — broken-aspect-only, or broader.
- [ ] Whether the facilitator may call a foregone-failure session early — once
      the carried Bane debt exceeds a session's realistic Boon ceiling — and cut
      straight to the untether scene.

### What this supersedes

- Section 4's deferred "facilitator-set difficulty from the fiction" — difficulty
  now escalates on its own through the carried pool, so the facilitator needs no
  floating-bane axis.
- Section 7's placeholder met / partial / failed session thresholds.
- The earlier section 19 sketch (leftover stone to the target, Boons tagged to
  aspects, facilitator-held floating banes, compels removing banes).

## 20. Character growth on the sheet

Largely absorbed into section 19: growth **is** the untether resolution — the
forced rewrite or replacement of an aspect after a reckoning — with the
`condition` line as the visible running record of strain between reckonings. A
rewrite changes what an aspect *means*; it never adds a rating (principle 5,
"grow in depth, not strength").

- [ ] Pin down what a rewrite may do: reword the aspect only, swap an ability
      tied to it, or retire the character outright.
- [ ] Decide whether anything persists across a reckoning besides the rewritten
      aspect — all Banes clear, but does the character keep any marker of what
      they went through?

## 21. Game text, tooltips, and glossary

The player-facing copy — move names, proposal descriptions, card titles, hint
lines — is scattered through `View.elm` as string literals, so tuning the game's
wording means editing the view. A game this much in flux needs its text easy to
revise.

- [ ] **Pull user-facing copy into one editable source.** A `Copy.elm` module of
      named string constants, or a `copy.json` compiled into the bundle, that
      `View` reads from — one place to rewrite a move's description.
- [ ] **Player tooltips.** A hover / tap affordance on move and stone terms
      showing the short rules text for that term. Deferred until the copy source
      exists.
- [ ] **A glossary.** A panel (or a section of the copy source) defining the
      game's terms — overcome, boon, bane, aspect, compel, highlight, floating
      boon — in one place for players. Deferred alongside tooltips.

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
