module UpdateTest exposing (suite)

{-| `Main.update` as a pure function: given a `Msg` and a `Model`, it returns the
next model and an `Effect` value a test can match on directly — no `Cmd`, no
mocking.
-}

import Action exposing (Action(..), Family(..))
import Dict
import Effect exposing (Effect(..))
import Expect
import Fixtures
import Http
import Main
import Roll exposing (Stone(..))
import Set
import Test exposing (Test, describe, test)
import Time
import Types exposing (Model, Msg(..))


{-| The collapsed acknowledge-only result for the stones family, standing in for
the old `StonesUpdated` constructor.
-}
stonesDone : Result Http.Error () -> Msg
stonesDone =
    MutationDone { family = StonesFamily, failMsg = "Failed to update stones." }


overcomeDone : Result Http.Error () -> Msg
overcomeDone =
    MutationDone { family = OvercomeFamily, failMsg = "Couldn't update the Overcome." }


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


{-| `ready`, with one session boon on the table to edit or spend.
-}
withAspect : Model
withAspect =
    let
        gs =
            Fixtures.gameState
    in
    { ready
        | gameState =
            Just
                { gs
                    | sessionAspects =
                        [ { id = "f1", kind = Boon, text = "a note", createdByName = "Gm", consumed = False } ]
                }
    }


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
            [ test "PressOvercome does nothing without auth" <|
                \_ ->
                    Main.update PressOvercome m |> Expect.equal ( m, Effect.None )
            , test "PressOvercome posts a roll with auth, open to a player" <|
                \_ ->
                    Main.update PressOvercome ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostOvercomeRoll Fixtures.playerAuth)
            , test "a second PressOvercome while the first is in flight is dropped" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update PressOvercome ready |> Tuple.first
                    in
                    Main.update PressOvercome afterFirst
                        |> Expect.equal ( afterFirst, Effect.None )
            , test "an Overcome result clears the in-flight roll so it can be fired again" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update PressOvercome ready |> Tuple.first

                        settled =
                            Main.update (overcomeDone (Ok ())) afterFirst |> Tuple.first
                    in
                    Main.update PressOvercome settled
                        |> Tuple.second
                        |> Expect.equal (Effect.PostOvercomeRoll Fixtures.playerAuth)
            , test "reroll, accept and reject each post their own step" <|
                \_ ->
                    [ Main.update RerollOvercome ready |> Tuple.second
                    , Main.update AcceptOvercome ready |> Tuple.second
                    , Main.update RejectOvercome ready |> Tuple.second
                    ]
                        |> Expect.equal
                            [ Effect.PostOvercomeReroll Fixtures.playerAuth
                            , Effect.PostOvercomeAccept Fixtures.playerAuth
                            , Effect.PostOvercomeReject Fixtures.playerAuth
                            ]
            , test "a result message releases only its own family of in-flight actions" <|
                \_ ->
                    Main.update (stonesDone (Ok ()))
                        { ready | inflight = [ AddingStone Bane, GrantingFate 0, AddingStone Boon ] }
                        |> Tuple.first
                        |> .inflight
                        |> Expect.equal [ GrantingFate 0 ]
            , test "AddStone posts the stone's kind" <|
                \_ ->
                    Main.update (AddStone Bane) ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostAddStone Fixtures.playerAuth Bane)
            , test "RemoveStone posts the stone's kind" <|
                \_ ->
                    Main.update (RemoveStone Boon) ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostRemoveStone Fixtures.playerAuth Boon)
            , test "SessionAspectKindChanged sets the pending kind" <|
                \_ ->
                    Main.update (SessionAspectKindChanged Bane) ready
                        |> Expect.equal ( { ready | newSessionAspectKind = Bane }, Effect.None )
            , test "AddSessionAspect does nothing on a blank draft" <|
                \_ ->
                    Main.update AddSessionAspect { ready | newSessionAspectNote = "   " }
                        |> Expect.equal ( { ready | newSessionAspectNote = "   " }, Effect.None )
            , test "AddSessionAspect posts the draft as typed (worker trims it) and clears the field" <|
                \_ ->
                    let
                        ( next, effect ) =
                            Main.update AddSessionAspect { ready | newSessionAspectNote = "  a detail  " }
                    in
                    ( next.newSessionAspectNote, effect )
                        |> Expect.equal ( "", Effect.PostAddSessionAspect Fixtures.playerAuth Boon "  a detail  " )
            , test "AddSessionAspect posts the picked kind" <|
                \_ ->
                    Main.update AddSessionAspect
                        { ready | newSessionAspectNote = "a complication", newSessionAspectKind = Bane }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostAddSessionAspect Fixtures.playerAuth Bane "a complication")
            , test "DeleteSessionAspect posts to the delete route with auth" <|
                \_ ->
                    Main.update (DeleteSessionAspect "f1") ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostDeleteSessionAspect Fixtures.playerAuth "f1")
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
                    Main.update (stonesDone (Err Http.NetworkError)) ready
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
            , test "ToggleGuide flips the guide open and shut, no effect" <|
                \_ ->
                    let
                        opened =
                            Main.update ToggleGuide ready |> Tuple.first
                    in
                    ( opened.guideExpanded
                    , Main.update ToggleGuide opened
                    )
                        |> Expect.equal ( True, ( ready, Effect.None ) )
            , test "ToggleSessionControls flips the top-bar expander open and shut, no effect" <|
                \_ ->
                    let
                        opened =
                            Main.update ToggleSessionControls ready |> Tuple.first
                    in
                    ( opened.sessionControlsExpanded
                    , Main.update ToggleSessionControls opened
                    )
                        |> Expect.equal ( True, ( ready, Effect.None ) )
            , test "ToggleAspectExamples opens one aspect's list, then closes it" <|
                \_ ->
                    let
                        opened =
                            Main.update (ToggleAspectExamples 0 Types.Archetype) ready |> Tuple.first
                    in
                    ( opened.aspectExamplesOpen
                    , Main.update (ToggleAspectExamples 0 Types.Archetype) opened
                    )
                        |> Expect.equal ( Just ( 0, Types.Archetype ), ( ready, Effect.None ) )
            , test "ToggleAspectExamples on a different aspect replaces the open one" <|
                \_ ->
                    let
                        opened =
                            Main.update (ToggleAspectExamples 0 Types.Archetype) ready |> Tuple.first
                    in
                    Main.update (ToggleAspectExamples 1 Types.Desire) opened
                        |> Tuple.first
                        |> .aspectExamplesOpen
                        |> Expect.equal (Just ( 1, Types.Desire ))
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
        , describe "player moves (each is queued as a proposal)"
            [ test "Highlight posts a proposal with auth, and none without" <|
                \_ ->
                    ( Main.update ProposeHighlight ready |> Tuple.second
                    , Main.update ProposeHighlight m |> Tuple.second
                    )
                        |> Expect.equal ( Effect.PostHighlight Fixtures.playerAuth, Effect.None )
            , test "Complicate names its target" <|
                \_ ->
                    Main.update (ProposeComplicate 2) ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostComplicate Fixtures.playerAuth 2)
            , test "Add Detail sends the trimmed suggestion and clears the field" <|
                \_ ->
                    Main.update ProposeAddDetail { ready | addDetailDraft = "  the door is barred  " }
                        |> (\( next, eff ) -> ( eff, next.addDetailDraft ))
                        |> Expect.equal ( Effect.PostAddDetail Fixtures.playerAuth (Just "the door is barred"), "" )
            , test "Add Detail with a blank field asks the facilitator for the wording" <|
                \_ ->
                    Main.update ProposeAddDetail { ready | addDetailDraft = "   " }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostAddDetail Fixtures.playerAuth Nothing)
            , test "Alter Fate and Use Session Boon post their proposals" <|
                \_ ->
                    [ Main.update ProposeAlter ready |> Tuple.second
                    , Main.update (ProposeUseSessionBoon "f1") ready |> Tuple.second
                    ]
                        |> Expect.equal
                            [ Effect.PostAlter Fixtures.playerAuth
                            , Effect.PostUseSessionBoon Fixtures.playerAuth "f1"
                            ]
            , test "a second move of the same kind is dropped while the first is in flight, a different move is not" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update ProposeHighlight ready |> Tuple.first
                    in
                    ( Main.update ProposeHighlight afterFirst |> Tuple.second
                    , Main.update ProposeAlter afterFirst |> Tuple.second
                    )
                        |> Expect.equal ( Effect.None, Effect.PostAlter Fixtures.playerAuth )
            ]
        , describe "session boons and banes"
            [ test "using and unconsuming post their own step" <|
                \_ ->
                    [ Main.update (UseSessionAspect "f1") ready |> Tuple.second
                    , Main.update (UnconsumeSessionAspect "f1") ready |> Tuple.second
                    ]
                        |> Expect.equal
                            [ Effect.PostUseSessionAspect Fixtures.playerAuth "f1"
                            , Effect.PostUnconsumeSessionAspect Fixtures.playerAuth "f1"
                            ]
            , test "editing the text keeps a local draft without posting" <|
                \_ ->
                    Main.update (SessionAspectTextChanged "f1" "new wording") withAspect
                        |> (\( next, eff ) -> ( eff, Dict.get "f1" next.sessionAspectEdits ))
                        |> Expect.equal ( Effect.None, Just "new wording" )
            , test "leaving the field saves a changed, non-blank text, trimmed, and drops the draft" <|
                \_ ->
                    Main.update (SaveSessionAspectText "f1")
                        { withAspect | sessionAspectEdits = Dict.singleton "f1" "  new wording  " }
                        |> (\( next, eff ) -> ( eff, Dict.member "f1" next.sessionAspectEdits ))
                        |> Expect.equal ( Effect.PostUpdateSessionAspect Fixtures.playerAuth "f1" "new wording", False )
            , test "leaving the field with the text unchanged, or blank, posts nothing" <|
                \_ ->
                    [ Main.update (SaveSessionAspectText "f1")
                        { withAspect | sessionAspectEdits = Dict.singleton "f1" "a note" }
                        |> Tuple.second
                    , Main.update (SaveSessionAspectText "f1")
                        { withAspect | sessionAspectEdits = Dict.singleton "f1" "   " }
                        |> Tuple.second
                    ]
                        |> Expect.equal [ Effect.None, Effect.None ]
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
        , describe "earlier-message history"
            [ test "LoadEarlierMessages asks for rows before the oldest loaded one" <|
                \_ ->
                    let
                        seeded =
                            withMessages [ msgAt "a" 1000, msgAt "b" 2000 ]
                    in
                    Main.update LoadEarlierMessages seeded
                        |> (\( next, eff ) -> ( next.loadingHistory, eff ))
                        |> Expect.equal ( True, Effect.GetMessageHistory Fixtures.playerAuth 1000 )
            , test "LoadEarlierMessages does nothing while a fetch is already in flight" <|
                \_ ->
                    let
                        seeded =
                            withMessages [ msgAt "a" 1000 ]
                    in
                    Main.update LoadEarlierMessages { seeded | loadingHistory = True }
                        |> Expect.equal ( { seeded | loadingHistory = True }, Effect.None )
            , test "an empty history page marks the log fully loaded" <|
                \_ ->
                    Main.update (GotEarlierMessages (Ok [])) { ready | loadingHistory = True }
                        |> (\( next, _ ) -> ( next.loadingHistory, next.noMoreHistory ))
                        |> Expect.equal ( False, True )
            , test "a history page is prepended, older first, without duplicating known rows" <|
                \_ ->
                    let
                        seeded =
                            withMessages [ msgAt "b" 2000, msgAt "c" 3000 ]
                    in
                    Main.update (GotEarlierMessages (Ok [ msgAt "a" 1000, msgAt "b" 2000 ])) seeded
                        |> Tuple.first
                        |> .gameState
                        |> Maybe.map (.messages >> List.map .id)
                        |> Expect.equal (Just [ "a", "b", "c" ])
            ]
        ]


msgAt : String -> Int -> Types.Message
msgAt id millis =
    { id = id
    , authorId = "u"
    , authorName = "U"
    , role = Types.Player
    , content = id
    , createdAt = Time.millisToPosix millis
    }


withMessages : List Types.Message -> Model
withMessages messages =
    case ready.gameState of
        Just gs ->
            { ready | gameState = Just { gs | messages = messages } }

        Nothing ->
            ready
