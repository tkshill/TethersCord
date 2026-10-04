# Rules

The current game rules. This is the canonical player-facing statement of the
mechanics: `DESIGN_PRINCIPLES.md` says *why* the game is shaped this way,
`CONTEXT.md` fixes the words, `ROADMAP.md` says what is planned, and this file
says *what the rules are*.

**Keep this file current.** Any change to a game rule updates this file in the
same branch, and `client/src/Copy/Terms.elm` (the in-app glossary) follows it.

> **Status.** Rewritten 2026-10-04 from the section 31 design interview. These
> are the official rules, but **the app does not implement them yet**: it still
> runs the stone pool, the Overcome and the proposal queue of section 26 until
> roadmap section 31 lands. Remove this note when 31.6 ships.

## The table

- **Facilitator.** Frames scenes, plays the world, and makes direct edits. Not
  a leader (principle 3, principle 7). The facilitator can undo any move.
- **Player.** Runs one character. Edits their own sheet, sends messages, and
  makes moves. A move takes effect at once; nobody approves it.
- What the table agrees is true, is true (principle 4). The app records the
  outcome of a rule; it does not settle the fiction.

## Aspects

An **aspect** is a statement that is true in the fiction. There are two kinds.

- **Character aspects.** Every character has three: **Archetype** (who the
  character is to the world), **Desire** (what they want badly enough to risk
  things for) and **Quest** (the concrete thing they are trying to do right
  now). They are always true; highlighting one makes it matter for a junction.
- **Context aspects.** Statements about the situation, owned by nobody. Each is
  a **context boon** or a **context bane** and carries one use.
  - **Where they come from.** An accepted Critical Flow adds a context boon,
    an accepted Critical Friction a context bane. **Create** adds a context
    boon, **Complicate** a context bane. The facilitator can add either kind
    directly at any time.
  - **Consumed.** Highlighting one spends its use. It is not deleted: it stays
    on the table, visibly consumed, and cannot be highlighted again.
  - **Lifetime.** They stay until the facilitator deletes them. Ending a
    session does not clear them.

## Boons

- Each character holds a count of **boons**: the currency players spend on
  moves. Complicate earns them. The facilitator can grant or remove them
  directly.
- "Boon" on its own always means this currency, never a context boon.

## The die

- One **die** decides every junction. Its size moves along the **ladder**:

  **d6 → d8 → d10 → d12 → d16 → d20**

- The **base die** is the **d10**. The die returns to it whenever a junction is
  accepted.
- A boon **steps the die up** one rung; a bane **steps it down** one rung. A step
  past either end of the ladder is not allowed: nothing is spent and nothing
  happens.
- **Reading a roll.** The same thresholds on every die:

  | Face | Outcome |
  | --- | --- |
  | 1–2 | **Critical Friction** |
  | 3–4 | **Friction** |
  | 5 and up | **Flow** |
  | the die's two highest faces | **Critical Flow** |

  On a d6 every Flow is a Critical Flow (5–6).
- **Flow** is the easier path for the characters; **Friction** the harder one,
  with more difficulty or conflict.
- **The two criticals are always equally likely.** A smaller die makes the
  story more volatile both ways; a larger die steadies it.

  | Die | Critical Friction | Friction | Flow | Critical Flow |
  | --- | --- | --- | --- | --- |
  | d6 | 33% | 33% | 0% | 33% |
  | d8 | 25% | 25% | 25% | 25% |
  | d10 | 20% | 20% | 40% | 20% |
  | d12 | 17% | 17% | 50% | 17% |
  | d16 | 12.5% | 12.5% | 62.5% | 12.5% |
  | d20 | 10% | 10% | 70% | 10% |

## The junction

A **junction** is a point the facilitator declares at the table, where the story
could go two ways: one easier for the characters (flow), one harder (friction).
The app does not model the declaring. It models what follows.

1. **Prepare.** Players make their moves: Highlight, Highlight Context,
   Complicate, Create. The facilitator steps the die or highlights context
   aspects directly. Everyone plays the scene in voice. **All of this happens
   before the roll.**
2. **Roll.** Any player, or the facilitator, rolls the die. It needs no
   approval. Only one junction is pending at a time.
3. **After the roll, preparation is over.** The only move left is **Alter
   Fate**. Nothing else can change the die, spend boons, or highlight an aspect
   until the junction ends. This is deliberate: boons are spent proactively,
   not only after a Friction. The app enforces it. (The facilitator's direct
   edits stay available, for corrections.)
4. **Alter.** Players may spend **Alter Fate** to reroll. The facilitator may
   reroll directly, for free. Either way the roll is on the same die.
5. **Resolve.** The facilitator **accepts** or **rejects** the roll.
   - **Accept.** The last roll stands. The die returns to the d10. A Critical
     Flow adds a context boon; a Critical Friction adds a context bane; any
     other outcome adds nothing. The facilitator words the new context
     aspect in their own time.
   - **Reject.** The roll is discarded. The die stays where it was and nothing
     else changes. The junction can be rolled again.

Only the accepted roll adds a context aspect: rerolls and Alters never do.
Every roll, reroll and the final accept or reject is a line in the message log,
and a roll reads as its outcome, face and die ("Flow — 7 on d10").

## Moves

There are five moves: **Highlight**, **Highlight Context**, **Complicate**,
**Create** and **Alter Fate**. Use these names in copy and in code.
Rolling a junction is not a move.

A move takes effect immediately. A move that costs boons cannot be made unless
the player holds enough. Every move is a line in the log.

| Move | Who | Cost | Effect |
| --- | --- | --- | --- |
| **Highlight** | Player, on one of their character aspects | 1 boon | The die steps up. |
| **Highlight Context** | Anyone, on an unconsumed context aspect | none | A context boon steps the die up; a context bane steps it down. It is consumed. |
| **Complicate** | Player, on one of their character aspects | none | The character gains two boons, and a context bane appears for the facilitator to word. |
| **Create** | Player | 1 boon | A context boon is added in the player's words. |
| **Alter Fate** | Player, after a roll | 2 boons | The roll is rerolled on the same die. |

- **Highlight** — show how one of your character aspects shapes what happens
  next. Highlights stack: each steps the die one rung.
- **Highlight Context** — bring a context aspect to bear. Highlighting a context
  bane makes the junction riskier and more volatile; that is a choice a player
  may make.
- **Complicate** — suggest a way one of your character aspects drags your
  character into something dangerous, destructive, or derailing. You gain two
  boons, and the trouble becomes a context bane. This is the only compel
  mechanic.
- **Create** — establish something true about the scene. If you leave it
  blank it is recorded as a detail from you, and the facilitator can reword it.
- **Alter Fate** — pay two boons to suggest an alternate action and reroll. Only
  after a roll and before the junction ends. **Each character may Alter Fate
  once per junction.**

### Undo

- The facilitator can undo **any** move; a player can undo **their own**.
- Undo reverses that move's own effects and nothing else, so moves made since
  are kept:
  - Highlight: the die steps down, the boon is refunded.
  - Highlight Context: the aspect is unconsumed, the die steps back.
  - Complicate: the two boons are taken back, the context bane is deleted.
  - Create: the context boon is deleted, the boon is refunded.
  - Alter Fate: the previous roll is restored, the two boons are refunded, and
    the character may Alter Fate again.
- A step back that would pass the end of the ladder stops at the end.
- **Undo is open during preparation only**: it closes when the junction is
  rolled. An Alter Fate can be undone until its junction is accepted or
  rejected.
- An undo is a line in the log.

### What players and facilitator each do

| | Player | Facilitator |
| --- | --- | --- |
| Edit own character sheet | yes | yes |
| Send messages | yes | yes |
| Roll the junction | yes | yes |
| Make a move | yes | not needed |
| Undo a move | own | any |
| Accept / reject a junction | no | yes |
| Reroll a junction, free | no | yes |
| Step the die up or down directly | no | yes |
| Grant or remove a character's boons | no | yes |
| Add a context boon or bane directly, free | no | yes |
| Word, reword or delete a context aspect | no | yes |
| Start or end a session, edit the goal | no | yes |

The facilitator's direct edits are logged when they move the die, and are
reversed by editing back rather than by undo.

## Sessions and the goal

- A **session** runs from the facilitator starting it, with a goal, to ending it.
- The **goal** is plain text for the table's story beats. It is not judged, and
  nothing is rolled to decide whether it was met. The facilitator can edit it at
  any time.
- Starting or ending a session records the goal and dates in the session history
  and does nothing else: it does not touch the die, moves, or context aspects.
- The **message log** is the persistent record of what happened. Session logs
  are a later feature.

## Characters

- A character has three **character aspects** (above) and a **condition** line:
  one evolving sentence about what strain is doing to them.
- There is no death mechanic and no numeric rating (principles 5 and 6).
- **Aspect Banes are not part of the game at present.** The sheet columns exist
  but nothing writes them. They return only if playtest shows they add to
  character progression; advancement is unresolved.

## Open

- Whether 60 / 40 Flow / Friction at the d10 is too generous.
- Whether equally likely criticals feel right at the table.
- Advancement and aspect banes (above). Not decided.
- Session logs beyond the message log. Later.
