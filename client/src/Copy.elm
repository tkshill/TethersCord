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

import Types exposing (Aspect(..))



-- STONE VOCABULARY — chip captions shared across cards


boonStone : String
boonStone =
    "Boon"


baneStone : String
baneStone =
    "Bane"


-- OVERCOME STAGE (View/TopBar.elm, roadmap 26.3)


overcome : String
overcome =
    "Overcome"


thePool : String
thePool =
    "the pool"


overcomeDrew : String -> String
overcomeDrew who =
    who ++ " drew"


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


waitingForFacilitator : String
waitingForFacilitator =
    "Waiting for the facilitator…"



-- SHARED CONTROLS


withdraw : String
withdraw =
    "withdraw"



-- SHELL — header, connection notes, composer (View.elm)


loadingTable : String
loadingTable =
    "Loading the table…"


appTitle : String
appTitle =
    "Tethers"


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


send : String
send =
    "Send"



-- TOP BAR (View/TopBar.elm) — the running session's goal and the shared
-- stone pool, both moved off the old Session / Stones cards by roadmap
-- section 23.6. Session start / end / goal-edit sit behind the bar's
-- expander so it stays one line at rest.


goalLabel : String
goalLabel =
    "Goal: "


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


bagOf : Int -> String
bagOf n =
    String.fromInt n ++ " in the pool"



-- SESSION HISTORY CARD (View/Session.elm) — all that is left of the old
-- Session card once its goal and controls move to the top bar (23.6).


sessionHistoryTitle : String
sessionHistoryTitle =
    "Session history"



-- SESSION BOONS & BANES CARD (View/SessionAspects.elm)


sessionAspectsTitle : String
sessionAspectsTitle =
    "Session boons & banes"


{-| The mark on a session boon or bane that has been spent into the pool. It
stays on the table, visibly consumed, and cannot be spent again.
-}
sessionAspectConsumed : String
sessionAspectConsumed =
    "used"


{-| Facilitator-only: clear a consumed mark, to correct a table miscommunication.
-}
sessionAspectUnconsume : String
sessionAspectUnconsume =
    "Unconsume"


sessionAspectUse : String
sessionAspectUse =
    "Use"


{-| Facilitator-only: remove a session boon or bane outright.
-}
sessionAspectRemove : String
sessionAspectRemove =
    "Remove"


{-| Facilitator-only: the field and button that plant a session boon or bane
directly, below the existing ones.
-}
addSessionAspectPlaceholder : String
addSessionAspectPlaceholder =
    "Add a session boon or bane…"


addSessionAspect : String
addSessionAspect =
    "Add"



-- FACILITATOR PANEL (View/FacilitatorPanel.elm) — direct pool edits and the
-- queue of proposals awaiting a decision, in their own facilitator-only section
-- of the left panel. The Overcome controls are on the top bar's stage.


facilitatorPanelTitle : String
facilitatorPanelTitle =
    "Facilitator"


accept : String
accept =
    "Accept"


proposalsTitle : String
proposalsTitle =
    "Proposals"


sessionAspectContextPlaceholder : String
sessionAspectContextPlaceholder =
    "Wording for the session boon…"


reject : String
reject =
    "Reject"



-- PROPOSAL DESCRIPTIONS (View/FacilitatorPanel.elm describeProposal)


proposalHighlight : String
proposalHighlight =
    "Highlight — pays 1 boon, the pool gains a Boon"


proposalAlter : String
proposalAlter =
    "Alter Fate — pays 2 boons, rerolls the Overcome"


proposalAddDetail : String
proposalAddDetail =
    "Add Detail — pays 1 boon, makes a session boon"


proposalComplicateOn : String -> String
proposalComplicateOn who =
    "Complicate " ++ who ++ " — they gain 2 boons"


proposalComplicateFallback : String
proposalComplicateFallback =
    "another character"


proposalUseSessionBoon : String -> String
proposalUseSessionBoon note =
    "Use Session Boon — " ++ note ++ "; the pool gains a Boon"


proposalUseSessionBoonGone : String
proposalUseSessionBoonGone =
    "a session boon that is gone"


{-| The header note beside the Facilitator accordion title: how many proposals
are waiting, so a collapsed panel still signals that one is.
-}
proposalsWaiting : Int -> String
proposalsWaiting n =
    String.fromInt n ++ " waiting"



-- MOVES CARD (View/Moves.elm)


movesTitle : String
movesTitle =
    "Moves"


{-| The Moves accordion's header note: the viewer's own boons, the currency the
moves are paid in.
-}
movesBoons : Int -> String
movesBoons n =
    case n of
        1 ->
            "1 boon"

        _ ->
            String.fromInt n ++ " boons"


highlightBlurb : String
highlightBlurb =
    "Pay 1 boon: an aspect shapes the outcome, and the pool gains a Boon."


highlightButton : String
highlightButton =
    "Highlight"


complicateBlurb : String
complicateBlurb =
    "Suggest a complication for another character. Their player gains 2 boons."


addDetailBlurb : String
addDetailBlurb =
    "Pay 1 boon to establish something true about the scene: suggest it, or leave it blank and ask the facilitator."


addDetailPlaceholder : String
addDetailPlaceholder =
    "Suggest a detail, or leave blank to ask for one…"


addDetailButton : String
addDetailButton =
    "Add Detail"


alterBlurb : String
alterBlurb =
    "Pay 2 boons to reroll the Overcome. Once per Overcome."


alterButton : String
alterButton =
    "Alter Fate"


alterNeedsBoons : String
alterNeedsBoons =
    "You need 2 boons."


alterAlreadyUsed : String
alterAlreadyUsed =
    "You have already altered fate this Overcome."


alterAlreadyProposed : String
alterAlreadyProposed =
    "An Alter Fate is already waiting for the facilitator."


needsABoon : String
needsABoon =
    "You need a boon."


useSessionBoonBlurb : String
useSessionBoonBlurb =
    "Spend a session boon: the pool gains a Boon."


useButton : String
useButton =
    "Use"


noSessionBoons : String
noSessionBoons =
    "No unspent session boons."


noOtherPlayers : String
noOtherPlayers =
    "no other players"


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


logTitle : String
logTitle =
    "Log"



-- RIGHT PANEL TABS (View.elm) — roadmap section 24. `logTitle` above doubles
-- as the Log tab's label; these two are new, standing for the cards each tab
-- combines.


npcsLocationsTabLabel : String
npcsLocationsTabLabel =
    "NPCs & Locations"


sessionContextTabLabel : String
sessionContextTabLabel =
    "Session boons & banes"


guideTabLabel : String
guideTabLabel =
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
