# The rules are a pure transition; GameTable persists the difference

Every mutation of a table is computed by one pure function,
`transition(table, command, deps)` in `worker/src/rules/`, which returns the next
table and the log events or a refusal. `GameTable` turns a request into a
`Command`, calls `transition`, and persists the result. No rule awaits
anything. Before this, each handler interleaved its rules with D1 awaits: it
wrote D1, built the next state, then `commit` saved the storage blob, inserted
the log line as a second D1 write, and broadcast. A throw between those steps
left D1 and memory disagreeing, and the rules could only be tested through
`SELF.fetch`.

The design follows the 2026-09-18 architecture review's candidate 1 (roadmap
25.1). The review's own plan file and ADR were never in the repository, so this
was re-derived on 2026-10-04 and recorded here before roadmap 31.2.

## The interface

```ts
transition(table: Table, command: Command, deps: Deps): Result

type Command = { by: Actor } & ( { type: "junction/roll" } | { type: "move/highlight"; aspect } | … )
type Actor   = { userId: string; name: string; role: Role }
type Deps    = { roll(sides: number): number; now(): number; newId(): string }
type Result  = { ok: true; next: Table; log: LogEvent[] }
             | { ok: false; status: 400 | 403 | 404 | 409; reason: string }
```

- `Table` is `GameState` without `messages`. The 50-message window belongs to
  `GameTable`, since no rule reads it.
- `Command` covers **every** mutation, chat and entity edits included, so
  `GameTable` has a single mutation path. The trivial arms cost little; a
  second path would bring back the interleave.
- **Authorisation that depends on role or state is a rule.** Facilitator-only
  commands, sheet ownership and "the facilitator or the move's own player may
  undo" are refused by `transition` (403). `GameTable` only authenticates,
  turning a token into an `Actor`.
- `Deps` is a seam with two adapters: crypto randomness, `Date.now()` and
  `crypto.randomUUID()` in production, and a scripted roll, a fixed clock and
  sequential ids in tests. Ids come from `deps` so a move can record the id of
  its own log line (`messageId`) before anything is written.
- The log is a `LogEvent` union (`{ kind: "die-step", from, to }`, …). One pure
  `logText(event)` turns it into the stored line, so tests assert events rather
  than wording, and a rename of game vocabulary touches one formatter.

Internal seams, private to `rules/` and tested through `transition`: `dice`
(the ladder, `step`, `classify`), `junction`, `moves` (moves and undo),
`context`, `sheets`, `session`, `entities`. `transition` dispatches with an
exhaustive `never` check. Only `dice` is also exported, for the client's
ladder-parity fixture.

**Undo is one inverse.** A move returns its effects as data, for example
`[{ die: +1 }, { boons: { slot, delta: -1 } }]`. That list is applied by one
interpreter and stored on the move record. Undo applies the inverted list,
clamping at the ladder ends and at zero boons (ADR 0002). The five undo rules
are not written separately.

## Persistence: the diff, not a list of writes

`transition` does not say what to write. A pure `persistDiff(prev, next, log)`
compares the D1-mirrored parts of the two tables: character sheets by slot,
NPCs and locations by id, and the running session by id (start, goal, end). It
emits row writes, plus a message insert for each log event; clearing the log is
an explicit change, because the message window is not a mirror of the table.
`GameTable` then does:

1. `DB.batch(...)` of every statement: one round trip, applied atomically. On
   failure nothing has changed, and the request fails.
2. With no `await` between them: install the next state in memory, `put` the
   Durable Object slice (skipped when it is byte-identical), and broadcast. The
   output gate holds the broadcast until the `put` is durable. If the `put`
   fails, the object resets and reloads, at most one mutation behind D1.

This is all done inside `withLock`, as before.

## Consequences

- Memory and D1 cannot diverge because a handler forgot one half: there is no
  handler code that writes D1. This absorbs roadmap 25.2. `characters.ts` keeps
  only row mapping.
- Session end adds the closed session to `sessionHistory` in memory instead of
  re-reading `game_sessions`, so `SessionState` gains `startedAt`
  (`migrateTableState` supplies a default for older blobs).
- Rules tests call `transition` directly under `worker/test/rules/`, in the
  existing workers pool. A separate plain-Node vitest project is not needed
  unless the suite gets slow. Route tests shrink to wiring: the status code,
  the broadcast, what is persisted. Rule tests that run through routes are
  replaced by core tests, not kept alongside them.
- The route table, the half of P2.2 that survives, maps
  `{ method, path }` to a `parse(request) → Command`; `fetch` becomes
  authenticate, parse, apply.
- `persistDiff` must learn every new D1-mirrored field. A field it misses is
  silently lost on cold start, so it has its own tests over each mirrored
  slice.

## Considered options

- **Explicit `writes[]` from each arm** (the review's sketch). It is simpler
  to flush, but every arm must emit a write for each change it makes to
  memory. That is the same two-halves bug, moved into data.
- **Log lines as strings built in each arm.** Less code, but tests would match
  wording, and 31.1 showed how widely log text moves in a rename.
- **An overridable dice source on `GameTable`**, set through
  `runInDurableObject` (the first 31 plan). It is replaced by `Deps.roll`,
  which reaches the rules without a Durable Object.
