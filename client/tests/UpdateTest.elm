module UpdateTest exposing (suite)

{-| `Main.update` as a pure function: given a `Msg` and a `Model`, it returns the
next model and an `Effect` value a test can match on directly — no `Cmd`, no
mocking.
-}

import Effect exposing (Effect(..))
import Expect
import Fixtures
import Http
import Main
import Test exposing (Test, describe, test)
import Types exposing (Model, Msg(..))


{-| Model after a successful auth + first snapshot: authorised, with game state.
-}
ready : Model
ready =
    { m
        | auth = Just Fixtures.playerAuth
        , gameState = Just Fixtures.gameState
    }


m : Model
m =
    Fixtures.model


suite : Test
suite =
    describe "Main.update"
        [ describe "SendMessage guard"
            [ test "a blank message produces no effect and no model change" <|
                \_ ->
                    Main.update SendMessage { ready | newMessage = "   " }
                        |> Expect.equal ( { ready | newMessage = "   " }, Effect.None )
            , test "a real message clears the field, pins the log, and posts" <|
                \_ ->
                    Main.update SendMessage { ready | newMessage = "hi", logAtBottom = False }
                        |> Expect.equal
                            ( { ready | newMessage = "", logAtBottom = True }
                            , Effect.PostMessage Fixtures.playerAuth "hi"
                            )
            , test "does nothing before auth arrives" <|
                \_ ->
                    Main.update SendMessage { m | newMessage = "hi", gameState = Just Fixtures.gameState }
                        |> Tuple.second
                        |> Expect.equal Effect.None
            , test "does nothing before the board has loaded" <|
                \_ ->
                    Main.update SendMessage { m | newMessage = "hi", auth = Just Fixtures.playerAuth }
                        |> Tuple.second
                        |> Expect.equal Effect.None
            ]
        , describe "GotGameState seed"
            [ test "the first snapshot seeds the board and scrolls the log" <|
                \_ ->
                    Main.update (GotGameState (Ok Fixtures.gameState)) { ready | gameState = Nothing }
                        |> Expect.equal
                            ( { ready | gameState = Just Fixtures.gameState, status = "Connected." }
                            , Effect.ScrollLogToBottom
                            )
            , test "a later seed does not overwrite state the socket already delivered" <|
                \_ ->
                    let
                        live =
                            { ready | gameState = Just { gs | sessionId = "from-socket" } }

                        gs =
                            Fixtures.gameState
                    in
                    Main.update (GotGameState (Ok Fixtures.gameState)) live
                        |> Expect.equal
                            ( { live | status = "Connected.", gameStateAttempts = 0 }, Effect.None )
            , test "a failed seed retries with a backoff until the attempt cap" <|
                \_ ->
                    Main.update (GotGameState (Err Http.NetworkError)) { m | gameStateAttempts = 0 }
                        |> Expect.equal
                            ( { m | status = "Reconnecting to the table…", gameStateAttempts = 1 }
                            , Effect.RetryGetGameStateIn 2000
                            )
            , test "gives up once the cap is reached" <|
                \_ ->
                    Main.update (GotGameState (Err Http.NetworkError)) { m | gameStateAttempts = 3 }
                        |> Expect.equal
                            ( { m | status = "Failed to load game state.", gameStateAttempts = 3 }
                            , Effect.None
                            )
            , test "RetryGetGameState re-issues the load while the socket is still silent" <|
                \_ ->
                    Main.update RetryGetGameState { m | auth = Just Fixtures.playerAuth }
                        |> Expect.equal ( { m | auth = Just Fixtures.playerAuth }, Effect.GetGameState Fixtures.playerAuth )
            , test "RetryGetGameState is a no-op once state has arrived" <|
                \_ ->
                    Main.update RetryGetGameState ready
                        |> Expect.equal ( ready, Effect.None )
            ]
        , describe "auth-gated effects"
            [ test "AddBoon does nothing without auth" <|
                \_ ->
                    Main.update AddBoon m |> Expect.equal ( m, Effect.None )
            , test "AddBoon posts to the add-boon route with auth" <|
                \_ ->
                    Main.update AddBoon ready
                        |> Expect.equal ( ready, Effect.PostStones Fixtures.playerAuth "/stones/add-boon" )
            , test "RollStones targets the roll route" <|
                \_ ->
                    Main.update RollStones ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostStones Fixtures.playerAuth "/stones/roll")
            , test "AcceptProposal carries the trimmed draft note as context" <|
                \_ ->
                    Main.update (AcceptProposal "p1") { ready | proposalDraft = "  a detail  " }
                        |> Tuple.second
                        |> Expect.equal
                            (Effect.PostProposalDecision Fixtures.playerAuth "p1" "accept" (Just "a detail"))
            , test "AcceptProposal sends no context when the draft is blank" <|
                \_ ->
                    Main.update (AcceptProposal "p1") { ready | proposalDraft = "   " }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostProposalDecision Fixtures.playerAuth "p1" "accept" Nothing)
            , test "RejectProposal never carries context" <|
                \_ ->
                    Main.update (RejectProposal "p1") { ready | proposalDraft = "ignored" }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostProposalDecision Fixtures.playerAuth "p1" "reject" Nothing)
            ]
        , describe "local-only messages"
            [ test "NewMessageChanged only updates the draft" <|
                \_ ->
                    Main.update (NewMessageChanged "typing") ready
                        |> Expect.equal ( { ready | newMessage = "typing" }, Effect.None )
            , test "SelectSlot only moves the open tab" <|
                \_ ->
                    Main.update (SelectSlot 2) ready
                        |> Expect.equal ( { ready | selectedSlot = 2 }, Effect.None )
            , test "CharacterFieldInput edits local state and marks the slot as being edited" <|
                \_ ->
                    Main.update (CharacterFieldInput 1 Types.NameField "Bea") ready
                        |> (\( next, eff ) ->
                                ( eff
                                , next.editingSlot
                                , next.gameState
                                    |> Maybe.map (.characters >> List.map .name)
                                )
                           )
                        |> Expect.equal ( Effect.None, Just 1, Just [ "Bea" ] )
            ]
        ]
