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

- [ ] Load a real UI typeface (Inter) — `Ui.sans` names it but nothing is
      linked, so it falls back to the system stack. Add a `@font-face` or a
      Google Fonts `<link>` in `client/index.html`.
- [ ] The log's scroll-to-bottom is unconditional on every snapshot. Skip it
      when the viewer has scrolled up to read history.

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
