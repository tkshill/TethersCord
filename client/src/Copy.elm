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


highlightedChip : String
highlightedChip =
    "Highlighted"


sessionAspectChip : String
sessionAspectChip =
    "Session"



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
    "Goal  "


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
    "Bag of " ++ String.fromInt n



-- SESSION HISTORY CARD (View/Session.elm) — all that is left of the old
-- Session card once its goal and controls move to the top bar (23.6).


sessionHistoryTitle : String
sessionHistoryTitle =
    "Session history"



-- SESSION ASPECTS CARD (View/SessionAspects.elm) — the session boons and banes list,
-- renamed and moved to the centre column by roadmap section 23.5, as 23.3
-- anticipated.


sessionAspectsTitle : String
sessionAspectsTitle =
    "Session boons & banes"


sessionAspectRequested : String
sessionAspectRequested =
    "(requested)"


sessionAspectUse : String
sessionAspectUse =
    "Use"


{-| Facilitator-only: remove a session context outright (23.2).
-}
sessionAspectRemove : String
sessionAspectRemove =
    "Remove"


{-| Facilitator-only: the field and button that plant a session context
directly (23.2), below the existing session aspects.
-}
addSessionAspectPlaceholder : String
addSessionAspectPlaceholder =
    "Add a session boon or bane…"


addSessionAspect : String
addSessionAspect =
    "Add"



-- FACILITATOR PANEL (View/FacilitatorPanel.elm) — the one-click draw (23.1),
-- direct pool edits (23.2), and the proposal queue, grouped into their own
-- facilitator-only panel in the left column by roadmap section 23.5.


facilitatorPanelTitle : String
facilitatorPanelTitle =
    "Facilitator"


draw : String
draw =
    "Draw two stones"


{-| Player-facing "Add boon" is disconnected (23.2) — the facilitator hand-edits
the pool directly now — but the underlying proposal it posted is untouched, so
the string stays for whenever that's re-wired.
-}
addBoon : String
addBoon =
    "Add boon"


accept : String
accept =
    "Accept"


proposalsTitle : String
proposalsTitle =
    "Proposals"


sessionAspectContextPlaceholder : String
sessionAspectContextPlaceholder =
    "Context this boon represents…"


reject : String
reject =
    "Reject"



-- PROPOSAL DESCRIPTIONS (View/FacilitatorPanel.elm describeProposal)


proposalAddBoon : String
proposalAddBoon =
    "add a boon to the pool"


proposalHighlight : String
proposalHighlight =
    "highlight an aspect (adds a boon to the pool)"


proposalHighlightWithdraw : String
proposalHighlightWithdraw =
    "withdraw a highlighted boon"


proposalAlter : String
proposalAlter =
    "Alter Fate — pay two boons to resolve the fork with an alternate action"


proposalAddDetail : String
proposalAddDetail =
    "Add Detail — a session boon"


proposalGainInsight : String
proposalGainInsight =
    "Gain Insight — a session boon"


proposalComplicateOn : String -> String
proposalComplicateOn who =
    "Complicate " ++ who ++ " (+1 / +2 boons)"


proposalComplicateFallback : String
proposalComplicateFallback =
    "another character"


proposalAcceptCompel : String
proposalAcceptCompel =
    "Accept Compel — take a complication for 2 boons"


proposalUseSessionBoon : String
proposalUseSessionBoon =
    "spend a session boon on the roll"



-- MOVES CARD (View/Moves.elm)


movesTitle : String
movesTitle =
    "Moves"


anyTime : String
anyTime =
    "Any time"


acceptCompel : String
acceptCompel =
    "Accept Compel"


abilitiesNeedSession : String
abilitiesNeedSession =
    "Abilities open once a session is running."


oncePerSession : String
oncePerSession =
    "Once per session"


alter : String
alter =
    "Alter Fate"


addDetail : String
addDetail =
    "Add Detail"


gainInsight : String
gainInsight =
    "Gain Insight"


complicate : String
complicate =
    "Complicate"


usedSuffix : String
usedSuffix =
    " (used)"


{-| The Moves card's collapsed-accordion summary (roadmap section 24, the 1c
layout variant): how many of the four once-per-session-or-fewer abilities
(Alter, Add Detail, Gain Insight, Complicate) are still unused.
-}
movesRemainingSummary : Int -> Int -> String
movesRemainingSummary remaining total =
    String.fromInt remaining ++ " of " ++ String.fromInt total ++ " left"


pendingSuffix : String
pendingSuffix =
    " (pending)"


noOtherPlayers : String
noOtherPlayers =
    "no other players"



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


highlight : String
highlight =
    "Highlight"



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
    "Session context"


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
