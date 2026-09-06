module Copy exposing (..)

{-| Every player-facing string the view renders, in one place so the game's
wording can be tuned without hunting through `View.*`. Grouped by the card it
appears on. Standalone strings are constants; strings with a value spliced in are
small functions that keep the whole phrase together.

Structural field labels that are not game vocabulary ("Name", "Notes") are left
inline in the view — the target here is the prose that expresses the game.

Section 21.2 adds the glossary `Term` list alongside these; 21.1 is the constants
only.
-}

import Format



-- STONE VOCABULARY — chip captions shared across cards


boonStone : String
boonStone =
    "Boon"


baneStone : String
baneStone =
    "Bane"


pledgedChip : String
pledgedChip =
    "Pledged"


floatingChip : String
floatingChip =
    "Floating"



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
    "Shared Table"


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



-- SESSION CARD (View/Session.elm)


sessionTitle : String
sessionTitle =
    "Session"


goalLabel : String
goalLabel =
    "Goal  "


sessionPool : String
sessionPool =
    "Session pool"


carryingBanes : Int -> String
carryingBanes n =
    "Carrying "
        ++ String.fromInt n
        ++ " "
        ++ Format.pluralize n "Bane"
        ++ " in from the last session"


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


pastSessions : String
pastSessions =
    "Past sessions"


verdictMet : String
verdictMet =
    "met"


verdictFailed : String
verdictFailed =
    "failed"


verdictPartial : String
verdictPartial =
    "partial"



-- UNTETHER BANNER (View/Session.elm)


untetheredHeadline : String -> String
untetheredHeadline who =
    who ++ " is untethered"


{-| `aspect` is the lowercased aspect name, e.g. "archetype". -}
untetheredExplanation : String -> String
untetheredExplanation aspect =
    " on their "
        ++ aspect
        ++ " — the reckoning resolves by the end of the following session, and afterward the aspect is rewritten or replaced."


resolveUntether : String
resolveUntether =
    "Resolve untether"



-- STONES CARD (View/Stones.elm)


stonesTitle : String
stonesTitle =
    "Stones"


reroll : String
reroll =
    "Reroll"


pressFate : String
pressFate =
    "Press Fate"


boonsCostSuffix : Int -> String
boonsCostSuffix n =
    " (" ++ String.fromInt n ++ " boons)"


bagOf : Int -> String
bagOf n =
    "Bag of " ++ String.fromInt n


floatingBoons : String
floatingBoons =
    "Floating boons"


floatingBoonRequested : String
floatingBoonRequested =
    "(requested)"


floatingBoonUse : String
floatingBoonUse =
    "Use"


addBoon : String
addBoon =
    "Add boon"


roll : String
roll =
    "Roll"


rolled : String
rolled =
    "Rolled"


accept : String
accept =
    "Accept"


overcomeWith : String -> String
overcomeWith who =
    "Overcome — " ++ who


callOffOvercome : String
callOffOvercome =
    "Call off"


startOvercome : String
startOvercome =
    "Start overcome"


proposalsTitle : String
proposalsTitle =
    "Proposals"


floatingBoonContextPlaceholder : String
floatingBoonContextPlaceholder =
    "Context this boon represents…"


reject : String
reject =
    "Reject"



-- PROPOSAL DESCRIPTIONS (View/Stones.elm describeProposal)


proposalAddBoon : String
proposalAddBoon =
    "add a boon to the pool"


proposalPledge : String
proposalPledge =
    "highlight an aspect (pledge a boon)"


proposalPledgeWithdraw : String
proposalPledgeWithdraw =
    "withdraw a highlighted boon"


proposalHelpOut : String
proposalHelpOut =
    "Help Out — reroll the overcome"


proposalAddDetail : String
proposalAddDetail =
    "Add a Detail — a floating boon"


proposalGainInsight : String
proposalGainInsight =
    "Gain Insight — a floating boon"


proposalSuggestCompelOn : String -> String
proposalSuggestCompelOn who =
    "Suggest Compel on " ++ who ++ " (+1 / +2 boons)"


proposalSuggestCompelFallback : String
proposalSuggestCompelFallback =
    "another character"


proposalAcceptCompel : String
proposalAcceptCompel =
    "Accept Compel — take a complication for 2 boons"


proposalUseFloating : String
proposalUseFloating =
    "spend a floating boon on the roll"



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


helpOut : String
helpOut =
    "Help Out"


addDetail : String
addDetail =
    "Add a Detail"


gainInsight : String
gainInsight =
    "Gain Insight"


suggestCompel : String
suggestCompel =
    "Suggest Compel"


usedSuffix : String
usedSuffix =
    " (used)"


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


untetheredAspectFlag : String
untetheredAspectFlag =
    "untethered — rewrite or replace this aspect"


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
