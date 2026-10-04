module UpdateTest exposing (suite)

{-| `Main.update` as a pure function: given a `Msg` and a `Model`, it returns the
next model and an `Effect` value a test can match on directly — no `Cmd`, no
mocking.
-}

import Action exposing (Action(..), Family(..))
import Aspect exposing (Aspect(..))
import ContextAspect exposing (Polarity(..))
import Dict
import Die
import Effect exposing (Effect(..))
import Expect
import Fixtures
import Http
import Main
import MoveRecord
import Set
import Test exposing (Test, describe, test)
import Time
import Types exposing (Model, Msg(..), ToolTab(..))


{-| The collapsed acknowledge-only result for the die family.
-}
dieDone : Result Http.Error () -> Msg
dieDone =
    MutationDone { family = DieFamily, failMsg = "Couldn't step the die." }


junctionDone : Result Http.Error () -> Msg
junctionDone =
    MutationDone { family = JunctionFamily, failMsg = "Couldn't update the Junction." }


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


{-| `ready`, with one context boon on the table to edit or spend.
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
                    | contextAspects =
                        [ { id = "f1", polarity = Boon, text = "a note", createdByName = "Gm", consumed = False, fromAspect = Nothing } ]
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
            [ test "PressJunction does nothing without auth" <|
                \_ ->
                    Main.update PressJunction m |> Expect.equal ( m, Effect.None )
            , test "PressJunction posts a roll with auth, open to a player" <|
                \_ ->
                    Main.update PressJunction ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostJunctionRoll Fixtures.playerAuth)
            , test "a second PressJunction while the first is in flight is dropped" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update PressJunction ready |> Tuple.first
                    in
                    Main.update PressJunction afterFirst
                        |> Expect.equal ( afterFirst, Effect.None )
            , test "a Junction result clears the in-flight roll so it can be fired again" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update PressJunction ready |> Tuple.first

                        settled =
                            Main.update (junctionDone (Ok ())) afterFirst |> Tuple.first
                    in
                    Main.update PressJunction settled
                        |> Tuple.second
                        |> Expect.equal (Effect.PostJunctionRoll Fixtures.playerAuth)
            , test "reroll, accept and reject each post their own step" <|
                \_ ->
                    [ Main.update RerollJunction ready |> Tuple.second
                    , Main.update AcceptJunction ready |> Tuple.second
                    , Main.update RejectJunction ready |> Tuple.second
                    ]
                        |> Expect.equal
                            [ Effect.PostJunctionReroll Fixtures.playerAuth
                            , Effect.PostJunctionAccept Fixtures.playerAuth
                            , Effect.PostJunctionReject Fixtures.playerAuth
                            ]
            , test "a result message releases only its own family of in-flight actions" <|
                \_ ->
                    Main.update (dieDone (Ok ()))
                        { ready | inflight = [ SteppingDie Die.Down, GrantingFate 0, SteppingDie Die.Up ] }
                        |> Tuple.first
                        |> .inflight
                        |> Expect.equal [ GrantingFate 0 ]
            , test "StepDie posts the step's direction, once while in flight" <|
                \_ ->
                    let
                        ( afterFirst, first ) =
                            Main.update (StepDie Die.Up) ready
                    in
                    ( first
                    , Main.update (StepDie Die.Up) afterFirst |> Tuple.second
                    , Main.update (StepDie Die.Down) afterFirst |> Tuple.second
                    )
                        |> Expect.equal
                            ( Effect.PostStepDie Fixtures.playerAuth Die.Up
                            , Effect.None
                            , Effect.PostStepDie Fixtures.playerAuth Die.Down
                            )
            , test "ContextAspectKindChanged sets the pending kind" <|
                \_ ->
                    Main.update (ContextAspectKindChanged Bane) ready
                        |> Expect.equal ( { ready | newContextAspectKind = Bane }, Effect.None )
            , test "AddContextAspect does nothing on a blank draft" <|
                \_ ->
                    Main.update AddContextAspect { ready | newContextAspectNote = "   " }
                        |> Expect.equal ( { ready | newContextAspectNote = "   " }, Effect.None )
            , test "AddContextAspect posts the draft as typed (worker trims it) and clears the field" <|
                \_ ->
                    let
                        ( next, effect ) =
                            Main.update AddContextAspect { ready | newContextAspectNote = "  a detail  " }
                    in
                    ( next.newContextAspectNote, effect )
                        |> Expect.equal ( "", Effect.PostAddContextAspect Fixtures.playerAuth Boon "  a detail  " )
            , test "AddContextAspect posts the picked kind" <|
                \_ ->
                    Main.update AddContextAspect
                        { ready | newContextAspectNote = "a complication", newContextAspectKind = Bane }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostAddContextAspect Fixtures.playerAuth Bane "a complication")
            , test "DeleteContextAspect posts to the delete route with auth" <|
                \_ ->
                    Main.update (DeleteContextAspect "f1") ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostDeleteContextAspect Fixtures.playerAuth "f1")
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
                    Main.update (dieDone (Err Http.NetworkError)) ready
                        |> (\( next, eff ) -> ( next.error, next.status, eff ))
                        |> Expect.equal
                            ( Just "Couldn't step the die.", ready.status, Effect.DismissErrorIn 6000 )
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
            , test "SelectTool switches the left panel's tool, no effect" <|
                \_ ->
                    Main.update (SelectTool CastTab) ready
                        |> Expect.equal ( { ready | toolTab = CastTab }, Effect.None )
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
                            Main.update (ToggleAspectExamples 0 Archetype) ready |> Tuple.first
                    in
                    ( opened.aspectExamplesOpen
                    , Main.update (ToggleAspectExamples 0 Archetype) opened
                    )
                        |> Expect.equal ( Just ( 0, Archetype ), ( ready, Effect.None ) )
            , test "ToggleAspectExamples on a different aspect replaces the open one" <|
                \_ ->
                    let
                        opened =
                            Main.update (ToggleAspectExamples 0 Archetype) ready |> Tuple.first
                    in
                    Main.update (ToggleAspectExamples 1 Desire) opened
                        |> Tuple.first
                        |> .aspectExamplesOpen
                        |> Expect.equal (Just ( 1, Desire ))
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
        , describe "moves (each acts at once)"
            [ test "Highlight posts the aspect with auth, and nothing without" <|
                \_ ->
                    ( Main.update (MakeHighlight Desire) ready |> Tuple.second
                    , Main.update (MakeHighlight Desire) m |> Tuple.second
                    )
                        |> Expect.equal ( Effect.PostHighlight Fixtures.playerAuth Desire, Effect.None )
            , test "Complicate posts the aspect it draws on" <|
                \_ ->
                    Main.update (MakeComplicate Quest) ready
                        |> Tuple.second
                        |> Expect.equal (Effect.PostComplicate Fixtures.playerAuth Quest)
            , test "Create sends the trimmed draft and clears the field" <|
                \_ ->
                    Main.update MakeCreate { ready | createDraft = "  the door is barred  " }
                        |> (\( next, eff ) -> ( eff, next.createDraft ))
                        |> Expect.equal ( Effect.PostCreate Fixtures.playerAuth "the door is barred", "" )
            , test "Create with a blank field still posts, for the Worker's default wording" <|
                \_ ->
                    Main.update MakeCreate { ready | createDraft = "   " }
                        |> Tuple.second
                        |> Expect.equal (Effect.PostCreate Fixtures.playerAuth "")
            , test "CreateDraftChanged keeps the draft without posting" <|
                \_ ->
                    Main.update (CreateDraftChanged "a ladder") ready
                        |> Expect.equal ( { ready | createDraft = "a ladder" }, Effect.None )
            , test "Alter and Highlight Context post their moves" <|
                \_ ->
                    [ Main.update MakeAlter ready |> Tuple.second
                    , Main.update (MakeHighlightContext "f1") ready |> Tuple.second
                    ]
                        |> Expect.equal
                            [ Effect.PostAlter Fixtures.playerAuth
                            , Effect.PostHighlightContext Fixtures.playerAuth "f1"
                            ]
            , test "a second move of the same kind is dropped while the first is in flight, a different move is not" <|
                \_ ->
                    let
                        afterFirst =
                            Main.update (MakeHighlight Desire) ready |> Tuple.first
                    in
                    ( Main.update (MakeHighlight Quest) afterFirst |> Tuple.second
                    , Main.update MakeAlter afterFirst |> Tuple.second
                    )
                        |> Expect.equal ( Effect.None, Effect.PostAlter Fixtures.playerAuth )
            , test "UndoMove posts the move's undo, guarded per move" <|
                \_ ->
                    let
                        ( afterFirst, first ) =
                            Main.update (UndoMove "mv1") ready
                    in
                    ( first
                    , Main.update (UndoMove "mv1") afterFirst |> Tuple.second
                    , Main.update (UndoMove "mv2") afterFirst |> Tuple.second
                    )
                        |> Expect.equal
                            ( Effect.PostUndo Fixtures.playerAuth "mv1"
                            , Effect.None
                            , Effect.PostUndo Fixtures.playerAuth "mv2"
                            )
            , test "a move's result releases the move family only" <|
                \_ ->
                    Main.update (MutationDone { family = MoveFamily, failMsg = "" } (Ok ()))
                        { ready | inflight = [ MakingMove MoveRecord.Alter, UndoingMove "mv1" ] }
                        |> Tuple.first
                        |> .inflight
                        |> Expect.equal [ UndoingMove "mv1" ]
            ]
        , describe "context boons and banes"
            [ test "editing the text keeps a local draft without posting" <|
                \_ ->
                    Main.update (ContextAspectTextChanged "f1" "new wording") withAspect
                        |> (\( next, eff ) -> ( eff, Dict.get "f1" next.contextAspectEdits ))
                        |> Expect.equal ( Effect.None, Just "new wording" )
            , test "leaving the field saves a changed, non-blank text, trimmed, and drops the draft" <|
                \_ ->
                    Main.update (SaveContextAspectText "f1")
                        { withAspect | contextAspectEdits = Dict.singleton "f1" "  new wording  " }
                        |> (\( next, eff ) -> ( eff, Dict.member "f1" next.contextAspectEdits ))
                        |> Expect.equal ( Effect.PostUpdateContextAspect Fixtures.playerAuth "f1" "new wording", False )
            , test "leaving the field with the text unchanged, or blank, posts nothing" <|
                \_ ->
                    [ Main.update (SaveContextAspectText "f1")
                        { withAspect | contextAspectEdits = Dict.singleton "f1" "a note" }
                        |> Tuple.second
                    , Main.update (SaveContextAspectText "f1")
                        { withAspect | contextAspectEdits = Dict.singleton "f1" "   " }
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
    , kind = Types.Chat
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
