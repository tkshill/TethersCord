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

**Worker** (`pnpm run test:worker`): `vitest` via `@cloudflare/vitest-pool-workers`, config in `worker/vitest.config.mts` (an `.mts` file — the pool package is ESM-only). Tests run inside `workerd` with a real `GameTable` Durable Object and a migrated D1 (`worker/test/apply-migrations.ts` applies `worker/migrations/` before each file). `worker/test/helpers.ts` seeds `sessions_auth` rows and drives routes through `SELF.fetch`. Covers the `index.ts` proxy (id validation, path rewrite), the auth gates (`facilitatorOnly`, `rollGate`, expiry), the `GameTable` proposal / session / ability state machine, the `npcs` / `locations` CRUD routes, `withLock` serialisation, and `oauth-discord` (`pruneExpiredSessions`, exchange input validation). The pool bundles an older `workerd`, so its `compatibilityDate` is pinned to `2026-08-22` (prod is `2026-09-01`); test files are not run through `tsc`.

`avh4/elm-program-test` is still deferred; the update tests fold `Main.update` directly for now.

### Elm version

Pinned to **0.19.1** (npm `elm@0.19.1-5`, `client/elm.json` `elm-version`). `.vscode/settings.json` points `elmLS` at `node_modules/elm/bin/elm` so the editor and CLI agree. Do not bump to the `0.19.2-0` prerelease — local editor tooling (elm-language-server / Lamdera) rejects it.

## Architecture

### One Worker, one origin

The whole app deploys as a single Cloudflare Worker described by the root `wrangler.jsonc`. `run_worker_first` is set to `/api/*`, so that is the only path that reaches Worker code; every other path is served from `client/dist` as a static asset, with `index.html` as the SPA fallback. No Pages project, no proxy hop.

`worker/src/index.ts` routes:

- `POST /api/oauth/discord/exchange` → `oauth-discord.ts`
- `/api/table/:tableId/*` → forwarded to the `GameTable` Durable Object via `env.GAME_TABLE.idFromName(tableId)`. The proxy rewrites the path and **overwrites** `?tableId=` from the URL segment, so a client-supplied table id can never make one table's DO touch another's rows. `TABLE_ID_PATTERN` bounds it.
- `scheduled` (hourly cron) → `pruneExpiredSessions`

### Per-table state: Durable Object + D1

State is partitioned by `tableId`, one `GameTable` Durable Object per table.

- **`tableId` is `guildId-channelId`** (or just `channelId`), resolved in `client/src/main.ts`. It is deliberately **not** the Discord `instance_id`, which changes on every Activity launch and would give each session a fresh DO and blank sheets.
- **D1** (`ttrpg-activity-db`) is the durable store: `messages`, `characters`, `sessions_auth`, `facilitators`, `game_sessions`, `npcs`, `locations`. Schema is in `worker/migrations/`.
- **`GameTable`** loads `messages`, `characters`, the completed `game_sessions` history, and the `npcs` / `locations` reference rows from D1 on cold start into an in-memory `GameState`. The **stone pool, pending roll, proposal queue, session pool, overcome, floating boons and used-ability flags are the only state the DO genuinely owns** — they live in DO storage (`KEY_STONES`), not D1, because they would otherwise be lost on hibernation (~10s after a table goes quiet).
- Because messages are read from D1 only on DO cold start, wiping the log means deleting the rows **and** cycling the DO (see `ROADMAP.md` "Flushing test messages").

### Realtime: broadcast is the source of truth

- Mutations — `POST /message`, `/messages/clear`, `/stones/{add-boon,commit,roll,reroll,accept,use-floating}`, `/overcome/{start,cancel}`, `/abilities/use`, `/moves/accept-compel`, `/proposals/:id/{accept,reject,withdraw}`, `/session/{start,end,goal}`, `/characters/:slot/{update,fate,claim,release}`, `/{npcs,locations}` and `/{npcs,locations}/:id/{update,delete}` — return **`204` only**. They do not return a snapshot, on purpose: an HTTP body would race the WebSocket broadcast that already went out, and the two transports have no ordering. `/stones/commit`, `/abilities/use`, `/moves/accept-compel`, `/stones/use-floating` and the `claim`/`release` routes resolve the character sheet from the caller's Discord id (`characters.discord_user_id`), not a slot argument.
- **The overcome**: `gameState.overcome` (`{ targetSlot } | null`, in `KEY_STONES` storage) is a facilitator-framed risky attempt against one character. `/overcome/start` (`{ slot }`) and `/overcome/cancel` are facilitator-only; while an overcome is open, `/stones/roll` and `/stones/reroll` are also allowed to the player who owns the target sheet (`rollGate`, not `facilitatorOnly`), and a Reroll deducts `REROLL_COST` (2) boons from the target's `fate` (the "Press Fate" move). Accepting the roll clears the overcome.
- **Proposal model**: player-side changes to shared state are queued, not applied. A `Proposal` (`gameState.proposals`, broadcast, persisted in `KEY_STONES`) is appended by `POST /stones/add-boon`, `/stones/commit` (pledge / Highlight an Aspect; `delta` is a non-zero integer — the client coalesces a run of +/- taps into one net-delta proposal, and `applyPledge` clamps it to `[0, fate]` on accept), `/abilities/use` (`{ kind }` — `help-out` / `add-detail` / `gain-insight` / `suggest-compel`, plus `{ targetSlot }` for `suggest-compel`; once per session, session required), `/moves/accept-compel`, and `/stones/use-floating` (`{ floatingId }`). The facilitator resolves each with `/proposals/:id/{accept,reject}`; an `accept` of `add-detail` / `gain-insight` carries `{ text }`, the context note stored on the resulting floating boon. The proposer can pull back their own still-pending proposal with `/proposals/:id/withdraw` (gated on `proposerId`, not `facilitatorOnly`). An accept whose target character / floating boon has since gone returns 409 and leaves the proposal queued. The facilitator's own `add-boon` / roll / fate actions still apply directly. `GameTable` owns this; there is no D1 table for proposals.
- **Session start / end clear pending state**: both `handleStartSession` and `handleEndSession` reset `overcome`, `pendingRoll`, `committedBoons`, `proposals`, `floatingBoons`, and `usedAbilities` — nothing left unresolved carries between sessions. The facilitator can rewrite the running goal with `POST /session/goal` (`{ goal }`, `facilitatorOnly`).
- **Abilities and floating boons**: `gameState.usedAbilities` (`{ slot, kinds }[]`) tracks the once-per-session abilities, marked used only when the facilitator accepts, and cleared on session start / end. An accepted Add a Detail / Gain Insight creates a `FloatingBoon` (`{ id, text, createdByName }`) in `gameState.floatingBoons` — a boon owned by nobody; a player spends one with `/stones/use-floating` (a facilitator-approved Highlight that removes it and adds a Boon to the bag). Unspent floating boons are discarded when the session ends. Accept Compel pays the proposer `ACCEPT_COMPEL_BOONS` (2) `fate` on approval; an accepted Suggest Compel pays the suggester `SUGGEST_COMPEL_SUGGESTER_BOONS` (1) and the compelled character `SUGGEST_COMPEL_TARGET_BOONS` (2). The compelee's consent is handled at the table, not modelled.
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
6. Every `/api/table/*` route requires `Authorization: Bearer <sessionToken>` and checks `expires_at`. Facilitator-only routes (`stones/accept`, `overcome/{start,cancel}`, `characters/:slot/fate`, `messages/clear`, `proposals/:id/{accept,reject}`, `session/{start,end,goal}`, `{npcs,locations}` and `{npcs,locations}/:id/{update,delete}`) additionally go through the `facilitatorOnly` gate (403 otherwise). `stones/{roll,reroll}` use `rollGate` instead — facilitator always, plus the overcome target while an overcome is open. `proposals/:id/withdraw` is gated on the proposer, not the facilitator.

### Client module layout (Elm + TS interop)

Elm (`client/src/`), dependency direction `Types` ← everything, `Main` → `Effect`/`Api`/`Ports`/`View`/`Format`:

- **`Main.elm`** — wiring only: `init` / `update` / `subscriptions` / `main`. `update : Msg -> Model -> ( Model, Effect )` is pure — it returns an `Effect` value, never a `Cmd` — and `main` runs `Effect.perform` on the result at the boundary.
- **`Effect.elm`** — an `Effect` type with one constructor per side effect the app performs (`GetGameState`, `PostMessage`, `PostStones`, `ScrollLogToBottom`, `Authorize`, `Batch`, `None`, …), and `Effect.perform : Flags -> Effect -> Cmd Msg` translating each to an `Api` / `Ports` / `Task` call. `Post*` effects carry the `Auth` they need; `update` still decides whether the user is authorised. This is what lets `update` be asserted on in tests without mocking `Cmd`.
- **`Types.elm`** — domain types **plus `Model` and `Msg`**. They live here, not in `Main`, so `View` can import them without a cycle (`Main` imports `View`).
- **`Api.elm`** — every `Http.request` command and the JSON decoders. Commands take their result-message constructor as an argument, so this module has no dependency on `Types.Msg`.
- **`Ports.elm`** (`port module`) — the `toDiscord` / `fromDiscord` / `wsGameState` ports, `authorize`, and a typed `DiscordInbound` + `decodeInbound`. Ports declared here still surface on `app.ports`; the JS side does not care which module declares them.
- **`View.elm`** — the whole view, built with elm-ui.
- **`Ui.elm`** — the elm-ui design system: palette, `xs`…`xl` spacing scale, type sizes, and building blocks (`page`, `card`, `primaryButton`, `stoneChip`, `banner`, `onEnter`, …). New UI goes through these, not raw `Element` styling. Aesthetic is deliberately spare.
- **`Format.elm`** / **`Roll.elm`** — pure helpers; stone type.

TypeScript (`client/src/`):

- **`main.ts`** — boots the Discord SDK, resolves `tableId`, `Elm.Main.init`, then wires the bridge and socket.
- **`DiscordBridge.ts`** — the Authorize flow and OAuth exchange. Imports `BackendAuthResult` from `worker/src/types.ts`, so the auth payload shape is shared across the client/worker boundary.
- **`GameSocket.ts`** — the reconnecting WebSocket feeding the `wsGameState` port. Gives up on close code `1008` (credentials rejected); exponential backoff otherwise.

`client/scripts/build.mjs` calls `node_modules/elm/bin/elm` directly rather than the `.bin` shim, which breaks under pnpm.

## Conventions

- **Migrations are append-only.** Never edit a migration that may have been applied — add `worker/migrations/000N_name.sql`.
- **Do not edit `client/elm-stuff/`** (generated).
- Keep client and worker responsibilities separate. Keep ports narrow and typed.
- Worker code: explicit request validation and authorization at every route.
- After a change, run the narrowest check: `pnpm run build:client` after Elm, `pnpm run typecheck:worker` after Worker.
- `ROADMAP.md` is forward-looking; `CHANGELOG.md` is the record of what shipped — add a bullet to its `[Unreleased]` section for any notable change.
