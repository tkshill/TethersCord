module StateMergeTest exposing (suite)

{-| `Main.applyServerState` — the rule that a server snapshot replaces local
state wholesale *except* for the character sheet the user is part-way through
editing, which would otherwise lose the field under the cursor on the next
broadcast.
-}

import Expect
import Fixtures
import Main
import Test exposing (Test, describe, test)
import Types exposing (CharacterSheet, GameState)


{-| Two-slot incoming snapshot; slot 1's name differs from any local edit.
-}
incoming : GameState
incoming =
    { sessionId = "sess-1"
    , messages = []
    , stonePool = []
    , pendingRoll = Nothing
    , committedBoons = []
    , proposals = []
    , session = Nothing
    , characters =
        [ { sheet | slot = 1, name = "server name" }
        , { sheet | slot = 2, name = "other" }
        ]
    , sessionHistory = []
    , overcome = Nothing
    , floatingBoons = []
    , usedAbilities = []
    }


sheet : CharacterSheet
sheet =
    Fixtures.character


suite : Test
suite =
    describe "Main.applyServerState"
        [ test "takes the incoming snapshot verbatim when nothing is being edited" <|
            \_ ->
                Main.applyServerState Fixtures.model incoming
                    |> Expect.equal incoming
        , test "keeps the locally-edited sheet at the editing slot" <|
            \_ ->
                let
                    local =
                        { incoming
                            | characters =
                                [ { sheet | slot = 1, name = "half-typed edit" }
                                , { sheet | slot = 2, name = "other" }
                                ]
                        }

                    model =
                        { m | editingSlot = Just 1, gameState = Just local }
                in
                Main.applyServerState model incoming
                    |> .characters
                    |> List.map (\c -> ( c.slot, c.name ))
                    |> Expect.equal [ ( 1, "half-typed edit" ), ( 2, "other" ) ]
        , test "still takes every other slot from the incoming snapshot" <|
            \_ ->
                let
                    local =
                        { incoming
                            | characters =
                                [ { sheet | slot = 1, name = "half-typed edit" }
                                , { sheet | slot = 2, name = "stale local" }
                                ]
                        }

                    model =
                        { m | editingSlot = Just 1, gameState = Just local }
                in
                Main.applyServerState model incoming
                    |> .characters
                    |> List.filter (\c -> c.slot == 2)
                    |> List.map .name
                    |> Expect.equal [ "other" ]
        , test "falls back to the snapshot when the editing slot is not in local state" <|
            \_ ->
                let
                    model =
                        { m | editingSlot = Just 9, gameState = Just incoming }
                in
                Main.applyServerState model incoming
                    |> Expect.equal incoming
        , test "falls back to the snapshot when there is no prior local state" <|
            \_ ->
                let
                    model =
                        { m | editingSlot = Just 1, gameState = Nothing }
                in
                Main.applyServerState model incoming
                    |> Expect.equal incoming
        ]


m : Types.Model
m =
    Fixtures.model
