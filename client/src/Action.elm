module Action exposing (Action(..), Decision(..), Family(..), family, isPending)

{-| The mutations the UI guards against a double-click, as a type rather than as
strings (roadmap 25.4).

An `Action` names one request that can be in flight — "resolving proposal `p1`",
"adding a Boon to the pool". `Model.inflight` is the list of those currently
awaiting the Worker's acknowledgement; a control whose action is in it renders
disabled (`Ui.press`), and `Main.guard` refuses to start it twice. Because the
actions are constructors, a typo no longer compiles, and a result message clears
its whole `Family` at once instead of matching a key prefix.

It lives in its own module, not in `Effect`, because `Effect` imports `View` and
`View` needs `Action` — the other direction would be an import cycle.

-}

import Kind exposing (ProposalKind)
import Roll exposing (Stone)


{-| Which way a queued proposal is being resolved.
-}
type Decision
    = Accepting
    | Rejecting
    | Withdrawing


type Action
    = ClearingLog
    | ClaimingSlot
    | ReleasingSlot
    | ResolvingProposal Decision String
    | RaisingMove ProposalKind
    | RollingOvercome
    | RerollingOvercome
    | AcceptingOvercome
    | RejectingOvercome
    | AddingStone Stone
    | RemovingStone Stone
    | AddingSessionAspect
    | DeletingSessionAspect String
    | UsingSessionAspect String
    | UnconsumingSessionAspect String
    | EditingSessionAspect String
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
    | ProposalFamily
    | MoveFamily
    | OvercomeFamily
    | StonesFamily
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

        ResolvingProposal _ _ ->
            ProposalFamily

        RaisingMove _ ->
            MoveFamily

        RollingOvercome ->
            OvercomeFamily

        RerollingOvercome ->
            OvercomeFamily

        AcceptingOvercome ->
            OvercomeFamily

        RejectingOvercome ->
            OvercomeFamily

        AddingStone _ ->
            StonesFamily

        RemovingStone _ ->
            StonesFamily

        AddingSessionAspect ->
            StonesFamily

        DeletingSessionAspect _ ->
            StonesFamily

        UsingSessionAspect _ ->
            StonesFamily

        UnconsumingSessionAspect _ ->
            StonesFamily

        EditingSessionAspect _ ->
            StonesFamily

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
