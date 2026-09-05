# Roadmap

The backend (single Worker + Durable Object + D1) is stable. Everything below is
incremental work on top of it, roughly in priority order.

## 1. Module structure

`client/src/Main.elm` has grown to a single ~900-line file holding flags, model,
messages, ports, every decoder/encoder, all HTTP commands, and the whole view.
Elm is comfortable with large files, but this one is past the point where the
sections earn their own modules. Do this split **before** the elm-ui pass so the
rewrite lands in a dedicated view module rather than back in `Main`.

- [ ] `Types.elm` — the shared data types with no dependencies: `Role`, `Auth`,
      `Message`, `GameState`, `PendingRoll`, `CharacterSheet`, `CharacterField`
      and its setter. Everything else imports this; it imports nothing local.
- [ ] `Api.elm` — `backendBaseUrl` and every `Http.request` command
      (`getGameStateCmd`, `postMessageCmd`, `postStonesCmd`, `postCharacterUpdateCmd`,
      `postFateCmd`), plus the JSON decoders/encoders they use. Split decoders
      into `Api/Decode.elm` if `Api` itself gets long.
- [ ] `Ports.elm` (`port module`) — the `toDiscord` / `fromDiscord` /
      `wsGameState` ports, `authorizeCmd`, and `decodeFromDiscord`. Port modules
      can live outside `Main`, so only the interop lands here.
- [ ] `Format.elm` (or `Util/Time.elm`) — `formatTimestamp` and `monthNumber`,
      and any other small pure helpers that accumulate.
- [ ] `View.elm` — the view functions, moved out ahead of the elm-ui rewrite.
      Consider `View/Messages.elm`, `View/CharacterSheet.elm`, `View/Roll.elm`
      if it stays large after the rewrite.
- [ ] `Main.elm` keeps only the wiring: `Flags`, `Model`, `Msg`, `init`,
      `update`, `subscriptions`, `main`.
- [ ] Watch for import cycles — the dependency direction is
      `Types` ← everything, and `Main` → `Api` / `Ports` / `View` / `Format`.

## 2. UI pass — `elm-ui`

The current view is bare `elm/html` with class names but no stylesheet. Rebuild
it with [`mdgriffith/elm-ui`](https://package.elm-lang.org/packages/mdgriffith/elm-ui/latest/)
for a spare, legible layout that works inside the narrow Discord Activity iframe.

- [ ] Add `mdgriffith/elm-ui` to `client/elm.json`; introduce a `Ui` module
      holding the palette, spacing scale, and type scale (one accent colour,
      restrained neutrals).
- [ ] Convert `view` to `Element.layout`. Three regions: roll panel, character
      sheets, and the message log + composer.
- [ ] Message log: monospace timestamp column, role emphasis (facilitator vs
      player), comfortable line spacing, its own scroll region that sticks to
      the bottom on new messages.
- [ ] Character sheets as cards in a row that wraps to a column when narrow.
- [ ] Roll panel: show the stone pool and pending roll as chips rather than a
      bullet list.
- [ ] Loading and error states (`model.status`) rendered as a quiet banner, not
      raw text at the top.

## 3. Message log hygiene

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

## 4. Session / campaign structure

- [ ] "Start session" / "end session" markers a facilitator can drop, so the
      log reads as distinct game days.
- [ ] Trim or paginate history — the DO currently loads the last 200 messages
      and the client keeps 200. Fine for now; revisit if a campaign outgrows it.

## 5. Connection polish

- [ ] Surface WebSocket disconnect/reconnect state in the UI.
- [ ] Retry `getGameState` on transient failure instead of parking on
      "Failed to load game state."

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
