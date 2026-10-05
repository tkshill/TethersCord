# Moves act immediately and are undone, not approved

A player's move takes effect the moment it is made; the facilitator, or the
player who made it, can undo it during preparation. This replaces the proposal
queue, where every move waited for the facilitator to accept or reject it. The
queue made the facilitator a bottleneck and buried moves behind a tab; most
moves were accepted anyway, so the common case now costs no clicks and the rare
correction costs one.

## Consequences

- **The post-roll lock is enforced by the Worker.** Officially every move except
  Alter is made before a junction's first roll, so boons cannot be spent
  only after seeing a Friction. Approval used to stand in the way of breaking
  that; with no approval, the Worker refuses any other move while a junction is
  pending.
- **Undo reverses one move's own effects**, not the table's state before it, so
  moves made since survive. A reverse step past the end of the ladder stops at
  the end.
- **The undo window closes when the junction is rolled**, so the odds of a roll
  already made cannot change; an Alter stays undoable until its junction
  ends.
- **Complicate is unapproved and free**, so the facilitator's undo is its only
  check.
- Undoable moves are held in Durable Object state and dropped when the window
  closes; nothing about them is written to D1.
