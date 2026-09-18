# TethersCord Instructions

## Project layout

- The whole app deploys as a single Cloudflare Worker configured by the root
  `wrangler.jsonc`. `/api/*` is the only route that reaches Worker code; every
  other path is served from `client/dist` as a static asset, with `index.html`
  fallback for client routing.
- `client/` is an Elm 0.19 application built with esbuild via
  `client/scripts/build.mjs`.
- `worker/` is a TypeScript Cloudflare Worker using Wrangler.
- Keep client and worker responsibilities separate.
- Prefer existing project patterns and minimal, focused changes.
- Use pnpm; all scripts live in the root `package.json`.
- Goal is to make a Discord Application to run my custom TTRPG with my friends. The application will be used to manage the game, including character sheets, dice rolls, and other game mechanics.

## Elm

- Use idiomatic Elm architecture: model, message, update, view.
- Avoid JavaScript interop unless required; keep ports narrow and typed.
- Run client checks after Elm changes:
  - `pnpm run build:client`
  - Run Elm tests when present.

## Worker

- Keep request validation and authorization explicit.
- Preserve TypeScript strictness and Cloudflare Worker compatibility.
- Run `pnpm run typecheck:worker` after Worker changes.
- Use `pnpm run dev` for local runtime verification: it starts the client
  watcher plus `wrangler dev` on port 8787.
- Only run `pnpm run deploy` when explicitly asked.

## General

- Do not modify generated files in `elm-stuff/`.
- Do not change migrations already applied; create a new migration instead.
- Before editing, inspect the relevant local code and tests.
- After edits, run the narrowest relevant validation command.
- Do not commit, push, reset, or discard unrelated workspace changes unless explicitly asked.

<!-- caveman-begin -->
Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra
Stop: "stop caveman" or "normal mode"

Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused. Resume after.

Boundaries: code/commits/PRs written normal.
<!-- caveman-end -->
