# A die ladder replaces the stone pool

Junctions are decided by one die whose size steps along a ladder (d6, d8, d10,
d12, d16, d20; base d10), not by drawing two stones from a shared pool of Boons
and Banes. Boons and banes now change the die's size instead of adding stones, so
the odds a table builds are visible as one rung on one ladder rather than a
count of stones, and nothing has to be reset stone by stone. The thresholds are
fixed across every die: 1–4 is Friction, 5 or more is Flow, 1–2 is a Critical
Friction and the top two faces a Critical Flow.

## Consequences

- **The two criticals are always equally likely** (two faces in N). Stepping the
  die down makes a context boon *more* likely as well as a context bane, and
  stepping up makes both rarer. This is deliberate — a lower die is a more
  volatile story, and a bane is not purely a penalty — and is not a bug to be
  "fixed" by moving the Critical Flow threshold.
- On a d6 every Flow is a Critical Flow.
- The base odds are 60 / 40 Flow / Friction, deliberately a little generous;
  the d8 is the 50 / 50 die if play asks for less.
- The stored stone pool and any pending stone draw are dropped on migration;
  the die starts at the base.

## Considered options

- **A fixed Critical Flow threshold** (say 9 or more), so stepping up always
  raises the chance of a context boon. Rejected for adding a second magic number
  and for making banes a pure penalty.
- **Keeping the stone pool.** Leftover stones had already skewed play once, and
  the pool's odds were hard to read at a glance.
