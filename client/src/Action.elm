module Action exposing (Action(..), Family(..), family, isPending)

{-| The mutations the UI guards against a double-click, as a type rather than as
strings (roadmap 25.4).

An `Action` names one request that can be in flight — "making a Highlight",
"stepping the die up". `Model.inflight` is the list of those currently awaiting
the Worker's acknowledgement; a control whose action is in it renders disabled
(`Ui.press`), and `Main.guard` refuses to start it twice. Because the actions
are constructors, a typo no longer compiles, and a result message clears its
whole `Family` at once instead of matching a key prefix.

It lives in its own module, not in `Effect`, because `Effect` imports `View` and
`View` needs `Action` — the other direction would be an import cycle.

-}

import Die
import MoveRecord


type Action
    = ClearingLog
    | ClaimingSlot
    | ReleasingSlot
    | MakingMove MoveRecord.Kind
    | UndoingMove String
    | RollingJunction
    | RerollingJunction
    | AcceptingJunction
    | RejectingJunction
    | SteppingDie Die.Direction
    | AddingContextAspect
    | DeletingContextAspect String
    | EditingContextAspect String
    | GrantingFate Int
    | CreatingNpc
    | CreatingLocation
    | DeletingEntity String
    | SavingGoal
    | StartingSession
    | EndingSession


{-| The group of actions one result message settles. A `MutationDone` names the
family it releases, so every in-flight action of that family clears when any
request of it comes back.
-}
type Family
    = MessageFamily
    | LogFamily
    | SlotFamily
    | MoveFamily
    | UndoFamily
    | JunctionFamily
    | DieFamily
    | ContextFamily
    | FateFamily
    | EntityFamily
    | SessionFamily


family : Action -> Family
family action =
    case action of
        ClearingLog ->
            LogFamily

        ClaimingSlot ->
            SlotFamily

        ReleasingSlot ->
            SlotFamily

        MakingMove _ ->
            MoveFamily

        UndoingMove _ ->
            UndoFamily

        RollingJunction ->
            JunctionFamily

        RerollingJunction ->
            JunctionFamily

        AcceptingJunction ->
            JunctionFamily

        RejectingJunction ->
            JunctionFamily

        SteppingDie _ ->
            DieFamily

        AddingContextAspect ->
            ContextFamily

        DeletingContextAspect _ ->
            ContextFamily

        EditingContextAspect _ ->
            ContextFamily

        GrantingFate _ ->
            FateFamily

        CreatingNpc ->
            EntityFamily

        CreatingLocation ->
            EntityFamily

        DeletingEntity _ ->
            EntityFamily

        SavingGoal ->
            SessionFamily

        StartingSession ->
            SessionFamily

        EndingSession ->
            SessionFamily


isPending : Action -> List Action -> Bool
isPending action inflight =
    List.member action inflight
