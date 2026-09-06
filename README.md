# TethersCord

A Discord Activity for running TTRPG sessions with a shared message board,
character sheets, and dice, built with:

- Elm + esbuild for the front-end (Activity iframe)
- Cloudflare Workers + Durable Objects + D1 for backend state
- Discord Embedded App SDK + OAuth2 for real user IDs and roles (DM vs player)

`DESIGN_PRINCIPLES.md` records the ten core design principles; `ROADMAP.md` is
forward-looking and `CHANGELOG.md` is the record of what shipped.

## Structure

Everything deploys as a **single Cloudflare Worker**. The built Elm SPA is
served from Workers Static Assets on the same origin as the API, so there is no
Pages project and no proxy hop.

- `client/` – Elm single-page app (Activity UI), built to `client/dist`
  - `scripts/build.mjs` runs `elm make` + esbuild; `scripts/watch.mjs` rebuilds
    on change
- `worker/` – Cloudflare Worker backend
  - Durable Object (`GameTable`) per table/session
  - D1 (SQLite) for messages, character sheets, and auth
  - `migrations/` – D1 schema migrations
- `wrangler.jsonc` – the one Worker config, at the repo root

`/api/*` is the only path that reaches Worker code (`run_worker_first`). Every
other path is served as a static asset, falling back to `index.html` for client
routing.

## Prerequisites

- Node 22+ and pnpm 11 (`.nvmrc` pins Node; `packageManager` pins pnpm, so
  `corepack enable` will select the right one)
- Cloudflare account
- Discord Developer Portal application configured as an Activity

## Setup

```bash
pnpm install
cp .dev.vars.example .dev.vars   # then fill in DISCORD_CLIENT_SECRET
pnpm run db:migrate:local
pnpm run dev
```

`pnpm run dev` builds the client, then runs the client watcher and
`wrangler dev` together on http://localhost:8787 — SPA and API on one origin.

## Common commands

| Command | What it does |
| --- | --- |
| `pnpm run build` | Build the client, then typecheck client and worker |
| `pnpm run build:client` | Build the Elm + TS bundle into `client/dist` |
| `pnpm run typecheck` | `tsc --noEmit` over both `client/` and `worker/` |
| `pnpm run deploy:dry-run` | Build and bundle without uploading |
| `pnpm run deploy` | Build, then upload assets and Worker atomically |
| `pnpm run db:migrate:local` | Apply D1 migrations to the local dev database |
| `pnpm run db:migrate:remote` | Apply D1 migrations to the deployed database |
| `pnpm run db:migrations:list` | List remote migration state |

## Secrets

`DISCORD_CLIENT_SECRET` is a secret, not a var:

- locally: `.dev.vars` at the repo root, next to `wrangler.jsonc`
- in production: `pnpm exec wrangler secret put DISCORD_CLIENT_SECRET`

`DISCORD_CLIENT_ID` is a plain var and lives in `wrangler.jsonc`.

## Cutover

These steps are manual and need portal/dashboard access. They are only needed
once, when moving off the old split Pages + Worker deployment:

1. `pnpm run deploy`.
2. In the Discord Developer Portal, point the Activity's **root** URL mapping at
   `tetherscord.tkshillinz.workers.dev` (previously the Pages domain).
3. Delete the now-unused Cloudflare Pages project.
