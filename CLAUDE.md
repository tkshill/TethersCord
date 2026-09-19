# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All scripts live in the root `package.json`; run them with pnpm from the repo root. Node 22 (`.nvmrc`), pnpm 11 (`corepack enable` selects it).

| Command | Purpose |
| --- | --- |
| `pnpm install` | Install; `pnpm-workspace.yaml` allowlists the `elm` / `esbuild` / `workerd` build scripts |
| `pnpm run dev` | Build client, then run the client watcher + `wrangler dev` on http://localhost:8787 (SPA and API on one origin) |
| `pnpm run build` | `build:client`, then `typecheck` (client + worker), then `test` — the pre-deploy gate |
| `pnpm run test` | `test:client` (`elm-test` over `client/tests/`) then `test:worker` (`vitest` via `@cloudflare/vitest-pool-workers` over `worker/test/`) |
| `pnpm run build:client` | `node client/scripts/build.mjs`: `elm make src/Main.elm --optimize` → `client/dist/elm.js`, esbuild `src/main.ts` → `client/dist/main.js`, copy `index.html`. Run after any Elm change |
| `pnpm run watch:client` | Rebuild `client/dist` in place on change (`wrangler dev` reads it off disk; there is no project dev server) |
| `pnpm run typecheck:worker` / `typecheck:client` | `tsc --noEmit`. Run the worker one after any Worker change |
| `pnpm run deploy` | `build` then `wrangler deploy` (assets + Worker, atomic). **Only when explicitly asked**; `pnpm run deploy:dry-run` to bundle without uploading |
| `pnpm run db:migrate:local` / `db:migrate:remote` | `wrangler d1 migrations apply ttrpg-activity-db` against the local dev DB / production |
| `pnpm run db:migrations:list` | Show remote migration state |

Local dev also needs `cp .dev.vars.example .dev.vars` (fill in `DISCORD_CLIENT_SECRET`) and one `pnpm run db:migrate:local`.

Quick Elm compile check without the full bundle, from `client/`: `../node_modules/elm/bin/elm make src/Main.elm --output /dev/null`.

### Tests

`pnpm run test` runs both suites (`test:client` then `test:worker`); it is folded into `pnpm run build` after `typecheck`, so `deploy` and CI (`.github/workflows/ci.yml`) run it.

**Client** (`pnpm run test:client`): `elm-test` (`elm-explorations/test` 2.2.1) over `client/tests/`, invoked with `--compiler ../node_modules/elm/bin/elm` so it uses the pinned Elm. Covers `Api.decodeGameState` against a full wire snapshot, `Main.applyServerState` (the edit-cursor merge), `Main.update` guards and the `Effect` each `Msg` yields, and the `Format` / `Roll` helpers. `Main` exposes `init` / `update` / `applyServerState` for the tests.

**Worker** (`pnpm run test:worker`): `vitest` via `@cloudflare/vitest-pool-workers`, config in `worker/vitest.config.mts` (an `.mts` file — the pool package is ESM-only). Tests run inside `workerd` with a real `GameTable` Durable Object and a migrated D1 (`worker/test/apply-migrations.ts` applies `worker/migrations/` before each file). `worker/test/helpers.ts` seeds `sessions_auth` rows and drives routes through `SELF.fetch`. Covers the `index.ts` proxy (id validation, path rewrite), the auth gates (`facilitatorOnly`, expiry), the `GameTable` proposal / Overcome / session state machine (`overcome.test.ts` drives the whole loop through the routes, shaping the pool to force a known draw), the `npcs` / `locations` CRUD routes, `withLock` serialisation, the pure rules helpers in `gameLogic.ts` / `migrateStoneState.ts` (`gameLogic.test.ts`, no `workerd` needed), `oauth-discord` (`pruneExpiredSessions`, exchange input validation), and `maintenance` (`pruneOldMessages`). The pool bundles an older `workerd`, so its `compatibilityDate` is pinned to `2026-08-22` (prod is `2026-09-01`); test files are not run through `tsc`.

`avh4/elm-program-test` is still deferred; the update tests fold `Main.update` directly for now.

### Elm version

Pinned to **0.19.1** (npm `elm@0.19.1-5`, `client/elm.json` `elm-version`). `.vscode/settings.json` points `elmLS` at `node_modules/elm/bin/elm` so the editor and CLI agree. Do not bump to the `0.19.2-0` prerelease — local editor tooling (elm-language-server / Lamdera) rejects it.

## Architecture

### One Worker, one origin

The whole app deploys as a single Cloudflare Worker described by the root `wrangler.jsonc`. `run_worker_first` is set to `/api/*`, so that is the only path that reaches Worker code; every other path is served from `client/dist` as a static asset, with `index.html` as the SPA fallback. No Pages project, no proxy hop.

`worker/src/index.ts` routes:

- `POST /api/oauth/discord/exchange` → `oauth-discord.ts`
- `/api/table/:tableId/*` → forwarded to the `GameTable` Durable Object via `env.GAME_TABLE.idFromName(tableId)`. The proxy rewrites the path and **overwrites** `?tableId=` from the URL segment, so a client-supplied table id can never make one table's DO touch another's rows. `TABLE_ID_PATTERN` bounds it.
- `scheduled` (hourly cron) → `pruneExpiredSessions` and `pruneOldMessages` (drops `messages` rows older than 30 days so the table cannot grow unbounded toward the account SQLite cap)

### Per-table state: Durable Object + D1

State is partitioned by `tableId`, one `GameTable` Durable Object per table.

- **`tableId` is `guildId-channelId`** (or just `channelId`), resolved in `client/src/main.ts`. It is deliberately **not** the Discord `instance_id`, which changes on every Activity launch and would give each session a fresh DO and blank sheets.
- **D1** (`ttrpg-activity-db`) is the durable store: `messages`, `characters`, `sessions_auth`, `facilitators`, `game_sessions`, `npcs`, `locations`. Schema is in `worker/migrations/`.
- **`GameTable`** loads `messages`, `characters`, the completed `game_sessions` history, and the `npcs` / `locations` reference rows from D1 on cold start into an in-memory `GameState`. Only the most recent `MESSAGE_WINDOW` (50) messages are held and broadcast, to keep the connect snapshot and each re-render small; older rows are fetched on demand through `GET /messages/history?before=<createdAt>` (read-only, no lock, no broadcast) and prepended client-side. The **stone pool, proposal queue, session, session aspects and used-ability flags are the only state the DO genuinely owns** — they live in DO storage (`KEY_STONES`), not D1, because they would otherwise be lost on hibernation (~10s after a table goes quiet). `saveStoneState` serialises that slice and skips the `put` when it is byte-identical to the last write, so stone-inert mutations (a chat post, for instance) do not rewrite the blob.
- Because messages are read from D1 only on DO cold start, wiping the log means deleting the rows **and** cycling the DO (see `ROADMAP.md` "Flushing test messages").

### Realtime: broadcast is the source of truth

- Mutations — `POST /message`, `/messages/clear`, `/stones/{add,remove}`, `/overcome/{roll,reroll,accept,reject}`, `/moves/{highlight,complicate,add-detail,alter,use-session-boon}`, `/session-aspects` and `/session-aspects/:id/{update,delete,use,unconsume}`, `/proposals/:id/{accept,reject,withdraw}`, `/session/{start,end,goal}`, `/characters/:slot/{update,fate,claim,release}`, `/{npcs,locations}` and `/{npcs,locations}/:id/{update,delete}` — return **`204` only**. They do not return a snapshot, on purpose: an HTTP body would race the WebSocket broadcast that already went out, and the two transports have no ordering. The `/moves/*` routes and the `claim`/`release` routes resolve the character sheet from the caller's Discord id (`characters.discord_user_id`), not a slot argument.
- **`RULES.md` is the source of truth for what the rules are** (the Overcome loop, the five moves and their costs, session boons and banes); this section only records how the Worker implements them. The client speaks this wire shape as of 26.3; the in-app glossary and copy are rewritten in 26.4.
- **One shared stone pool** (`gameState.stonePool`) backs every Overcome. It starts at the base four (`INITIAL_STONE_POOL`: two Boon, two Bane) and **returns to exactly that whenever an Overcome is accepted** — nothing carries between Overcomes, which is the point (leftover stones skewed playtest results). Between accepts it changes only through an accepted Highlight or Use Session Boon, a session aspect the facilitator uses, and the facilitator's direct `/stones/{add,remove}` (silent hand-edits; `remove` 400s if the pool holds none of that kind). A roll only ever *reads* the pool. There is no per-session pool.
- **The Overcome loop (26.2)**: `gameState.overcome` is `{ rolledBy, stones, rerolls, alteredSlots } | null`, persisted in `KEY_STONES` and broadcast. `POST /overcome/roll` is open to **any** authenticated player (no approval): it 409s if one is already pending, otherwise draws two stones (`pickTwoRandom`) without touching the pool and logs it. `/overcome/reroll` (`facilitatorOnly`, free, needs a pending roll) redraws. `/overcome/accept` (`facilitatorOnly`) resets the pool to `INITIAL_STONE_POOL`, creates a session boon (two Boons) or session bane (two Banes) from a matched pair (`pairKind`; a mixed draw creates none), clears `overcome`, withdraws any queued `alter` proposals, and logs the final result. `/overcome/reject` discards the roll and withdraws queued `alter` proposals; the pool and everything else are untouched. **"No pool changes after the roll" is a table rule — the Worker does not enforce it.**
- **Proposal model**: a player move other than Overcome is queued as a `Proposal` (`gameState.proposals`, broadcast, persisted in `KEY_STONES`): `highlight` (pays 1 boon, pool +1 Boon), `complicate` (`{ targetSlot }`; the target's player gains `COMPLICATE_TARGET_BOONS` (2), the suggester nothing), `add-detail` (`{ text? }`, pays 1 boon, creates a session boon), `alter` (Alter Fate: pays 2, rerolls the pending Overcome) and `use-session-boon` (`{ sessionAspectId }`, no cost; adds a Boon to the pool and marks it consumed). Each needs a claimed sheet. **Costs are checked at proposal time (400) and again at accept time (409, the proposal stays queued) and are paid on approval only** — a rejection costs nothing. Every move logs both its proposal (`<label> proposes <Move>`) and its resolution (`<Move> accepted — …` / `<Move> rejected — <label>`). `alter` also needs a pending Overcome, at most one `alter` proposal is pending at a time, and each character may have one *accepted* Alter per Overcome (`overcome.alteredSlots`); a rejected one does not use up the attempt. The facilitator resolves proposals with `/proposals/:id/{accept,reject}`; an `add-detail` accept may carry `{ text }` (the facilitator's edit of the player's suggestion, falling back to it, then to a default). The proposer can pull back their own pending proposal with `/proposals/:id/withdraw` (gated on `proposerId`). An accept whose target character / session aspect has since gone returns 409 and leaves the proposal queued. `GameTable` owns this; there is no D1 table for proposals.
- **Session boons and banes (26.2)**: `SessionAspect` is `{ id, kind, text, createdByName, createdAt, consumed }`. They come from an accepted Overcome pair, an accepted Add Detail (always a Boon) or the facilitator (`POST /session-aspects`, any kind). They persist until the facilitator deletes them; spending one **marks it `consumed` rather than deleting it**, and a consumed one cannot be spent again. Players spend session *boons* through `use-session-boon`; session *banes* are the facilitator's to use directly. Facilitator-only routes: `/session-aspects/:id/use` (adds the aspect's kind to the pool, marks it consumed, logs), `/unconsume` (a correction for table miscommunication — clears the mark, does not touch the pool), `/update` (`{ text }`, silent) and `/delete`. `migrateStoneState` reads pre-26.2 blobs: `consumed` defaults to `false`; `usedAbilities`, `committedBoons` and proposals of the retired kinds (`add-boon`, `gain-insight`, `accept-compel`) are dropped; legacy move names map forward.
- **Sessions do nothing special (26.2)**: `handleStartSession` records the goal, `handleEndSession` closes the history row, and neither touches the pool, proposals, session aspects or a pending Overcome. `SessionState` is just `{ id, goal }`; the goal is plain text, never judged, and can be rewritten with `POST /session/goal` (`facilitatorOnly`). `game_sessions.outcome` is not written; session history (`gameState.sessionHistory`) shows each past session's goal and dates. The message log is the persistent record of play.
- The resulting `GameState` is broadcast to every connected client over the table's WebSocket (`GET /api/table/:id/connect`, bearer token passed in `Sec-WebSocket-Protocol: bearer, <token>`).
- `GameTable` uses **hibernatable** WebSockets (`state.acceptWebSocket`). On connect it sends the current snapshot before any `await`, so a concurrent mutation's broadcast can only arrive after it.
- Every mutation runs through `withLock` — a promise chain that serializes DB write + in-memory update + broadcast. Durable Objects interleave concurrent requests at `await` points, so without this two mutations lost-update each other.
- Client side: the initial `GET /messages` seeds the board **only if** the socket snapshot has not already arrived (`GotGameState` checks `model.gameState`).

### Auth flow

1. Elm sends `Authorize` over the `toDiscord` port.
2. `client/src/DiscordBridge.ts` runs `discordSdk.commands.authorize` → auth code → `POST /api/oauth/discord/exchange`.
3. `worker/src/oauth-discord.ts` exchanges the code with Discord (no `redirect_uri` — Embedded App SDK codes are not issued against one), fetches `users/@me`, mints a random-UUID `sessionToken` into `sessions_auth` with an expiry, and returns `BackendAuthResult` (`sessionToken`, `accessToken`, `role`, …).
4. Bridge calls `discordSdk.commands.authenticate({ access_token })` to finish the Activity handshake, opens the game socket, and sends `BackendAuthResult` back over `fromDiscord`.
5. **Role**: `facilitator` if the Discord user id matches the `BOOTSTRAP_FACILITATOR_ID` var **or** is in the `facilitators` table, else `player` (`inferRole` in `oauth-discord.ts`, mirrored in `GameTable.getAuthFromToken`). Set `BOOTSTRAP_FACILITATOR_ID` in `wrangler.jsonc` (or `.dev.vars`) for a single known facilitator; seed the table for more.
6. Every `/api/table/*` route requires `Authorization: Bearer <sessionToken>` and checks `expires_at`. Facilitator-only routes (`stones/{add,remove}`, `overcome/{reroll,accept,reject}`, `session-aspects` and `session-aspects/:id/{update,delete,use,unconsume}`, `characters/:slot/fate`, `messages/clear`, `proposals/:id/{accept,reject}`, `session/{start,end,goal}`, `{npcs,locations}` and `{npcs,locations}/:id/{update,delete}`) additionally go through the `facilitatorOnly` gate (403 otherwise). `proposals/:id/withdraw` is gated on the proposer, not the facilitator.

### Client module layout (Elm + TS interop)

Elm (`client/src/`), dependency direction `Types` ← everything, `Main` → `Effect`/`Api`/`Ports`/`View`/`Format`, `View` → `View/*` → `View/Helpers` → `Ui`:

- **`Main.elm`** — wiring only: `init` / `update` / `subscriptions` / `main`. `update : Msg -> Model -> ( Model, Effect )` is pure — it returns an `Effect` value, never a `Cmd` — and `main` runs `Effect.perform` on the result at the boundary.
- **`Effect.elm`** — an `Effect` type with one constructor per side effect the app performs (`GetGameState`, `PostMessage`, `PostOvercomeRoll`, `PostHighlight`, `ScrollLogToBottom`, `Authorize`, `Batch`, `None`, …), and `Effect.perform : Flags -> Effect -> Cmd Msg` translating each to an `Api` / `Ports` / `Task` call. `Post*` effects carry the `Auth` they need; `update` still decides whether the user is authorised. This is what lets `update` be asserted on in tests without mocking `Cmd`.
- **`Types.elm`** — domain types **plus `Model` and `Msg`**. They live here, not in `Main`, so `View` can import them without a cycle (`Main` imports `View`).
- **`Api.elm`** — every backend call and the JSON decoders. Endpoints are one line each over three private request helpers (`get` / `postEmpty` / `postJson`); commands take their result-message constructor as an argument, so this module has no dependency on `Types.Msg`.
- **`Ports.elm`** (`port module`) — the `toDiscord` / `fromDiscord` / `wsGameState` ports, `authorize`, and a typed `DiscordInbound` + `decodeInbound`. Ports declared here still surface on `app.ports`; the JS side does not care which module declares them.
- **`Kind.elm`** — the `ProposalKind` custom type (`Highlight | Complicate | AddDetail | Alter | UseSessionBoon`, with its decoder and string encoder) at parity with the Worker's `types.ts` union. Its own module because several constructor names also name `Msg` variants.
- **`Action.elm`** — the mutations the UI guards against a double-click, as a type (`Action`) with a `Family` per group of results. `Model.inflight` is a `List Action`; `Main.guard` refuses an action already in flight, `MutationDone` clears a whole `Family`, and `Ui.press` greys a control whose action is pending. `inflight` rides on `ViewContext`. Its own module because `Effect` imports `View`.
- **`View.elm`** — the page shell only (roadmap 27, mockup 2a): `view` computes a `ViewContext` once, then composes a one-line status strip (`View.TopBar`) over two panels — a **tool panel** on the left (a row of glyph tabs, `◆ Sheet` / `⚑ Facilitator` (facilitator only) / `▲ Moves` (players only) / `☺ Cast` / `◇ Context` / `? Guide`, showing one tool at a time via `Model.toolTab`; the facilitator's oldest waiting proposal sits in a strip under any tool but their own) and the event log with the composer pinned beneath it on the right. `Model.leftPanelWidth` (default 320) is draggable through `Ui.dragHandle`. Also `connectionNote`, `composer`, `logDomId`.
- **`View/*.elm`** — one module per tool: `TopBar` (the status strip: the running goal — click it as facilitator to open the session start/end/goal controls — the pool as `+` / `−` marks, the pending Overcome draw in a ringed chip, **Overcome** for any player or the facilitator's Reroll / Reject / Accept, and who you are), `FacilitatorPanel` (direct pool edits and the proposal queue; `strip` is the one-line oldest-proposal Accept / Reject), `Characters` (the Sheet: slot tabs and hairline label/value fields, boons as `+` marks, aspect Banes as `−` marks), `Moves` (real buttons for the five player moves, each disabled when unaffordable), `Entities` (the Cast tab: NPCs and locations), `SessionAspects` + `Session` (the Context tab: session boons and banes as `+` / `−` rows, then past sessions), `Guide` (the `?` tab, `Copy.Terms` always expanded) and `Log`. Each exposes `view : ViewContext -> <props record> -> GameState -> Element Msg` (a couple take no extra props; `Guide` takes nothing). `View/Helpers.elm` holds the `ViewContext` type (including `username`) and the cross-section helpers (`placeholder`, `inputAttrs` / `inlineInputAttrs`, `characterLabel`, `countProposals` / `latestProposalId`, `pendingHint` / `withdrawLink`, and the glossary-tooltip helpers `glossaryTitle` / `tip` / `tipAttrs` over `Ui.withTip` — `tip`/`withTip` shrink-wrap, so a full-width element takes `tipAttrs` directly instead, to leave its width alone).
- **`Ui.elm`** — the elm-ui design system: palette, `xs`…`xl` spacing scale, type sizes, and building blocks (`page`, `flat`, `toolTab`, `tab`, `primaryButton`, `ghostButton`, `linkButton`, `boonMarks` / `baneMarks`, `oneLine`, `onEnter`, …), plus the `press` (in-flight gate) and `onlyWhen` list helpers. New UI goes through these, not raw `Element` styling. Aesthetic is deliberately spare and dense: no cards, just hairlines between regions, 11–13px type. `page` is a fixed-height shell (`{ top, columns }`, edge to edge); `scrollArea` is a tool's independently-scrolling body. It relies on `shrinkable` (`min-height: 0`) — CSS flex items default to `min-height: auto`, which refuses to shrink a flex-grow item below its content's natural size, so without it a panel (or a scrolling region nested inside one, like the Log's message list) just grows to fit its content instead of clipping and scrolling; `client/index.html` carries the matching `html, body, #root { height: 100% }` a `height fill` chain needs to reach a viewport to fill against — `#root` included, since a bare `<div>` does not inherit a percentage height from its parent. `oneLine` is a nowrap-ellipsis text slot (a wrapping `paragraph` ignores `text-overflow`).
- **`Copy.elm`** / **`Copy/Terms.elm`** — `Copy.elm` is every player-facing string the view renders, as named constants grouped by card (small formatting functions where a value is spliced in), plus `aspectExamples : Aspect -> List String` (a curated subset of the repo-root `ASPECTS.md`, shown under "see examples" on each aspect field); structural labels that are not game vocabulary ("Name", "Notes") stay inline. `Copy/Terms.elm` is the glossary: `Term = { term, short, long }` and `terms` / `groupedTerms`, the `short` feeding the `title` tooltips and the `long` the `View.Guide` card.
- **`Format.elm`** / **`Roll.elm`** — pure helpers; stone type.

TypeScript (`client/src/`):

- **`main.ts`** — boots the Discord SDK, resolves `tableId`, `Elm.Main.init`, then wires the bridge and socket.
- **`DiscordBridge.ts`** — the Authorize flow and OAuth exchange. Imports `BackendAuthResult` from `worker/src/types.ts`, so the auth payload shape is shared across the client/worker boundary.
- **`GameSocket.ts`** — the reconnecting WebSocket feeding the `wsGameState` port. Gives up on close code `1008` (credentials rejected); exponential backoff otherwise.
- **`ports.ts`** — the one description of the Elm `app.ports` surface (`ElmPorts`, plus a `SocketPorts` pick for `GameSocket`), and the `Window.DISCORD_CLIENT_ID` / `Window.BACKEND_BASE_URL` global declarations. Imported by the three files above instead of each hand-copying the shape.

`client/scripts/build.mjs` calls `node_modules/elm/bin/elm` directly rather than the `.bin` shim, which breaks under pnpm.

## Conventions

- **Migrations are append-only.** Never edit a migration that may have been applied — add `worker/migrations/000N_name.sql`.
- **Do not edit `client/elm-stuff/`** (generated).
- Keep client and worker responsibilities separate. Keep ports narrow and typed.
- Worker code: explicit request validation and authorization at every route.
- After a change, run the narrowest check: `pnpm run build:client` after Elm, `pnpm run typecheck:worker` after Worker.
- `RULES.md` is the canonical, current statement of the game rules. Any change to a game rule updates it in the same branch, and `client/src/Copy/Terms.elm` (the in-app glossary) follows it.
- `ROADMAP.md` is forward-looking; `CHANGELOG.md` is the record of what shipped — add a bullet to its `[Unreleased]` section for any notable change.
