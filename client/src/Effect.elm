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

import Action exposing (Family(..))
import Api
import Aspect exposing (Aspect)
import Browser.Dom
import ContextAspect exposing (Polarity)
import Die
import Http
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
    | Focus String
      -- Reads
    | GetGameState Auth
    | GetMessageHistory Auth Int
      -- Mutations (204-only; the result arrives on the socket)
    | PostMessage Auth String
    | PostClearMessages Auth
    | PostJunctionRoll Auth
    | PostJunctionReroll Auth
    | PostJunctionAccept Auth
    | PostJunctionReject Auth
    | PostStepDie Auth Die.Direction
    | PostHighlight Auth Aspect
    | PostHighlightContext Auth String
    | PostComplicate Auth Aspect
    | PostCreate Auth String
    | PostAlter Auth
    | PostUndo Auth String
    | PostFate Auth Int Int
    | PostCharacterUpdate Auth Int CharacterSheet
    | PostClaimSlot Auth Int
    | PostReleaseSlot Auth Int
    | PostAddContextAspect Auth Polarity String
    | PostDeleteContextAspect Auth String
    | PostUpdateContextAspect Auth String String
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

        Focus domId ->
            Browser.Dom.focus domId |> Task.attempt (\_ -> NoOp)

        GetGameState auth ->
            Api.getGameState flags auth GotGameState

        GetMessageHistory auth before ->
            Api.getMessageHistory flags auth before GotEarlierMessages

        PostMessage auth content ->
            Api.postMessage flags auth content messagePosted

        PostClearMessages auth ->
            Api.postClearMessages flags auth logCleared

        PostJunctionRoll auth ->
            Api.postJunction flags auth "roll" junctionUpdated

        PostJunctionReroll auth ->
            Api.postJunction flags auth "reroll" junctionUpdated

        PostJunctionAccept auth ->
            Api.postJunction flags auth "accept" junctionUpdated

        PostJunctionReject auth ->
            Api.postJunction flags auth "reject" junctionUpdated

        PostStepDie auth direction ->
            Api.postStepDie flags auth direction dieStepped

        PostHighlight auth aspect ->
            Api.postHighlight flags auth aspect moveMade

        PostHighlightContext auth contextAspectId ->
            Api.postHighlightContext flags auth contextAspectId moveMade

        PostComplicate auth aspect ->
            Api.postComplicate flags auth aspect moveMade

        PostCreate auth text ->
            Api.postCreate flags auth text moveMade

        PostAlter auth ->
            Api.postAlter flags auth moveMade

        PostUndo auth moveId ->
            Api.postUndo flags auth moveId moveUndone

        PostFate auth slot delta ->
            Api.postFate flags auth slot delta characterUpdated

        PostCharacterUpdate auth slot character ->
            Api.postCharacterUpdate flags auth slot character characterUpdated

        PostClaimSlot auth slot ->
            Api.postClaimSlot flags auth slot slotClaimed

        PostReleaseSlot auth slot ->
            Api.postReleaseSlot flags auth slot slotClaimed

        PostAddContextAspect auth kind text ->
            Api.postAddContextAspect flags auth kind text contextUpdated

        PostDeleteContextAspect auth contextAspectId ->
            Api.postDeleteContextAspect flags auth contextAspectId contextUpdated

        PostUpdateContextAspect auth contextAspectId text ->
            Api.postUpdateContextAspect flags auth contextAspectId text contextUpdated

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
the in-flight `Action.Family` `update` releases on the ack and the transient error to
show if the POST failed; `update` has a single `MutationDone` branch that reads
both off the record. `characterUpdated` uses the `FateFamily` because the
Grant `+` / `−` is the only guarded character mutation — the debounced sheet
save is not in-flight-tracked.
-}
messagePosted : Result Http.Error () -> Msg
messagePosted =
    MutationDone { family = MessageFamily, failMsg = "Failed to post message." }


logCleared : Result Http.Error () -> Msg
logCleared =
    MutationDone { family = LogFamily, failMsg = "Failed to clear the log." }


slotClaimed : Result Http.Error () -> Msg
slotClaimed =
    MutationDone { family = SlotFamily, failMsg = "Couldn't claim that character sheet." }


moveMade : Result Http.Error () -> Msg
moveMade =
    MutationDone { family = MoveFamily, failMsg = "Couldn't make that move." }


moveUndone : Result Http.Error () -> Msg
moveUndone =
    MutationDone { family = UndoFamily, failMsg = "Couldn't undo that move." }


junctionUpdated : Result Http.Error () -> Msg
junctionUpdated =
    MutationDone { family = JunctionFamily, failMsg = "Couldn't update the Junction." }


sessionUpdated : Result Http.Error () -> Msg
sessionUpdated =
    MutationDone { family = SessionFamily, failMsg = "Failed to update the session." }


dieStepped : Result Http.Error () -> Msg
dieStepped =
    MutationDone { family = DieFamily, failMsg = "Couldn't step the die." }


contextUpdated : Result Http.Error () -> Msg
contextUpdated =
    MutationDone { family = ContextFamily, failMsg = "Failed to update the context aspects." }


characterUpdated : Result Http.Error () -> Msg
characterUpdated =
    MutationDone { family = FateFamily, failMsg = "Failed to update character sheet." }


entityMutated : Result Http.Error () -> Msg
entityMutated =
    MutationDone { family = EntityFamily, failMsg = "Failed to update the table entry." }
