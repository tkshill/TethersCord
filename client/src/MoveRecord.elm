module MoveRecord exposing (Kind(..), MoveRecord, kindLabel, undoableBy)

{-| A move that can still be undone (ADR 0002). The Worker keeps these in
`gameState.moves` until the window closes — when the junction is rolled, or,
for an Alter, when its junction ends — and `messageId` names the move's log
line, where the undo link goes. The move's effects stay on the Worker; the
client only needs to know whose it is and where it was logged.

`Kind`'s constructors share names with several `Msg` variants, so it lives
here rather than in `Types`.

-}

import Aspect exposing (Aspect)


type Kind
    = Highlight
    | HighlightContext
    | Complicate
    | Create
    | Alter


kindLabel : Kind -> String
kindLabel kind =
    case kind of
        Highlight ->
            "Highlight"

        HighlightContext ->
            "Highlight Context"

        Complicate ->
            "Complicate"

        Create ->
            "Create"

        Alter ->
            "Alter"


type alias MoveRecord =
    { id : String
    , kind : Kind
    , actorId : String
    , actorName : String
    , slot : Maybe Int
    , aspect : Maybe Aspect
    , messageId : String
    }


{-| The facilitator may undo any move; a player only their own. `viewer` is
`( userId, isFacilitator )`.
-}
undoableBy : ( String, Bool ) -> MoveRecord -> Bool
undoableBy ( userId, isFacilitator ) move =
    isFacilitator || move.actorId == userId
