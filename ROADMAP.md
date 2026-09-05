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
      from the fiction instead of the fixed two (waits on section 5's role-gated
      interface).
- [ ] Bind a character sheet to a Discord user so "pledge my boons" needs no
      slot picker.
- [ ] Decide where boons are earned — right now anyone can bump the count with
      the sheet's +/- buttons.

## 5. Facilitator identity and a role-gated interface

Role is decided at auth time: `facilitator` if the Discord user id is in the
`facilitators` table, otherwise `player` (`inferRoleFromDb` in
`oauth-discord.ts`, mirrored in `GameTable.ts`). That table is
`(discord_user_id, created_at)` and is seeded by inserting rows by hand. Every
client currently renders the same `View`.

- [ ] **For the first campaign, use the existing allowlist.** Insert the
      facilitator's Discord user id into `facilitators` and leave it there — it
      already survives re-launches, is table-independent, and the facilitator is
      a known single person. Nothing new is needed to get unblocked.
- [ ] **Self-serve claiming is the eventual replacement**, for running games
      without hand-seeding rows: the first authenticated user at a given
      `tableId` with no facilitator yet claims it, stored as a
      `facilitator_user_id` on a per-table row (new migration). Needs a
      hand-off/reassign path and has an obvious failure mode (a player launching
      before the facilitator). Defer until it is actually needed.
- [ ] **Split the interface by role.** `Role` is already on `Auth`, so `View`
      can branch on `model.auth`. Facilitator-only controls likely include: the
      `messages/clear` route (section 6), stone / roll administration, granting
      positive stones to players (section 4), and session start/end markers
      (section 7). Players get a reduced view without those.
- [ ] The Worker must **enforce** the role on those routes, not just hide the
      buttons. Several stone routes (`handleAddBoon`, `handleCommitBoon`,
      `handleAcceptRoll`) currently take no auth info at all, and `handleRoll`
      ignores the `authInfo` it is given.

## 6. Message log hygiene

- [ ] Facilitator-only `POST /api/table/:id/messages/clear` route in the Worker
      that deletes the session's rows from D1 **and** resets the Durable
      Object's in-memory `gameState.messages`, then broadcasts. This is the
      supported way to wipe a log; see "Flushing test messages" below for the
      one-off manual path.
- [ ] Visually separate system/log lines (rolls) from player chat. Consider a
      `kind` column on `messages` (`chat` | `system`) so the client does not
      have to pattern-match on content.
- [ ] Day dividers in the log now that timestamps carry the date and a table
      spans multiple real-world days.

## 7. Session / campaign structure

A **session** is one game day with a goal the players work toward, and it carries
its own stone pool that fills up from the rolls made during it. This needs
first-class model support, not just log markers.

- [ ] **Session goal.** Every session records what the players are trying to
      accomplish. Set by the facilitator at the start (section 5) and shown to
      the whole table for the session's duration. Likely a `sessions` table row
      (`id`, `session_id`, `goal`, `started_at`, `ended_at`, `outcome`) rather
      than another column on `characters`.
- [ ] **Start / end session** actions the facilitator triggers, replacing the
      log-marker idea. Starting opens a goal and a fresh session pool; ending
      runs the session roll below. The log gets a system line for each.
- [ ] **Session stone pool.** Separate from the per-roll bag in section 4. It
      starts at two Boon + two Bane and persists for the life of the session
      (Durable Object storage, like the per-roll pool). After each *accepted*
      roll in the session, one of that roll's two result stones — chosen at
      random — is added to the session pool, so the pool drifts toward however
      the session has been going.
- [ ] **Session roll.** At end of session the facilitator rolls against the
      session pool to decide whether the players met the goal. Resolved the same
      way as a normal roll (draw from the bag); the result and the goal outcome
      are written to the `sessions` row and logged as a distinct system line.
- [ ] Trim or paginate history — the DO currently loads the last 200 messages
      and the client keeps 200. Fine for now; revisit if a campaign outgrows it.

## 8. Connection polish

- [ ] Surface WebSocket disconnect/reconnect state in the UI.
- [ ] Retry `getGameState` on transient failure instead of parking on
      "Failed to load game state."

## 9. Effect pattern + tests

`update` currently returns `( Model, Cmd Msg )` and calls `Api` / `Ports` /
`Browser.Dom` directly. The [Effect pattern](https://elm-radio.com/episode/single-out-effects/)
replaces the `Cmd` with a custom `Effect Msg` type that only *describes* side
effects, turning `update` into a pure function that returns data.

Worth doing, but the main payoff — a `update` that can be asserted on without
mocking `Cmd` — only lands with a test suite, so treat these as one unit of
work rather than a standalone reorganisation.

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

## 10. Character sheet layout and stone visualisation

The three sheets in a `wrappedRow` and the roll panel's text-and-number
summaries are getting dense. This pass is about seeing the current roll at a
glance.

- [ ] **Tabbed character sheets.** Show one sheet at a time behind a tab strip
      (or selector) so each field has room, instead of three cramped columns
      that collapse to a stack when narrow.
- [ ] **Boons at the top of the sheet.** Move the "Boons" and "Pledged" rows
      above the text fields, so a player sees their spendable stones in the
      context of the current roll.
- [ ] **Render a player's boons as circles**, not a bare count with `+` / `−`,
      reusing the `Ui.stoneChip` shape.
- [ ] **Mark the pledged ones.** Show which of a player's boon circles are
      pledged into the current roll with a visual change to those circles — a
      fill texture, an extra ring, or a centre mark — rather than the separate
      "Pledged" number.
- [ ] **Pledged boons as shapes in the pool.** In the roll panel, draw pledged
      boons as extra stone shapes in the bag rather than the
      "(N boon pledged)" caption.

---

## Flushing test messages before the campaign

Until the `messages/clear` route exists, wipe the log manually. The Durable
Object only reads `messages` from D1 on a cold start, so the in-memory copy must
be evicted too.

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
