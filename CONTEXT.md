# TethersCord

A rules-lite tabletop RPG played inside a Discord Activity: a facilitator and a
few players tell a story together, and a single die decides which way the story
turns at each junction. `RULES.md` states the rules; this file fixes the words.
Terms listed under _Avoid_ are retired and may still appear in code until
roadmap section 31 lands.

## Language

### The table

**Facilitator**:
The one person at the table who frames scenes, plays the world, and can make
direct edits and undo any move. Not a leader.
_Avoid_: GM, DM, game master, narrator

**Player**:
A person at the table who runs one character.

**Character**:
A protagonist a player runs, written around three character aspects.
_Avoid_: PC, sheet (the sheet is where a character is written down)

### Aspects

**Aspect**:
A statement that is true in the fiction. Every aspect is either a character
aspect or a context aspect.

**Character aspect**:
One of a character's three standing aspects: **Archetype** (who they are to the
world), **Desire** (what they want badly enough to risk things for) and
**Quest** (the concrete thing they are trying to do now).

**Context aspect**:
An aspect of the situation, owned by no character, carrying one boon or one
bane that can be used once. Either a context boon or a context bane.
_Avoid_: session aspect, floating boon

**Context boon**:
A context aspect that steps the die up when highlighted.
_Avoid_: session boon, floating boon

**Context bane**:
A context aspect that steps the die down when highlighted.
_Avoid_: session bane

**Consumed**:
The state of a context aspect whose one use is spent. It stays on the table,
visibly, and cannot be highlighted again.

**Condition**:
One evolving sentence on a character about what strain is doing to them. Not
an aspect.

### Boons

**Boon**:
A character's currency, spent on moves and earned by Complicate. Always a
character's own; never a die step or a context aspect.
_Avoid_: fate, stone, token

### The die

**Die**:
The one die the table rolls at a junction. Its size is its rung on the ladder.
_Avoid_: pool, bag, stones, dice pool

**Ladder**:
The fixed order of die sizes the die moves along: d6, d8, d10, d12, d16, d20.

**Base die**:
The d10, the die's rung whenever no junction has changed it.

**Step up / step down**:
Moving the die one rung up or down the ladder. A move that would step past either
end of the ladder is refused.
_Avoid_: add a boon / bane to the pool

### The junction

**Junction**:
A point where the story could go two ways, one easier for the characters (flow)
and one harder (friction), from its first roll until the facilitator accepts or
rejects it.
_Avoid_: Overcome, fork, check, test

**Preparation**:
The time before a junction's first roll, when moves are made and can be undone.

**Roll**:
One throw of the die during a junction. A junction may have several: a reroll
or an Alter replaces the previous roll.
_Avoid_: draw

**Face**:
The number a roll shows.

**Outcome**:
What a roll's face means: Critical Friction, Friction, Flow or Critical Flow.
_Avoid_: result (for the outcome specifically), success, failure

**Flow**:
An outcome of 5 or more: the story takes the easier path.

**Critical Flow**:
A Flow on one of the die's two highest faces. Accepting it adds a context
boon.

**Friction**:
An outcome of 4 or less: the story takes the harder path.

**Critical Friction**:
A Friction on a 1 or a 2. Accepting it adds a context bane.

**Accept / reject**:
The facilitator's ruling that ends a junction. Accepting keeps the last roll
and resets the die to the base die; rejecting discards it and leaves the die.

### Moves

**Move**:
Something a player does that has a cost or an effect and can be undone. There
are five: Highlight, Highlight Context, Complicate, Create and Alter.
Rolling a junction is not a move.
_Avoid_: proposal, ability, action

**Highlight**:
Spending a boon to make one of your character aspects matter: the die steps up.
_Avoid_: pledge

**Highlight Context**:
Using a context aspect's one use: a context boon steps the die up, a context
bane steps it down, and the aspect is consumed.
_Avoid_: use session boon, use floating

**Complicate**:
Drawing trouble from one of your character aspects: your character gains two
boons and a context bane appears for the facilitator to word.
_Avoid_: compel, suggest compel

**Create**:
Spending a boon to establish something true about the scene, which becomes a
context boon in the player's words.
_Avoid_: Add Detail, gain insight

**Alter**:
Spending two boons to reroll a junction's pending roll on the same die; the
only move allowed after the first roll, once per character per junction.
_Avoid_: Alter Fate, help out, press fate

**Undo**:
Reversing one move's own effects, by the facilitator or the move's player,
during preparation (or, for Alter, before the junction ends).
_Avoid_: withdraw, reject (for a move)

**Direct edit**:
A change the facilitator makes without a move: stepping the die, granting or
removing boons, adding or rewording a context aspect. Reversed by editing back,
not by undo.

### Sessions

**Session**:
One sitting of play, from the facilitator starting it with a goal to ending it.

**Goal**:
Free text naming the session's story beats. Never judged or rolled against.

**Log**:
The table's running record of chat and of every roll, move, undo and direct
edit.
_Avoid_: history (the session history is the list of past sessions)

## Relationships

- A **Character** has exactly three **character aspects** and a count of **boons**.
- A **Junction** has one or more **rolls**, each on the **die** at that time, each
  with a **face** and an **outcome**; the last roll is the one accepted.
- An accepted **Critical Flow** or **Critical Friction** adds one **context
  aspect**; **Complicate** adds a **context bane**; **Create** adds a
  **context boon**; the **facilitator** may add either as a direct edit.
- **Highlight** and **Complicate** each name one of the player's own **character
  aspects**; **Highlight Context** names one **context aspect**.

## Example dialogue

> **Player:** "I'll Highlight my Desire — she won't leave without the letter."
> **Facilitator:** "Die's at d12 then. Anyone highlighting a context before we
> roll?"
> **Player:** "The flooded stairwell — I'll Highlight Context on that bane. Make
> it messy."
> **Facilitator:** "Back to d10. Rolling the junction… 2. Critical Friction. I'll
> accept, and the new context bane is *the letter is soaked through*."

## Flagged ambiguities

- "Session boon / bane" was renamed **context boon / bane** because they outlive
  the session that made them.
- "Boon" meant a character's currency, a pool stone and a session boon at once;
  it now means only the currency.
- "Add Detail" was renamed **Create**, a single verb like the other moves. Because
  Create is a move, other ways a context aspect comes into being are described
  as *adding* one, never *creating* it.
- "Alter Fate" was shortened to **Alter** for the same reason.
- "Use a context" was named **Highlight Context** so that every die step a
  player makes from an aspect is a Highlight of some kind.
