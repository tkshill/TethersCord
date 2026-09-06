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
import Ports
import Process
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
    | PostUseAbility Auth String
    | PostSuggestCompel Auth Int
    | PostAcceptCompelMove Auth
    | PostUseFloatingBoon Auth String
    | PostStartSession Auth String
    | PostSessionGoal Auth String
    | PostEndSession Auth
    | PostStartOvercome Auth Int
    | PostCancelOvercome Auth
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
            Api.postMessage flags auth content MessagePosted

        PostClearMessages auth ->
            Api.postClearMessages flags auth LogCleared

        PostStones auth path ->
            Api.postStones flags auth path StonesUpdated

        PostCommitBoon auth delta ->
            Api.postCommitBoon flags auth delta StonesUpdated

        PostFate auth slot delta ->
            Api.postFate flags auth slot delta CharacterUpdated

        PostCharacterUpdate auth slot character ->
            Api.postCharacterUpdate flags auth slot character CharacterUpdated

        PostClaimSlot auth slot ->
            Api.postClaimSlot flags auth slot SlotClaimed

        PostReleaseSlot auth slot ->
            Api.postReleaseSlot flags auth slot SlotClaimed

        PostProposalDecision auth id decision context ->
            Api.postProposalDecision flags auth id decision context (ProposalResolved id)

        PostWithdrawProposal auth id ->
            Api.postWithdrawProposal flags auth id (ProposalResolved id)

        PostUseAbility auth kind ->
            Api.postUseAbility flags auth kind MoveRaised

        PostSuggestCompel auth targetSlot ->
            Api.postSuggestCompel flags auth targetSlot MoveRaised

        PostAcceptCompelMove auth ->
            Api.postAcceptCompelMove flags auth MoveRaised

        PostUseFloatingBoon auth floatingId ->
            Api.postUseFloatingBoon flags auth floatingId MoveRaised

        PostStartSession auth goal ->
            Api.postStartSession flags auth goal SessionUpdated

        PostSessionGoal auth goal ->
            Api.postSessionGoal flags auth goal SessionUpdated

        PostEndSession auth ->
            Api.postEndSession flags auth SessionUpdated

        PostStartOvercome auth slot ->
            Api.postStartOvercome flags auth slot OvercomeUpdated

        PostCancelOvercome auth ->
            Api.postCancelOvercome flags auth OvercomeUpdated

        PostCreateEntity auth kind ->
            Api.postCreateEntity flags auth kind EntityMutated

        PostUpdateEntity auth kind entity ->
            Api.postUpdateEntity flags auth kind entity EntityMutated

        PostDeleteEntity auth kind entityId ->
            Api.postDeleteEntity flags auth kind entityId EntityMutated
