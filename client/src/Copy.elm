module Copy exposing (..)

{-| Every player-facing string the view renders, in one place so the game's
wording can be tuned without hunting through `View.*`. Grouped by the card it
appears on. Standalone strings are constants; strings with a value spliced in are
small functions that keep the whole phrase together.

Structural field labels that are not game vocabulary ("Name", "Notes") are left
inline in the view — the target here is the prose that expresses the game.

The glossary `Term` list lives next door in `Copy.Terms`; `aspectExamples` here
is the character-creation prompt list, a curated subset of `ASPECTS.md`.

-}

import Aspect exposing (Aspect(..))
import ContextAspect exposing (Polarity(..))



-- STONE VOCABULARY — chip captions shared across cards


boonStone : String
boonStone =
    "Boon"


baneStone : String
baneStone =
    "Bane"


-- JUNCTION STAGE (View/TopBar.elm, roadmap 26.3)


junction : String
junction =
    "Junction"


junctionRolled : String -> String
junctionRolled who =
    who ++ " rolled"


{-| The pending roll beside the ladder: `Flow · 7`.
-}
rollResult : String -> Int -> String
rollResult outcome face =
    outcome ++ " · " ++ String.fromInt face


{-| The current rung's tooltip while it is the roll button.
-}
rollTip : String -> String
rollTip die =
    "Roll the Junction on the " ++ die


stepUpTip : String
stepUpTip =
    "Step the die up a rung"


stepDownTip : String
stepDownTip =
    "Step the die down a rung"


alterTip : String
alterTip =
    "Alter: pay 2 boons to reroll on the same die, once this Junction"


{-| What Alter costs, in boons (RULES.md "Moves"); the Worker checks it too.
-}
alterCost : Int
alterCost =
    2


rerollsNote : Int -> String
rerollsNote n =
    case n of
        0 ->
            "no rerolls"

        1 ->
            "1 reroll"

        _ ->
            String.fromInt n ++ " rerolls"


rerollButton : String
rerollButton =
    "Reroll"



-- SHARED CONTROLS


undo : String
undo =
    "undo"



-- SHELL — header, connection notes, composer (View.elm)


loadingTable : String
loadingTable =
    "Loading the table…"


reconnecting : String
reconnecting =
    "Reconnecting to the table…"


connectionLost : String
connectionLost =
    "Connection lost. Reload the Activity to reconnect."


sessionRejected : String
sessionRejected =
    "Session rejected — reload the Activity to sign in again."


waitingForAuth : String
waitingForAuth =
    "Waiting for authentication…"


messagePlaceholder : String
messagePlaceholder =
    "Write a message…"



-- TOP BAR (View/TopBar.elm) — the running session's goal and the shared
-- stone pool, both moved off the old Session / Stones cards by roadmap
-- section 23.6. Session start / end / goal-edit sit behind the bar's
-- expander so it stays one line at rest.


endSession : String
endSession =
    "End session"


sessionGoalPlaceholder : String
sessionGoalPlaceholder =
    "Session goal…"


startSession : String
startSession =
    "Start session"


noSessionRunning : String
noSessionRunning =
    "No session running."


saveGoal : String
saveGoal =
    "Save goal"


{-| The status strip's tooltip over the die. -}
dieTip : String -> String
dieTip die =
    "The die: the next Junction rolls a " ++ die


{-| The strip's tooltip on the running goal for the facilitator, who can click
it to open the session controls. -}
goalTip : String
goalTip =
    "Session goal — click to edit"



-- SESSION HISTORY CARD (View/Session.elm) — all that is left of the old
-- Session card once its goal and controls move to the top bar (23.6).


sessionHistoryTitle : String
sessionHistoryTitle =
    "Session history"



-- SESSION BOONS & BANES CARD (View/ContextAspects.elm)


noContextAspects : String
noContextAspects =
    "No context boons or banes yet."


{-| The mark on a context boon or bane that has been highlighted. It stays on
the table, visibly consumed, and cannot be highlighted again.
-}
contextAspectConsumed : String
contextAspectConsumed =
    "used"


{-| Facilitator-only: remove a context boon or bane outright.
-}
contextAspectRemove : String
contextAspectRemove =
    "Remove"


{-| Facilitator-only: the field and button that plant a context boon or bane
directly, below the existing ones.
-}
addContextAspectPlaceholder : String
addContextAspectPlaceholder =
    "Add a context boon or bane…"


addContextAspect : String
addContextAspect =
    "Add"



-- JUNCTION CONTROLS (View/TopBar.elm) — the facilitator's accept / reject.


accept : String
accept =
    "Accept"


reject : String
reject =
    "Reject"




-- MOVES — the aspect split buttons (View/Characters.elm), Highlight Context
-- and Create (View/ContextAspects.elm), Alter (View/TopBar.elm).


createPlaceholder : String
createPlaceholder =
    "Something true about the scene, or leave blank…"


createButton : String
createButton =
    "Create"


alterButton : String
alterButton =
    "Alter"


alterNeedsBoons : String
alterNeedsBoons =
    "You need 2 boons."


alterAlreadyUsed : String
alterAlreadyUsed =
    "You have already altered this Junction."


needsABoon : String
needsABoon =
    "You need a boon."


{-| Why the preparation moves are off: the junction has been rolled.
-}
movesLocked : String
movesLocked =
    "Moves are locked once the Junction is rolled."


dieAtTop : String
dieAtTop =
    "The die is already at the top of the ladder."


dieAtEnd : String
dieAtEnd =
    "The die is already at that end of the ladder."


{-| A context aspect's tooltip while it can be highlighted.
-}
highlightContextTip : Polarity -> String
highlightContextTip polarity =
    case polarity of
        Boon ->
            "Highlight Context: the die steps up, and this boon is consumed"

        Bane ->
            "Highlight Context: the die steps down, and this bane is consumed"


contextAspectConsumedTip : String
contextAspectConsumedTip =
    "Consumed: its one use is spent"


contextAspectWordingPlaceholder : String
contextAspectWordingPlaceholder =
    "Word this context aspect…"


{-| A Complicate's bane before the facilitator words it.
-}
unwordedFrom : String -> String -> String
unwordedFrom character aspect =
    "Trouble from " ++ character ++ "'s " ++ aspect ++ " — to be worded"


unworded : String
unworded =
    "To be worded"


createTip : String
createTip =
    "Create: pay 1 boon to make something true about the scene, a context boon in your words"


contextBoonToggleTip : String
contextBoonToggleTip =
    "Add a context boon"


contextBaneToggleTip : String
contextBaneToggleTip =
    "Add a context bane"


editTip : String
editTip =
    "Edit"


{-| The two halves of a character aspect's split button.
-}
highlightHalf : String
highlightHalf =
    "Highlight ☼"


complicateHalf : String
complicateHalf =
    "☽ Complicate"


highlightTip : String
highlightTip =
    "Highlight: pay 1 boon to make this aspect matter — the die steps up"


complicateTip : String
complicateTip =
    "Complicate: this aspect drags you into trouble — gain 2 boons, and a context bane appears"


claimASheetForMoves : String
claimASheetForMoves =
    "Claim a character sheet to use moves."


-- CHARACTERS CARD (View/Characters.elm)


charactersTitle : String
charactersTitle =
    "Characters"


noCharacterSheets : String
noCharacterSheets =
    "No character sheets."


youMarker : String
youMarker =
    " (you)"


{-| Tab / label fallback for a sheet with no name yet. Mirrors the worker's
`characterLabel`. `slot` is zero-based, shown one-based.
-}
characterFallback : Int -> String
characterFallback slot =
    "Character " ++ String.fromInt (slot + 1)


ownerMine : String
ownerMine =
    "Your character"


ownerRelease : String
ownerRelease =
    "Release"


ownerUnclaimed : String
ownerUnclaimed =
    "Unclaimed"


ownerClaim : String
ownerClaim =
    "Claim"


ownerClaimed : String
ownerClaimed =
    "Claimed"


notableFeaturesLabel : String
notableFeaturesLabel =
    "Notable features"


conditionLabel : String
conditionLabel =
    "Condition"


boonsLabel : String
boonsLabel =
    "Boons"


boonsNone : String
boonsNone =
    "None"


grant : String
grant =
    "Grant"



-- ENTITY CARDS — NPCs / Locations (View/Entities.elm)


npcsTitle : String
npcsTitle =
    "NPCs"


npcSingular : String
npcSingular =
    "NPC"


locationsTitle : String
locationsTitle =
    "Locations"


locationSingular : String
locationSingular =
    "location"


noEntitiesYet : String -> String
noEntitiesYet title =
    "No " ++ title ++ " yet."


addEntity : String -> String
addEntity singular =
    "Add " ++ singular


entityDelete : String
entityDelete =
    "Delete"


entityUnnamed : String
entityUnnamed =
    "Unnamed"



-- LOG CARD (View/Log.elm)



-- TOOL STRIP (View.elm, roadmap section 27) — the label shown on the selected
-- glyph tab, and the tooltip on each unselected one.


sheetTabLabel : String
sheetTabLabel =
    "Sheet"


sheetTabTip : String
sheetTabTip =
    "Sheet, moves & session context"


castTabLabel : String
castTabLabel =
    "Cast"


castTabTip : String
castTabTip =
    "Cast & locations"


noCast : String
noCast =
    "The facilitator has not added any NPCs or locations yet."


contextTabLabel : String
contextTabLabel =
    "Context"


guideTabLabel : String
guideTabLabel =
    "Guide"


guideTabTip : String
guideTabTip =
    "How to play"


noMessages : String
noMessages =
    "No messages yet."


loadingEarlierMessages : String
loadingEarlierMessages =
    "Loading earlier messages…"


loadEarlierMessages : String
loadEarlierMessages =
    "Load earlier messages"


clearLog : String
clearLog =
    "Clear log"



-- ASPECT EXAMPLES (View/Characters.elm) — a curated subset of ASPECTS.md,
-- shown under "see examples" on each aspect field during character creation.


aspectExamplesLabel : String
aspectExamplesLabel =
    "see examples"


aspectExamplesHideLabel : String
aspectExamplesHideLabel =
    "hide examples"


aspectExamples : Aspect -> List String
aspectExamples aspect =
    case aspect of
        Archetype ->
            [ "The soldier who was told the war was over"
            , "Youngest heir of a house that no longer exists"
            , "The healer who is afraid of their own hands"
            , "The cartographer of a country being erased"
            , "The family disappointment, home again"
            , "Keeper of a shrine to a god that left"
            ]

        Desire ->
            [ "To be believed, just once, by the person who raised them"
            , "To go one season without owing anyone"
            , "To be the one who stays"
            , "To keep a promise they made to someone who is gone"
            , "To be forgiven without having to ask"
            , "To hold power long enough to give it away well"
            ]

        Quest ->
            [ "Get the last shipment across the border before the pass closes"
            , "Keep the lights on in the house until spring"
            , "Deliver the letter without reading it"
            , "Get the child to the coast and onto a boat"
            , "Hold the bridge until the others are across"
            , "Convince one more family to leave"
            ]
