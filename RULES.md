# Rules

The current game rules as the app implements them. This is the canonical
player-facing statement of the mechanics: `DESIGN_PRINCIPLES.md` says *why* the
game is shaped this way, `ROADMAP.md` says what is planned, and this file says
*what the rules are right now*.

**Keep this file current.** Any change to a game rule updates this file in the
same branch, and `client/src/Copy/Terms.elm` (the in-app glossary) follows it.
Where a section below describes a rule that has been decided but not yet built,
it is marked **(Worker built in 26.2; client planned, 26.3)**.

> **Status.** Written 2026-09-18 from the section 26 design pass. The Worker
> implements every rule below (roadmap 26.2, with tests). The client does not
> expose them yet (26.3), so the running app still shows the facilitator-run
> interface from roadmap section 23 and `main` is not deployable until 26.3
> lands.

## The table

- **Facilitator.** Frames scenes, plays the world, and rules on the moves
  players propose. Not a leader (principle 3, principle 7). The facilitator acts
  directly; every other player proposes and waits.
- **Player.** Runs one character. Edits their own sheet and sends messages
  freely. Every other change to shared state is a **move**, and a move waits for
  the facilitator to accept or reject it.
- What the table agrees is true, is true (principle 4). The app records the
  outcome of a rule; it does not settle the fiction.

## Boons, Banes, and the pool

- **Stone.** The unit of chance. A stone is a **Boon** (favourable) or a **Bane**
  (unfavourable).
- **Character boons.** Each character holds a personal count of boons (stored as
  `fate`). Boons are the currency players spend on moves. The facilitator can
  grant or remove them directly.
- **The pool.** One shared pool of stones that every Overcome draws from. It
  **starts at two Boon and two Bane** and returns to exactly that after every
  resolved Overcome. Nothing else resets it, and nothing carries between
  Overcomes: the skew that leftover stones caused in playtest is the reason.
- Players change the pool only by moves (Highlight, using a session boon). The
  facilitator changes it directly: add or remove a Boon or a Bane, or use a
  session boon or bane (below).

## The Overcome **(Worker built in 26.2; client planned, 26.3)**

An **Overcome** is a fork the facilitator declares at the table: a moment where
the plot could go more than one way. The app does not model the declaring. It
models what follows.

1. **Prepare.** Players add Boons to the pool with **Highlight**. The
   facilitator adds Banes: directly, or by using a session bane. Everyone plays
   the scene in voice.
2. **Roll.** The table picks one player, who presses **Overcome**. Any player
   (or the facilitator) may press it. It needs no approval and it draws two
   stones from the pool. Only one roll can be pending at a time.
3. **After the roll, the pool is frozen.** No move that creates, removes, or
   moves boons or banes in the pool is allowed until the Overcome is resolved.
   *This is a table rule.* The app does not stop a player or facilitator from
   breaking it.
4. **Alter.** Players may spend **Alter Fate** to reroll (below). The
   facilitator may reroll directly, for free.
5. **Resolve.** The facilitator either **accepts** or **rejects** the result.
   - **Accept.** The pool returns to two Boon and two Bane. If the final draw
     was two Boons, a **session boon** is created automatically. If it was two
     Banes, a **session bane** is created. A mixed draw creates nothing. The
     facilitator can edit the new session aspect's text afterwards, in their own
     time.
   - **Reject.** The roll is discarded. The pool is not reset and nothing else
     changes. Players may press Overcome again.

Every roll, reroll, and the final accept or reject is a line in the message log,
so the log reads as: roll result, any reroll results, then the accepted result.

## Moves **(Worker built in 26.2; client planned, 26.3)**

The five official move names are **Highlight**, **Overcome**, **Complicate**,
**Add Detail**, and **Alter Fate**. Use these names in copy and in code.

Every move except Overcome is a **proposal**: the player raises it, the
facilitator accepts or rejects it, and both steps are written to the log. A
player can withdraw their own pending proposal. Moves have no once-per-session
limit; they are limited by **cost** and, for Alter Fate, by the rules below.

A move that costs boons cannot be proposed unless the player holds enough: the
button is disabled, and the server refuses the proposal too. The cost is
**paid on approval only**; rejection costs nothing. It is checked again at
approval, in case the player's boons changed while the proposal waited.

| Move | Who | Cost | On approval |
| --- | --- | --- | --- |
| **Highlight** | Player | 1 boon | One boon moves from the player to the pool. One boon per proposal. |
| **Overcome** | Any player | none | Not a proposal. Draws two stones. See above. |
| **Complicate** | Player, naming another character | none | The named character's player gains two boons. The suggester gains nothing. |
| **Add Detail** | Player | 1 boon | A session boon is created. The text comes from the player (it may be blank) and the facilitator can edit it before accepting. |
| **Alter Fate** | Player, during a pending roll | 2 boons | The pending roll is rerolled. |

- **Highlight** — note how an aspect of the scene will shape the outcome, and put
  a boon in the pool. Not allowed to be *resolved* in the middle of a pending
  roll (a table rule, above).
- **Complicate** — suggest a way another character could do something
  dangerous, destructive, or derailing. This is the only compel mechanic; the
  word "compel" is retired. The other player's consent is handled at the table.
- **Add Detail** — establish something true about the scene. Either suggest the
  detail yourself, or ask the facilitator for one. The result is a session boon
  anyone can spend later.
- **Alter Fate** — pay two boons to suggest an alternate action at a fork and
  reroll. Only usable while an Overcome has a roll pending (after at least one
  roll). **One pending Alter Fate proposal at a time.** **Each player may
  succeed at Alter Fate once per Overcome.** A rejected Alter Fate does not use up
  the attempt and removes no boons. The once-per-Overcome allowance resets when
  the Overcome is accepted or rejected.

### What players and facilitator each do directly

| | Player | Facilitator |
| --- | --- | --- |
| Edit own character sheet | yes | yes |
| Send messages | yes | yes |
| Press Overcome | yes | yes |
| Propose a move | yes | not needed |
| Accept / reject a proposal | no | yes |
| Accept / reject an Overcome result | no | yes |
| Reroll the pending roll, free | no | yes |
| Grant or remove a character's boons | no | yes |
| Add or remove a Boon or Bane in the pool | no | yes |
| Create, edit, delete a session boon or bane | no | yes |
| Use a session bane (or boon) directly | no | yes |
| Undo a mistaken "consumed" mark | no | yes |
| Start or end a session, edit the goal | no | yes |

## Session boons and session banes **(Worker built in 26.2; client planned, 26.3)**

A **session boon** or **session bane** is a note of something true in the
fiction, owned by nobody, that can be spent into the pool.

- **Where they come from.** The system creates one when an Overcome that drew two
  of a kind is accepted. Add Detail creates a session boon. The facilitator can
  create either kind directly at any time, and delete any of them at any time.
- **Spending one.**
  - A **player** selects a session boon, which raises a proposal. On approval a
    Boon enters the pool.
  - The **facilitator** uses a session bane (or a session boon) directly, with no
    approval. A Bane enters the pool.
- **Consumed.** Spending a session boon or bane does not delete it. It is marked
  **consumed**, visibly, and a consumed one cannot be spent again. The
  facilitator can **unconsume** one; that is a correction for a table
  miscommunication (something was moved into the pool that should not have
  been), not part of the game's mechanics.
- **Lifetime.** They stay until deleted. Ending a session does not clear them.

## Sessions and the goal

- A **session** runs from the facilitator starting it, with a goal, to ending it.
- The **goal** is plain text for the table's story beats. It is not judged, and
  nothing is rolled to decide whether it was met. The facilitator can edit it at
  any time.
- Starting or ending a session records the goal and dates in the session history
  and does nothing else: it does not touch the pool, proposals, or session
  boons and banes.
- The **message log** is the persistent record of what happened. Session logs
  are a later feature.

## Characters

- A character has three **aspects**: **Archetype** (who the character is to the
  world), **Desire** (what they want badly enough to risk things for), and
  **Quest** (the concrete thing they are trying to do right now), plus a
  **condition** line: one evolving sentence about what strain is doing to them.
- Aspects are always true; a Highlight makes one relevant for a roll.
- There is no death mechanic and no numeric rating (principles 5 and 6).
- **Aspect Banes are not part of the game at present.** The sheet columns exist
  but nothing writes them. They return only if playtest shows they add to
  character progression; advancement is unresolved.

## Open

- Advancement and aspect banes (above). Not decided.
- Session logs beyond the message log. Later.
- Whether an Overcome should ever be a framed, targeted action again. Currently
  not: the facilitator calls it at the table.
