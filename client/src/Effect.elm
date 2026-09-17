module Effect exposing (Effect(..), perform)

{-| A description of a side effect, kept separate from the `Cmd` that carries it
out.

`update` returns `( Model, Effect )` instead of `( Model, Cmd Msg )`, so it is a
pure function whose result a test can pattern-match on without going near `Http`,
`Task`, or the ports. `perform` is the single place an `Effect` turns into a real
`Cmd`, called once at the `Main` boundary.

Each constructor names a "what"; `Api` and `Ports` keep the "how". The `Post*`
effects all carry the `Auth` they need, so `update` still decides whether the
user is authorised — `perform` only translates.

-}

import Api
import Browser.Dom
import Http
import Kind exposing (AbilityKind)
import Ports
import Process
import Roll exposing (Stone)
import Task
import Time
import Types exposing (Auth, CharacterSheet, EntityKind, Flags, Msg(..), TableEntity)
import View


type Effect
    = None
    | Batch (List Effect)
      -- Interop / tasks with no backend call
    | Authorize
    | GetTimeZone
    | ScrollLogToBottom
    | RetryGetGameStateIn Float
    | DismissErrorIn Float
    | DebounceFieldSave Int Float
    | DebouncePledge Int Float
      -- Reads
    | GetGameState Auth
    | GetMessageHistory Auth Int
      -- Mutations (204-only; the result arrives on the socket)
    | PostMessage Auth String
    | PostClearMessages Auth
    | PostStones Auth String
    | PostCommitBoon Auth Int
    | PostFate Auth Int Int
    | PostCharacterUpdate Auth Int CharacterSheet
    | PostClaimSlot Auth Int
    | PostReleaseSlot Auth Int
    | PostProposalDecision Auth String String (Maybe String)
    | PostWithdrawProposal Auth String
    | PostUseAbility Auth AbilityKind
    | PostSuggestCompel Auth Int
    | PostAcceptCompelMove Auth
    | PostUseFloatingBoon Auth String
    | PostAddStone Auth Stone
    | PostRemoveStone Auth Stone
    | PostAddFloatingBoon Auth String
    | PostDeleteFloatingBoon Auth String
    | PostStartSession Auth String
    | PostSessionGoal Auth String
    | PostEndSession Auth
    | PostCreateEntity Auth EntityKind
    | PostUpdateEntity Auth EntityKind TableEntity
    | PostDeleteEntity Auth EntityKind String


{-| Realise an `Effect` as a `Cmd`. The only impure function in the update path.
-}
perform : Flags -> Effect -> Cmd Msg
perform flags effect =
    case effect of
        None ->
            Cmd.none

        Batch effects ->
            Cmd.batch (List.map (perform flags) effects)

        Authorize ->
            Ports.authorize [ "identify" ]

        GetTimeZone ->
            Task.perform GotTimeZone Time.here

        ScrollLogToBottom ->
            Browser.Dom.setViewportOf View.logDomId 0 1.0e7
                |> Task.attempt (\_ -> NoOp)

        RetryGetGameStateIn ms ->
            Process.sleep ms |> Task.perform (\_ -> RetryGetGameState)

        DismissErrorIn ms ->
            Process.sleep ms |> Task.perform (\_ -> DismissError)

        DebounceFieldSave seq ms ->
            Process.sleep ms |> Task.perform (\_ -> FieldSaveDue seq)

        DebouncePledge seq ms ->
            Process.sleep ms |> Task.perform (\_ -> PledgeDue seq)

        GetGameState auth ->
            Api.getGameState flags auth GotGameState

        GetMessageHistory auth before ->
            Api.getMessageHistory flags auth before GotEarlierMessages

        PostMessage auth content ->
            Api.postMessage flags auth content messagePosted

        PostClearMessages auth ->
            Api.postClearMessages flags auth logCleared

        PostStones auth path ->
            Api.postStones flags auth path stonesUpdated

        PostCommitBoon auth delta ->
            Api.postCommitBoon flags auth delta stonesUpdated

        PostFate auth slot delta ->
            Api.postFate flags auth slot delta characterUpdated

        PostCharacterUpdate auth slot character ->
            Api.postCharacterUpdate flags auth slot character characterUpdated

        PostClaimSlot auth slot ->
            Api.postClaimSlot flags auth slot slotClaimed

        PostReleaseSlot auth slot ->
            Api.postReleaseSlot flags auth slot slotClaimed

        PostProposalDecision auth id decision context ->
            Api.postProposalDecision flags auth id decision context (ProposalResolved id)

        PostWithdrawProposal auth id ->
            Api.postWithdrawProposal flags auth id (ProposalResolved id)

        PostUseAbility auth kind ->
            Api.postUseAbility flags auth (Kind.abilityToString kind) moveRaised

        PostSuggestCompel auth targetSlot ->
            Api.postSuggestCompel flags auth targetSlot moveRaised

        PostAcceptCompelMove auth ->
            Api.postAcceptCompelMove flags auth moveRaised

        PostUseFloatingBoon auth floatingId ->
            Api.postUseFloatingBoon flags auth floatingId moveRaised

        PostAddStone auth stone ->
            Api.postAddStone flags auth stone stonesUpdated

        PostRemoveStone auth stone ->
            Api.postRemoveStone flags auth stone stonesUpdated

        PostAddFloatingBoon auth text ->
            Api.postAddFloatingBoon flags auth text stonesUpdated

        PostDeleteFloatingBoon auth floatingId ->
            Api.postDeleteFloatingBoon flags auth floatingId stonesUpdated

        PostStartSession auth goal ->
            Api.postStartSession flags auth goal sessionUpdated

        PostSessionGoal auth goal ->
            Api.postSessionGoal flags auth goal sessionUpdated

        PostEndSession auth ->
            Api.postEndSession flags auth sessionUpdated

        PostCreateEntity auth kind ->
            Api.postCreateEntity flags auth kind entityMutated

        PostUpdateEntity auth kind entity ->
            Api.postUpdateEntity flags auth kind entity entityMutated

        PostDeleteEntity auth kind entityId ->
            Api.postDeleteEntity flags auth kind entityId entityMutated


{-| The result message for each family of acknowledge-only mutation. Each names
the in-flight key prefix `update` releases on the ack and the transient error to
show if the POST failed; `update` has a single `MutationDone` branch that reads
both off the record. `characterUpdated` uses the `"fate:"` family because the
Grant `+` / `−` is the only guarded character mutation — the debounced sheet
save is not in-flight-tracked.
-}
messagePosted : Result Http.Error () -> Msg
messagePosted =
    MutationDone { family = "message:", failMsg = "Failed to post message." }


logCleared : Result Http.Error () -> Msg
logCleared =
    MutationDone { family = "log:", failMsg = "Failed to clear the log." }


slotClaimed : Result Http.Error () -> Msg
slotClaimed =
    MutationDone { family = "slot:", failMsg = "Couldn't claim that character sheet." }


moveRaised : Result Http.Error () -> Msg
moveRaised =
    MutationDone { family = "move:", failMsg = "Couldn't raise that move." }


sessionUpdated : Result Http.Error () -> Msg
sessionUpdated =
    MutationDone { family = "session:", failMsg = "Failed to update the session." }


stonesUpdated : Result Http.Error () -> Msg
stonesUpdated =
    MutationDone { family = "stones:", failMsg = "Failed to update stones." }


characterUpdated : Result Http.Error () -> Msg
characterUpdated =
    MutationDone { family = "fate:", failMsg = "Failed to update character sheet." }


entityMutated : Result Http.Error () -> Msg
entityMutated =
    MutationDone { family = "entity:", failMsg = "Failed to update the table entry." }
