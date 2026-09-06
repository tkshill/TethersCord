module UpdateTest exposing (suite)

{-| `Main.update` as a pure function: given a `Msg` and a `Model`, it returns the
next model and an `Effect` value a test can match on directly — no `Cmd`, no
mocking.
-}

import Dict
import Effect exposing (Effect(..))
import Expect
import Fixtures
import Http
import Main
import Set
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
            [ test "backend auth schedules a fallback load rather than fetching immediately" <|
                \_ ->
                    Main.update (GotBackendAuth (Ok Fixtures.playerAuth)) m
                        |> Tuple.second
                        |> Expect.equal (Effect.RetryGetGameStateIn 3000)
            , test "the first snapshot seeds the board and scrolls the log" <|
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
                            , Effect.RetryGetGameStateIn 3000
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
                        |> Tuple.second
                        |> Expect.equal (Effect.PostStones Fixtures.playerAuth "/stones/add-boon")
            , test "RollStones targets the roll route" <|
                \_ ->
                    Main.update RollStones ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostStones Fixtures.playerAuth "/stones/roll")
            , test "a second RollStones while the first is in flight is dropped" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update RollStones ready |> Tuple.first
                    in
                    Main.update RollStones afterFirst
                        |> Expect.equal ( afterFirst, Effect.None )
            , test "StonesUpdated clears the in-flight roll so it can be fired again" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update RollStones ready |> Tuple.first

                        settled =
                            Main.update (StonesUpdated (Ok ())) afterFirst |> Tuple.first
                    in
                    Main.update RollStones settled
                        |> Tuple.second
                        |> Expect.equal (Effect.PostStones Fixtures.playerAuth "/stones/roll")
            , test "AcceptProposal carries that row's trimmed draft note as context" <|
                \_ ->
                    Main.update (AcceptProposal "p1")
                        { ready | proposalDrafts = Dict.fromList [ ( "p1", "  a detail  " ) ] }
                        |> Tuple.second
                        |> Expect.equal
                            (Effect.PostProposalDecision Fixtures.playerAuth "p1" "accept" (Just "a detail"))
            , test "AcceptProposal sends no context when this row's draft is blank" <|
                \_ ->
                    Main.update (AcceptProposal "p1")
                        { ready | proposalDrafts = Dict.fromList [ ( "p1", "   " ), ( "p2", "other" ) ] }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostProposalDecision Fixtures.playerAuth "p1" "accept" Nothing)
            , test "RejectProposal never carries context" <|
                \_ ->
                    Main.update (RejectProposal "p1")
                        { ready | proposalDrafts = Dict.fromList [ ( "p1", "ignored" ) ] }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostProposalDecision Fixtures.playerAuth "p1" "reject" Nothing)
            , test "WithdrawProposal posts to the withdraw route with auth" <|
                \_ ->
                    Main.update (WithdrawProposal "p1") ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostWithdrawProposal Fixtures.playerAuth "p1")
            ]
        , describe "per-row proposal drafts"
            [ test "ProposalDraftChanged writes only the named row" <|
                \_ ->
                    { ready | proposalDrafts = Dict.fromList [ ( "p2", "kept" ) ] }
                        |> Main.update (ProposalDraftChanged "p1" "typing")
                        |> Tuple.first
                        |> .proposalDrafts
                        |> Expect.equal (Dict.fromList [ ( "p1", "typing" ), ( "p2", "kept" ) ])
            , test "ProposalResolved Ok drops that row's draft" <|
                \_ ->
                    { ready | proposalDrafts = Dict.fromList [ ( "p1", "note" ), ( "p2", "kept" ) ] }
                        |> Main.update (ProposalResolved "p1" (Ok ()))
                        |> Tuple.first
                        |> .proposalDrafts
                        |> Expect.equal (Dict.fromList [ ( "p2", "kept" ) ])
            ]
        , describe "confirm gate"
            [ test "RequestConfirm arms the named action, no effect" <|
                \_ ->
                    Main.update (RequestConfirm "end-session") ready
                        |> Expect.equal ( { ready | confirming = Just "end-session" }, Effect.None )
            , test "EndSession fires only after the action is armed, and disarms" <|
                \_ ->
                    let
                        armed =
                            { ready | confirming = Just "end-session" }
                    in
                    Main.update EndSession armed
                        |> (\( next, eff ) -> ( next.confirming, eff ))
                        |> Expect.equal ( Nothing, Effect.PostEndSession Fixtures.playerAuth )
            , test "CancelConfirm disarms without acting" <|
                \_ ->
                    Main.update CancelConfirm { ready | confirming = Just "clear-log" }
                        |> Expect.equal ( ready, Effect.None )
            ]
        , describe "transient errors"
            [ test "a failed mutation sets error, not status, and schedules its dismissal" <|
                \_ ->
                    Main.update (StonesUpdated (Err Http.NetworkError)) ready
                        |> (\( next, eff ) -> ( next.error, next.status, eff ))
                        |> Expect.equal
                            ( Just "Failed to update stones.", ready.status, Effect.DismissErrorIn 6000 )
            , test "DismissError clears the error line" <|
                \_ ->
                    Main.update DismissError { ready | error = Just "boom" }
                        |> Expect.equal ( ready, Effect.None )
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
            , test "CharacterFieldInput edits local state, marks the slot dirty, and arms the debounced save" <|
                \_ ->
                    Main.update (CharacterFieldInput 1 Types.NameField "Bea") ready
                        |> (\( next, eff ) ->
                                ( eff
                                , next.editingSlot
                                , next.gameState
                                    |> Maybe.map (.characters >> List.map .name)
                                )
                           )
                        |> Expect.equal ( Effect.DebounceFieldSave 1 1000, Just 1, Just [ "Bea" ] )
            , test "a stale FieldSaveDue token is ignored" <|
                \_ ->
                    let
                        edited =
                            Main.update (CharacterFieldInput 1 Types.NameField "Bea") ready
                                |> Tuple.first
                                |> Main.update (CharacterFieldInput 1 Types.NameField "Beatrix")
                                |> Tuple.first
                    in
                    -- token 1 was superseded by token 2, so the earlier timer is a no-op
                    Main.update (FieldSaveDue 1) edited
                        |> Expect.equal ( edited, Effect.None )
            , test "the current FieldSaveDue flushes each dirty sheet as one write and clears the dirty set" <|
                \_ ->
                    let
                        edited =
                            Main.update (CharacterFieldInput 1 Types.NameField "Bea") ready
                                |> Tuple.first
                    in
                    Main.update (FieldSaveDue edited.fieldSaveSeq) edited
                        |> (\( next, eff ) ->
                                case eff of
                                    Effect.Batch [ Effect.PostCharacterUpdate _ slot sheet ] ->
                                        ( slot, sheet.name, Set.isEmpty next.dirtySlots )

                                    _ ->
                                        ( -1, "wrong effect", False )
                           )
                        |> Expect.equal ( 1, "Bea", True )
            ]
        , describe "Highlight pledge coalescing"
            [ test "the +/- taps only arm a debounce, they do not each POST" <|
                \_ ->
                    let
                        ( afterTaps, _ ) =
                            Main.update CommitBoonIncrement ready
                                |> Tuple.first
                                |> Main.update CommitBoonIncrement
                                |> Tuple.first
                                |> Main.update CommitBoonDecrement
                    in
                    afterTaps.pendingPledgeDelta |> Expect.equal 1
            , test "PledgeDue sends the accumulated net delta as one commit" <|
                \_ ->
                    let
                        armed =
                            Main.update CommitBoonIncrement ready
                                |> Tuple.first
                                |> Main.update CommitBoonIncrement
                                |> Tuple.first
                    in
                    Main.update (PledgeDue armed.pledgeSeq) armed
                        |> (\( next, eff ) -> ( eff, next.pendingPledgeDelta ))
                        |> Expect.equal ( Effect.PostCommitBoon Fixtures.playerAuth 2, 0 )
            , test "a stale PledgeDue token is ignored" <|
                \_ ->
                    let
                        armed =
                            Main.update CommitBoonIncrement ready |> Tuple.first
                    in
                    Main.update (PledgeDue (armed.pledgeSeq - 1)) armed
                        |> Expect.equal ( armed, Effect.None )
            ]
        , describe "NPCs and locations"
            [ test "AddEntity posts a create for that kind with auth" <|
                \_ ->
                    Main.update (AddEntity Types.Npc) ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostCreateEntity Fixtures.playerAuth Types.Npc)
            , test "EntityFieldInput edits the local row and marks it as being edited" <|
                \_ ->
                    let
                        gs =
                            Fixtures.gameState

                        seeded =
                            { ready
                                | gameState =
                                    Just { gs | npcs = [ { id = "n1", name = "", notes = "" } ] }
                            }
                    in
                    Main.update (EntityFieldInput Types.Npc "n1" Types.EntityNameField "Warden") seeded
                        |> (\( next, eff ) ->
                                ( eff
                                , next.editingEntity
                                , next.gameState |> Maybe.map (.npcs >> List.map .name)
                                )
                           )
                        |> Expect.equal ( Effect.DebounceFieldSave 1 1000, Just "n1", Just [ "Warden" ] )
            , test "EntityFieldBlur releases the edit lock; the debounced flush posts the row" <|
                \_ ->
                    let
                        gs =
                            Fixtures.gameState

                        seeded =
                            { ready | gameState = Just { gs | locations = [ { id = "l1", name = "The", notes = "" } ] } }

                        edited =
                            Main.update (EntityFieldInput Types.Location "l1" Types.EntityNameField "The Gate") seeded
                                |> Tuple.first

                        blurred =
                            Main.update (EntityFieldBlur Types.Location "l1") edited |> Tuple.first
                    in
                    ( blurred.editingEntity
                    , Main.update (FieldSaveDue blurred.fieldSaveSeq) blurred
                        |> Tuple.second
                    )
                        |> Expect.equal
                            ( Nothing
                            , Effect.Batch
                                [ Effect.PostUpdateEntity Fixtures.playerAuth
                                    Types.Location
                                    { id = "l1", name = "The Gate", notes = "" }
                                ]
                            )
            , test "DeleteEntity clears an edit lock on that row and posts a delete" <|
                \_ ->
                    Main.update (DeleteEntity Types.Npc "n1") { ready | editingEntity = Just "n1" }
                        |> (\( next, eff ) -> ( next.editingEntity, eff ))
                        |> Expect.equal
                            ( Nothing, Effect.PostDeleteEntity Fixtures.playerAuth Types.Npc "n1" )
            ]
        ]
