> Kept from the design handoff for roadmap section 32. The HTML reference
> (`Table v2.dc.html`) and its `support.js` runtime are not in the repo; the
> screenshots below show its four states.

# Handoff: Table v2 (High contrast)

## Overview
A cohesive visual pass on the TethersCord Activity (`tkshill/TethersCord`, `client/src`). Layout stays the same: a status strip over three columns (tool panel · context · log). What changes:
- One palette and type system (High contrast only, no theme switch).
- Character aspects and context aspects share one visual block.
- Larger reading type.
- A bigger Create/Add entry.
- The Condition field is removed from the sheet.
- The die ladder is compacted into a roll button with rung bars.
- The facilitator's direct-edit controls are restyled.
- The Guide is rebuilt.
- The "Cast" tab is renamed "World".

Game rules and behaviour are unchanged (RULES.md, ADR 0001/0002). This is presentation only, plus one tool-strip state change (see State Management).

## About the design files
`Table v2.dc.html` is a **design reference built in HTML**. It is a prototype of the intended look and behaviour, not code to ship. Recreate it in the existing Elm / elm-ui client using its patterns (`Ui.elm` building blocks, `Copy.elm` strings, `View/*` modules). To view it, open the file in a browser next to `support.js`. The Tweaks panel switches between:
- **role:** Player / Facilitator
- **moment:** Preparation / Junction pending

Ignore its `theme` and `marks` tweaks. Ship **High contrast** with **☼ ☽**.

## Fidelity
**High fidelity.** The colours, type, spacing, radii and copy below are final. The target frame is 1000×560, a Discord Activity on a 13" laptop.

---

## Design tokens (replace the palette in `Ui.elm`)

| Ui.elm name | New value | Use |
|---|---|---|
| `paper` | `#ffffff` | page background, composer row |
| `panel` | `#ffffff` | blocks, buttons, log column |
| `ink` | `#000000` | primary text; primary-button hover |
| `inkSoft` | `#333333` | labels, meta, timestamps, placeholders (12.6:1) |
| `line` | `#8c8c8c` | hairlines: column rules, row dividers, strip borders |
| **new** `edge` | `#1a1a1a` | 1px borders on aspect blocks, buttons, inputs, chips |
| `tint` | `#e6ecfb` | selected tab, hover wash, roll row, locked note |
| `selectedWash` | `#e6ecfb` (= tint) | selected tool tab |
| `accent` | `#0a3a8c` | primary buttons, boon marks, Flow, current rung |
| `accentText` | `#ffffff` | text on accent |
| `danger` | `#9e0000` | bane marks, Friction, Reject hover |
| `success` | `#00662b` | Highlight half of the split button |
| **new** `accentSoft` | `#86a0d4` | Flow segment in the Guide odds bars |
| **new** `dangerSoft` | `#dc8f8f` | Friction segment in the Guide odds bars |
| `facilitatorTint` / `speakerColor 0` | `#7a3300` | facilitator name in the log |
| `speakerColor 1` / `2` / `3` | `#0a3a8c` / `#00662b` / `#6b1f6b` | player names |

The split-button washes in `client/index.html` change to:
- left (Complicate): `linear-gradient(to right, rgba(158,0,0,.16), rgba(158,0,0,0))`
- right (Highlight): `linear-gradient(to left, rgba(0,102,43,.18), rgba(0,102,43,0))`
- touch resting tints: same colours at alpha `.07` / `.08`

### Type
- **UI, text and labels:** `Atkinson Hyperlegible` (400, 700, 400 italic). Replace `Ui.sans`.
- **Mono** (timestamps, die chips, odds labels): `IBM Plex Mono` 400/500. Replace `Ui.mono`.
- **Glyphs** (☼ ☽ ↑ ↓): `Noto Sans Symbols 2`, then `Segoe UI Symbol`, `DejaVu Sans`. Apply it in `Ui.boonMarks` / `Ui.baneMarks` and on every mark cell. Apple Symbols draws ☼ as a thin ring that reads as "empty", so this stack must win.
- **⚠ Self-host all three** in `client/public/fonts/` with `@font-face` in `client/index.html`, the same way Inter is now. Discord's Activity CSP blocks Google Fonts. Inter can be dropped.

| Role | Size / weight | Notes |
|---|---|---|
| Statement (aspect text, context text, chat body, goal) | 15px / 400, lh 1.35–1.4 | `text-wrap: pretty` where possible |
| Character name | 22px / 500, lh 1.15 | |
| Body UI | 13px / 400 | |
| Tabs, buttons | 12.5px (tabs), 12px (buttons); selected/primary 600 | |
| Event line | 12px / 400, `inkSoft` | **no italic** |
| Section/field label | 10px / 600, letter-spacing .07em, uppercase, `inkSoft` | `Ui.sectionTitle` and the sheet `labelStyle` |
| Meta (from, counts, costs) | 10.5–11px, `inkSoft` | |
| Timestamp | mono 10.5px, `inkSoft`, column 34px wide | |

### Radii and spacing
- **Radii:** aspect/context block 7 · buttons, tabs, chips 5 · small square buttons 4 · roll row 6 · step chip 3 · odds bar 2.
- **Spacing:** keep the `xs 4 / sm 8 / md 12 / lg 20` scale. The values used below are 2, 3, 4, 7, 9, 10, 12, 14 px.
- **Shadows:** none.

---

## Screens / views

### Frame
The column direction is unchanged; only the widths change:
- Status strip (42px) over a row of three columns.
- **Tool panel:** `width px 316`.
- **Context:** `width px 284`.
- **Log:** `width fill`.

Each column is separated by a 1px `line` rule. Today all three columns are equal. The fixed tool and context widths give the log the leftover space (≈398px at 1000px).

### 1 · Status strip (`View/TopBar.elm`)
Row: height 42, padding `0 12 0 14`, gap 14, bottom border 1px `line`. Left to right:

1. **"GOAL"** label (10px/600/.07em, `inkSoft`, no shrink).
2. **Goal text:** 15px, one line with ellipsis (`Ui.oneLine`), fills the space. For the facilitator a `▾` (10px, `inkSoft`) follows the text. The whole thing stays the `ToggleSessionControls` button with tooltip `Copy.goalTip`.
3. **Rung bars:** replaces the six text labels `d6 … d20`.
   - Six bars, 5px wide, gap 3, bottom-aligned in an 18px-tall box.
   - Heights 6, 8.4, 10.8, 13.2, 15.6, 18px; radius 1.5.
   - Colour: current rung = `accent`; d10 (base, when not current) = `inkSoft`; others = `line`.
   - Each bar's tooltip is its label. The group's tooltip is "The ladder: d6 · d8 · d10 · d12 · d16 · d20. The die is at d16."
4. **Die control:** a row with gap 4.
   - *Facilitator only*, either side of the die: step buttons `‹` / `›`.
     - 24×26, 1px `edge`, radius 5, `panel` background, glyph 15px.
     - Hover: border and text `accent`.
     - Tooltips `Copy.stepDownTip` / `Copy.stepUpTip`. Disabled at a ladder end (existing `Die.step` logic).
     - Available in both preparation and junction.
   - *No roll pending:* **primary button "Roll d16"**.
     - 12.5px/600, padding 5×12, radius 5, `accent` background, white text; hover background `ink`.
     - Tooltip `Copy.rollTip`. New copy: `rollButton die = "Roll " ++ die`.
   - *Roll pending:* outlined chip **"d16"**.
     - 12.5px/600, padding 4×10, 1px `edge`, radius 5.
     - Tooltip `Copy.dieTip`.
5. **Result** (roll pending only): "Flow · 11".
   - 13px/600.
   - Colour: Flow / Critical Flow = `accent`; Friction / Critical Friction = `danger`. Criticals are bold (existing).
   - Tooltip unchanged ("Halvard rolled d16 · no rerolls").
6. **Junction controls** (roll pending only), gap 4.
   - *Player:* ghost button **"Alter ☼☼"**, the cost shown as glyphs, existing enable rules and tooltips.
   - *Facilitator:* ghost buttons **Reroll** and **Reject** (Reject hovers `danger`), then primary **Accept**.
   - **Ghost button:** 12px, padding 4×10, 1px `edge`, radius 5, `panel` background; hover border and text `accent`.
7. **Who:** 11.5px `inkSoft`. "tkshill ◈" for the facilitator, the username for a player. Tooltip unchanged.

### 2 · Tool panel (`View.elm` toolStrip + `View/Characters.elm`)

**Tool strip.** Height 36, padding `0 8`, gap 2, bottom border `line`.
- It merges the **character slot tabs** and the tools into one strip:
  `[Wren you] [Halvard] [Mara]  |  World  Guide`
- **Tab:** 12.5px, padding 4×9, radius 5.
  - Selected: `tint` background, `ink`, 600.
  - Idle: `inkSoft`; hover `ink` on `tint`.
- **"you" marker:** a 10.5px suffix inside the tab (gap 4), replacing `Copy.youMarker`'s " (you)". The facilitator sees no marker.
- **Separator:** 1×16 `line`, margin `0 5 0 auto`, so World and Guide sit at the right.
- **Rename:** `Copy.castTabLabel = "World"`, `Copy.castTabTip = "NPCs & locations"`.
- Tooltips: idle character tabs "Halvard's sheet"; Guide `Copy.guideTabTip`.

**Body:** padding `12 14 14`, scrolls (`Ui.scrollArea`).

**Sheet:** a column with gap 10.

1. **Header.**
   - Name: 22px/500, read-only display. Editing stays available via the existing Name field behaviour; a ✎ on hover is fine.
   - To its right: **boons** as ☼ marks, 17px glyph font, letter-spacing 2, `accent`, tooltip "3 boons". When the count is 0, show `Copy.boonsNone` at 12px `inkSoft`.
   - *Facilitator:* after the marks, two square buttons **−** / **+** (22×22, 1px `edge`, radius 4, 13px).
     - Tooltips "Remove a boon" / "Grant a boon".
     - Wired to `FateDecrement` / `FateIncrement`.
     - This replaces the old "Grant − +" row.
2. **Notable features.** Under the name, a borderless inline input: 13.5px italic `inkSoft`, placeholder "Notable features…", tooltip "Notable features". It saves on blur (existing `CharacterFieldBlur`).
3. **Owner line** (facilitator, and any unclaimed sheet): 11px `inkSoft`, "Played by sam".
   - Keep the existing claim/release logic (`ownerRow`).
   - Render Claim / Release as a `linkButton` at the right of this line.
   - The player's own sheet needs no line; the "you" tab says it.
4. **Locked note** (player's own sheet, roll pending): `Copy.movesLocked`.
   - 11.5px `inkSoft`, padding 5×8, `tint` background, radius 5.
5. **Aspect blocks** (Archetype, Desire, Quest). This is the shared aspect identity.
   - **Block:** 1px `edge`, radius 7, `panel` background, padding `8 11 9`.
   - **Label:** 10px/600/.07em uppercase `inkSoft`.
   - **Statement:** 15px, lh 1.35, under the label with gap 3.
   - **✎:** absolutely positioned at top 5 / right 6. 12px `inkSoft`, hover `accent`, sits above the split halves.
   - **Split button** on the viewer's own sheet in preparation:
     - Bottom padding grows to 22px, to make room for the hover labels.
     - The two halves (`Ui.splitButton`) fill the block.
     - Labels 10.5px/600, aligned to the bottom, padding `0 10 5`.
     - Left half is `Copy.complicateHalf` in `danger`; right half is `Copy.highlightHalf` in `success`.
     - Labels show on hover, focus or press (existing CSS).
   - **No split button** for the facilitator, on other players' sheets, or after the roll. The block is identical, minus the halves.
   - "see examples" (`aspectExamplesBlock`) is not in the mock. Show it only while an aspect is empty or being edited, as a `linkButton` under the block.
6. **Remove the Condition field** from the sheet (`ConditionField`). Leave the data and wire format alone; the field just isn't rendered.
7. **Notes.**
   - "NOTES" label, then a 2-row textarea.
   - No border except a 1px `line` bottom border; padding-bottom 4.
   - 13px, lh 1.4, placeholder "Private notes…".

### 3 · Context column (`View.elm` contextPanel + `View/ContextAspects.elm`)

**Header.** Height 36, padding `0 14`, bottom border `line`.
- Left: "CONTEXT" label.
- Right: "4 open · 1 consumed", 11px `inkSoft`.
- This replaces the `Ui.divider` title.

**List.** Padding `12 14`, gap 7, scrolls. `View.Session` (session history) stays beneath the list.

**Open context aspect.** The whole block is the Highlight Context button, same identity as the aspect block.
- **Block:** 1px `edge`, radius 7, `panel` background, padding `8 11`, gap 3. Hover `tint` (when enabled).
- **Meta row** (one line, `nowrap`, line-height 1, gap 5):
  - Mark cell: 13px wide, glyph font 13px.
  - Kind label "BOON" or "BANE": 10px/600/.07em, in `accent` or `danger`.
  - Right-aligned origin, 10.5px `inkSoft`, nowrap, no shrink: "Mara · Create" or "Wren · Complicate". Show nothing if there is no origin.
  - *Facilitator:* after the origin, `✎` and `×` (12px `inkSoft`, gap 6; hover `accent` and `danger`).
  - These can't be nested buttons inside the row button. Either restructure the row (button for the statement, a sibling for the actions) or use `Element.inFront`.
- **Statement:** 15px, lh 1.35. An unworded Complicate bane shows `Copy.unwordedFrom` in italic `inkSoft`.
- **Tooltips:** existing (`highlightContextTip`, `movesLocked`, `dieAtEnd`).

**Consumed aspect.**
- 1px **dashed** `edge` border, no fill.
- Mark and kind in `inkSoft`. "consumed" at the right (10.5px `inkSoft`).
- Statement in `inkSoft` with line-through.
- *Facilitator:* `×` only.
- Tooltip `Copy.contextAspectConsumedTip`.
- The old faded mark (alpha .4) and the inline "consumed" tag are replaced by this.

**Entry box.** Pinned under the list (`createField`).
- Wrapper: padding `10 14 12`, top border `line`.
- Box: 1px dashed `edge`, radius 7, `panel` background, padding `8 11`, gap 4. It reads as "an aspect waiting to be written".
- *Player, Create:*
  - Meta row: "☼ CREATE" in `accent`; right "costs ☼", 10.5px `inkSoft`, nowrap.
  - Textarea: 3 rows, 15px, no border, placeholder `Copy.createPlaceholder`.
  - Primary **Create** (12px/600, padding 4×12), right-aligned.
  - When unavailable: opacity .4, with the reason as its tooltip (existing logic).
- *Facilitator, Add:*
  - Meta row: two toggle pills, then "free" at the right.
  - Pill: padding 2×7, radius 4, 10px/600/.07em, with a 12px glyph. Each one is a glyph plus a word, not the glyph alone.
  - **☼ BOON** selected: `accent` fill, white text, `accent` border.
  - **☽ BANE** idle: transparent, `danger` text, `edge` border; hover border `danger`.
  - Whichever pill is selected takes the filled style.
  - Textarea placeholder `Copy.addContextAspectPlaceholder`.
  - Primary **Add**.
- **Keys:** Enter submits. Newlines are stripped, the same as today's sheet fields, because a context aspect is one statement.

### 4 · Log column (`View/Log.elm`)
Background `panel`. The list has padding `12 16` and gap 9.

- **Day divider:** existing `Ui.divider`. Label 10px, letter-spacing .06em, uppercase ("4 OCT").
- **Chat line:** row with gap 10.
  - Timestamp: mono 10.5px `inkSoft`, 34px wide, padding-top 3.
  - Body: 15px, lh 1.4.
  - Speaker name: 12.5px/600 in the speaker colour, followed by a space.
- **Event line:** restyled. No italic, no left border.
  - Row: timestamp (padding-top 1), then a **mark column** (13px wide, glyph font 13px, no shrink), then a wrapping group (gap `3 7`).
  - The wrapping group holds:
    - text, 12px `inkSoft`, lh 1.4
    - optional **step chip** "d10 → d12": mono 10.5px, padding `0 5`, 1px `line`, radius 3, `ink`
    - optional **undo**: 11px `inkSoft`, underlined (offset 2), hover `accent`
  - Mark per event:
    - ☼ `accent`: context boon added, Create
    - ☽ `danger`: context bane added, Complicate
    - ↑ `accent` / ↓ `danger`: Highlight, Highlight Context, direct step
  - **Data note:** the mark and the step chip need structure the log line may not carry today (move kind, die before/after). Derive the kind from `MoveRecord` where the line has a `messageId`. If the Worker's message has no die delta, either add one to the event payload or leave the chip out. Keep the existing content strings and the "· author" suffix if the Worker's text doesn't already name the actor.
- **Roll line** (each roll, reroll and alter):
  - Row: `tint` background, radius 6, padding `7 8`, margin `2 -8`, gap 10.
  - Contents: timestamp; outcome (13.5px/600, `accent` for flows, `danger` for frictions); face "11 on d16" (mono 12px); "Halvard rolled" (11.5px `inkSoft`).
  - Accept / reject lines stay normal event lines.
- **Undo:** shown on the facilitator's view for every open move, and on a player's view for their own moves (existing `MoveRecord.undoableBy`). It disappears once the junction is rolled.
- **Composer:**
  - Row: padding `8 12`, top border `line`, `paper` background.
  - Input: 13px, padding 7×10, 1px `edge`, radius 6, `panel` background, placeholder `Copy.messagePlaceholder`.
  - Enter sends; there is no button.
- **Clear log** (facilitator): unchanged, top right of the log.

### 5 · World tab (was Cast, `View/Entities.elm`)
- Sections "NPCS" and "LOCATIONS": a 10px label with 4px below, gap 14 between sections.
- Player row:
  - Padding `7 0`, bottom border `line`.
  - Name: 13px/600.
  - Notes: 15px→**14px**, `inkSoft`, lh 1.35.
- Facilitator rows keep their inputs and Delete. Restyle the inputs to 1px `edge`, radius 5, 13px.

### 6 · Guide (`View/Guide.elm`)
The Guide no longer lists the whole glossary. Every term stays available as a tooltip where it is used.

Decision to confirm with the owner: RULES.md calls `Copy/Terms.elm` the in-app glossary, and the Guide no longer renders all of it. A "See all terms" link to the old list is an option.

Three sections, gap 18:

1. **THE DIE**
   - Paragraph (14px, lh 1.4): "One die decides each junction. Boons step it up, banes step it down. It returns to the d10 when a junction is accepted."
   - **Odds bars:** one row per rung, gap 4.
     - Die label: mono 11px, 26px wide; the current die is bold.
     - Bar: fills the width, 10px tall, radius 2, 1px gaps between segments.
     - Segments, sized by `Copy.Terms.ladderOdds`: Critical Friction `danger`, Friction `dangerSoft`, Flow `accentSoft`, Critical Flow `accent`.
     - Row tooltip, e.g. "d16: Critical Friction 12.5% · Friction 12.5% · Flow 62.5% · Critical Flow 12.5%".
   - **Legend:** 2-column grid, 11px `inkSoft`, 8×8 swatches, indented 34px.
     - "Critical Friction · 1–2"
     - "Friction · 3–4"
     - "Flow · 5 and up"
     - "Critical Flow · top two"
2. **MOVES:** grid `92px 1fr auto`, gap 8, row padding `6 0`, bottom border `line`.
   - Name: 12.5px/600. Effect: 13.5px. Cost: 11.5px `accent`, with a tooltip.
   - Rows:
     - **Highlight:** "Make one of your aspects matter. The die steps up." · `☼` (1 boon)
     - **Highlight Context:** "Use a context aspect once. Boon steps up, bane steps down." · `free`
     - **Complicate:** "Your aspect drags you into trouble. Gain two boons; a bane appears." · `+☼☼` (gain 2 boons)
     - **Create:** "Make something true about the scene, a context boon in your words." · `☼`
     - **Alter:** "After a roll, reroll on the same die. Once per junction." · `☼☼`
3. **A JUNCTION:** four steps. Number in mono 11px `inkSoft`, 12px wide; text 12.5px with a bold lead word.
   1. **Prepare.** Make moves and play the scene. Moves can be undone.
   2. **Roll.** Anyone rolls the die. Moves lock.
   3. **Alter.** The only move left after the roll.
   4. **Resolve.** The facilitator accepts or rejects. Accepting resets to d10.

---

## Interactions and behaviour
- **Hover:** tabs and context rows wash to `tint`. Ghost buttons, step buttons and ✎ turn `accent`. Remove (×) and Reject turn `danger`. Primary buttons go to `ink`. No animations beyond the existing 120ms label fade on the split button.
- **Disabled:** controls carry no `onPress`, keep their tooltip reason, and draw at reduced emphasis (`inkSoft` text, or opacity .4 on the primary Create).
- **Every glyph** sits next to a word or has a tooltip. Keep it that way.
- **Touch:** unchanged. The split halves keep their resting tint, and the Guide is the path to the glosses.

## State management
- **Tool strip.** Merge `toolTab` and `selectedSlot` into one selection, so the strip has one selected item:
  `type ToolTab = SheetTab Int | WorldTab | GuideTab`
  `SelectSlot` becomes `SelectTool (SheetTab slot)`. Default to the viewer's own slot, otherwise slot 0.
- **Facilitator Add pill:** existing `newContextAspectKind`.
- No other new state. Role, junction and undo logic are unchanged.

## Copy changes (`Copy.elm`)
- `castTabLabel` → "World"; `castTabTip` → "NPCs & locations"
- **new** `rollButton die = "Roll " ++ die`
- `youMarker` → render as a separate "you" suffix
- **new** `ownerPlayedBy name = "Played by " ++ name`
- **new** `contextCount open consumed`, e.g. "4 open · 1 consumed"
- **new** `createCost = "costs ☼"`; facilitator `"free"`
- **new** Guide strings: listed above.
- `conditionLabel` is no longer rendered.

## Assets
None besides the fonts: Atkinson Hyperlegible, IBM Plex Mono and Noto Sans Symbols 2, all OFL and all self-hosted. No icons or images; marks are Unicode (☼ ☽ ↑ ↓ ‹ › ✎ × ◈ ▾).

## Files
- `screenshots/`: 2× captures of the four states. `1-player-preparation.png`, `2-player-junction.png`, `3-facilitator-preparation.png`, `4-facilitator-junction.png`.
- `Table v2.dc.html`: the design reference. Open it with `support.js` in the same folder. Use the Tweaks panel for role and moment.
- `support.js`: the runtime the reference needs to open. Not for the app.

### Source modules touched
`client/index.html` · `Ui.elm` · `View.elm` · `View/TopBar.elm` · `View/Characters.elm` · `View/ContextAspects.elm` · `View/Log.elm` · `View/Entities.elm` · `View/Guide.elm` · `Copy.elm` · `Types.elm` (ToolTab)
