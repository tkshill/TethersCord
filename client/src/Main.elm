module Main exposing (applyServerState, init, main, update)

{-| Program wiring only: `init`, `update`, `subscriptions`, `main`. Domain types
and `Model` / `Msg` live in `Types`; HTTP in `Api`; interop in `Ports`; the view
in `View`.

`update` returns `( Model, Effect )` — a pure value — and `Effect.perform` turns
that into a `Cmd` once, here at the boundary.

-}

import Action exposing (Action(..), Decision(..), Family(..))
import Api
import Browser
import Browser.Events
import Dict
import Effect exposing (Effect)
import Json.Decode as Decode
import Kind
import Ports
import Roll exposing (Stone(..), stoneLabel)
import Set
import Time
import Types exposing (..)
import View


{-| How many times the initial game-state seed is retried before giving up.
-}
maxGameStateAttempts : Int
maxGameStateAttempts =
    3


{-| Delay before the fallback game-state load, in milliseconds. The live socket
sends a full snapshot before its first `await`, so in nearly every launch it
beats this timer and the HTTP `getGameState` never fires. It doubles as the
backoff between retries once a load has actually failed.
-}
gameStateRetryDelay : Float
gameStateRetryDelay =
    3000


{-| How long a transient error stays on screen before it dismisses itself, in
milliseconds.
-}
errorDismissDelay : Float
errorDismissDelay =
    6000


{-| Idle time after the last character-sheet / entity keystroke before the edit
is flushed to the server as one write, rather than one per field blur.
-}
fieldSaveDelay : Float
fieldSaveDelay =
    1000


{-| The left panel's width in pixels (roadmap section 24, the 1c layout
variant), and the range the draggable divider clamps it to so neither panel
can be dragged away to nothing.
-}
defaultLeftPanelWidth : Float
defaultLeftPanelWidth =
    420


minLeftPanelWidth : Float
minLeftPanelWidth =
    280


maxLeftPanelWidth : Float
maxLeftPanelWidth =
    640


connectionFromString : String -> Connection
connectionFromString raw =
    case raw of
        "connected" ->
            Connected

        "reconnecting" ->
            Reconnecting

        "rejected" ->
            Rejected

        _ ->
            Offline


{-| Flip one of the left panel's three accordion sections, leaving the other
two untouched (roadmap section 24, the 1c layout variant).
-}
toggleLeftSection : LeftSection -> LeftSections -> LeftSections
toggleLeftSection section sections =
    case section of
        FacilitatorSection ->
            { sections | facilitator = not sections.facilitator }

        CharactersSection ->
            { sections | characters = not sections.characters }

        MovesSection ->
            { sections | moves = not sections.moves }


main : Program Flags Model Msg
main =
    Browser.element
        { init = \flags -> init flags |> withPerform flags
        , update = \msg model -> update msg model |> withPerform model.flags
        , view = View.view
        , subscriptions = subscriptions
        }


{-| Run the `Effect` half of an `update` result through `Effect.perform`.
-}
withPerform : Flags -> ( Model, Effect ) -> ( Model, Cmd Msg )
withPerform flags ( model, effect ) =
    ( model, Effect.perform flags effect )


init : Flags -> ( Model, Effect )
init flags =
    ( { flags = flags
      , auth = Nothing
      , gameState = Nothing
      , newMessage = ""
      , status = "Authorizing with Discord…"
      , error = Nothing
      , confirming = Nothing
      , editingSlot = Nothing
      , editingEntity = Nothing
      , inflight = []
      , dirtySlots = Set.empty
      , dirtyEntities = Set.empty
      , fieldSaveSeq = 0
      , selectedSlot = 0
      , logAtBottom = True
      , newSessionGoal = ""
      , goalEdit = ""
      , sessionControlsExpanded = False
      , proposalDrafts = Dict.empty
      , addDetailDraft = ""
      , sessionAspectEdits = Dict.empty
      , newSessionAspectNote = ""
      , newSessionAspectKind = Boon
      , loadingHistory = False
      , noMoreHistory = False
      , guideExpanded = False
      , aspectExamplesOpen = Nothing
      , connection = Connected
      , gameStateAttempts = 0
      , timeZone = Time.utc
      , rightPanelTab = NpcsLocationsTab
      , openLeftSections = { facilitator = True, characters = True, moves = False }
      , leftPanelWidth = defaultLeftPanelWidth
      , draggingDivider = False
      }
    , Effect.Batch [ Effect.Authorize, Effect.GetTimeZone ]
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.fromDiscord FromDiscordRaw
        , Ports.wsGameState WsGameStateRaw
        , Ports.wsStatus WsStatusChanged
        , if model.draggingDivider then
            Sub.batch
                [ Browser.Events.onMouseMove (Decode.map DividerDragged (Decode.field "movementX" Decode.float))
                , Browser.Events.onMouseUp (Decode.succeed DividerDragEnded)
                ]

          else
            Sub.none
        ]



-- UPDATE


{-| Show a transient failure note and schedule its own dismissal. Used for the
per-action mutation failures, which are worth flagging but not worth keeping on
screen once the user has moved on.
-}
fail : String -> Model -> ( Model, Effect )
fail message model =
    ( { model | error = Just message }, Effect.DismissErrorIn errorDismissDelay )


{-| Start a guarded mutation. If its action key already has a request in flight,
do nothing — this is what makes an impatient double-click harmless. Otherwise
mark the key busy and issue the effect (which needs auth).
-}
guard : Action -> Model -> (Auth -> Effect) -> ( Model, Effect )
guard action model toEffect =
    if Action.isPending action model.inflight then
        ( model, Effect.None )

    else
        case model.auth of
            Just auth ->
                ( { model | inflight = action :: model.inflight }, toEffect auth )

            Nothing ->
                ( model, Effect.None )


{-| Release every in-flight action of a family, once its (often shared) result
message has come back. Mutations are driven one at a time from the UI, so
clearing by family rather than exact action is enough.
-}
clearInflight : Family -> Model -> Model
clearInflight fam model =
    { model
        | inflight = List.filter (\action -> Action.family action /= fam) model.inflight
    }


{-| The in-flight action for adding a blank row to an NPC / location collection.
-}
creatingEntity : EntityKind -> Action
creatingEntity kind =
    case kind of
        Npc ->
            CreatingNpc

        Location ->
            CreatingLocation


{-| (Re)arm the field-save debounce after an edit or a blur: bump the token and
schedule a `FieldSaveDue` carrying it.
-}
armFieldSave : Model -> ( Model, Effect )
armFieldSave model =
    let
        seq =
            model.fieldSaveSeq + 1
    in
    ( { model | fieldSaveSeq = seq }, Effect.DebounceFieldSave seq fieldSaveDelay )


{-| Find an NPC / location row by id anywhere in the game state, paired with the
collection it lives in, for the debounced entity save.
-}
findEntityWithKind : String -> GameState -> Maybe ( EntityKind, TableEntity )
findEntityWithKind entityId gs =
    case findEntityAtId Npc entityId gs of
        Just entity ->
            Just ( Npc, entity )

        Nothing ->
            findEntityAtId Location entityId gs
                |> Maybe.map (\entity -> ( Location, entity ))


{-| Send every dirty character sheet / entity row as one write apiece and clear
the dirty sets. Invoked by the debounce (`FieldSaveDue`) and eagerly when the
user leaves a tab, so a whole sheet edit costs one request rather than one per
field.
-}
flushFieldSaves : Model -> ( Model, Effect )
flushFieldSaves model =
    case model.auth of
        Nothing ->
            ( model, Effect.None )

        Just auth ->
            let
                sheetSaves =
                    model.dirtySlots
                        |> Set.toList
                        |> List.filterMap
                            (\slot ->
                                model.gameState
                                    |> Maybe.andThen (\gs -> characterAtSlot slot gs.characters)
                                    |> Maybe.map (Effect.PostCharacterUpdate auth slot)
                            )

                entitySaves =
                    model.dirtyEntities
                        |> Set.toList
                        |> List.filterMap
                            (\entityId ->
                                model.gameState
                                    |> Maybe.andThen (findEntityWithKind entityId)
                                    |> Maybe.map
                                        (\( kind, entity ) -> Effect.PostUpdateEntity auth kind entity)
                            )

                effects =
                    sheetSaves ++ entitySaves
            in
            if List.isEmpty effects then
                ( model, Effect.None )

            else
                ( { model | dirtySlots = Set.empty, dirtyEntities = Set.empty }
                , Effect.Batch effects
                )


update : Msg -> Model -> ( Model, Effect )
update msg model =
    case msg of
        FromDiscordRaw value ->
            case Ports.decodeInbound value of
                Ports.BackendAuth auth ->
                    update (GotBackendAuth (Ok auth)) model

                Ports.AuthRejected message ->
                    update (AuthFailed message) model

                Ports.UnknownInbound ->
                    ( model, Effect.None )

        -- The socket opens right after this and pushes a full snapshot before
        -- its first `await`, so rather than spend an HTTP `getGameState` on the
        -- happy path, schedule a fallback load that only fires if no snapshot
        -- has landed a few seconds later.
        GotBackendAuth (Ok auth) ->
            ( { model | auth = Just auth, status = "Loaded auth as " ++ auth.username }
            , Effect.RetryGetGameStateIn gameStateRetryDelay
            )

        GotBackendAuth (Err _) ->
            ( { model | status = "Failed to authorize with backend." }, Effect.None )

        -- Seeds the board only. The socket is opened before this request is even
        -- issued, so its snapshot can already have arrived; taking this one on
        -- top of it would replace live state with an older read.
        GotGameState (Ok gs) ->
            case model.gameState of
                Just _ ->
                    ( { model | status = "Connected.", gameStateAttempts = 0 }, Effect.None )

                Nothing ->
                    ( { model
                        | gameState = Just (applyServerState model gs)
                        , status = "Connected."
                        , gameStateAttempts = 0
                      }
                    , Effect.ScrollLogToBottom
                    )

        -- The live socket is the real source of state, so a failed seed load is
        -- retried a few times with a short backoff before giving up.
        GotGameState (Err _) ->
            if model.gameState == Nothing && model.gameStateAttempts < maxGameStateAttempts then
                ( { model
                    | status = "Reconnecting to the table…"
                    , gameStateAttempts = model.gameStateAttempts + 1
                  }
                , Effect.RetryGetGameStateIn gameStateRetryDelay
                )

            else
                ( { model | status = "Failed to load game state." }, Effect.None )

        NewMessageChanged s ->
            ( { model | newMessage = s }, Effect.None )

        -- The log reports its scroll position as the viewer moves it; new
        -- messages only auto-scroll while this stays True.
        LogScrolled atBottom ->
            ( { model | logAtBottom = atBottom }, Effect.None )

        -- The snapshot only carries the most recent window of messages; this
        -- pulls the page before the oldest one currently loaded.
        LoadEarlierMessages ->
            case ( model.auth, oldestMessageMillis model.gameState ) of
                ( Just auth, Just before ) ->
                    if model.loadingHistory || model.noMoreHistory then
                        ( model, Effect.None )

                    else
                        ( { model | loadingHistory = True }
                        , Effect.GetMessageHistory auth before
                        )

                _ ->
                    ( model, Effect.None )

        GotEarlierMessages (Ok older) ->
            ( { model
                | loadingHistory = False
                , noMoreHistory = List.isEmpty older
                , gameState = Maybe.map (prependMessages older) model.gameState
              }
            , Effect.None
            )

        GotEarlierMessages (Err _) ->
            fail "Couldn't load earlier messages." { model | loadingHistory = False }

        SendMessage ->
            case ( model.auth, model.gameState ) of
                ( Just auth, Just _ ) ->
                    if String.trim model.newMessage == "" then
                        ( model, Effect.None )

                    else
                        -- Posting a message is an intent to see it: snap back to
                        -- the bottom even if reading history a moment ago.
                        ( { model | newMessage = "", logAtBottom = True }
                        , Effect.PostMessage auth model.newMessage
                        )

                _ ->
                    ( model, Effect.None )

        -- Every acknowledge-only mutation (the Worker replies 204) lands here:
        -- release the family's in-flight keys, and on failure show the transient
        -- note. The resulting state arrives separately on the socket.
        MutationDone tag result ->
            case result of
                Ok () ->
                    ( clearInflight tag.family model, Effect.None )

                Err _ ->
                    fail tag.failMsg (clearInflight tag.family model)

        ClearLog ->
            guard ClearingLog { model | confirming = Nothing } Effect.PostClearMessages

        SelectSlot slot ->
            -- Leaving a tab flushes any unsaved edits on the sheet behind it.
            flushFieldSaves { model | selectedSlot = slot }

        ClaimSlot slot ->
            -- Bring the claimed sheet's tab to the front as well.
            guard ClaimingSlot { model | selectedSlot = slot } (\auth -> Effect.PostClaimSlot auth slot)

        ReleaseSlot slot ->
            guard ReleasingSlot model (\auth -> Effect.PostReleaseSlot auth slot)

        AcceptProposal id ->
            let
                context =
                    model.proposalDrafts
                        |> Dict.get id
                        |> Maybe.map String.trim
                        |> Maybe.andThen
                            (\text ->
                                if text == "" then
                                    Nothing

                                else
                                    Just text
                            )
            in
            guard (ResolvingProposal Accepting id)
                model
                (\auth -> Effect.PostProposalDecision auth id "accept" context)

        RejectProposal id ->
            guard (ResolvingProposal Rejecting id)
                model
                (\auth -> Effect.PostProposalDecision auth id "reject" Nothing)

        WithdrawProposal id ->
            guard (ResolvingProposal Withdrawing id)
                model
                (\auth -> Effect.PostWithdrawProposal auth id)

        ProposalDraftChanged id s ->
            ( { model | proposalDrafts = Dict.insert id s model.proposalDrafts }, Effect.None )

        ProposalResolved id (Ok ()) ->
            ( clearInflight ProposalFamily { model | proposalDrafts = Dict.remove id model.proposalDrafts }
            , Effect.None
            )

        ProposalResolved _ (Err _) ->
            fail "Failed to resolve the proposal." (clearInflight ProposalFamily model)

        -- The Overcome loop (26.2). Anyone may roll; the rest are the
        -- facilitator's, and the Worker enforces that.
        PressOvercome ->
            guard RollingOvercome model Effect.PostOvercomeRoll

        RerollOvercome ->
            guard RerollingOvercome model Effect.PostOvercomeReroll

        AcceptOvercome ->
            guard AcceptingOvercome model Effect.PostOvercomeAccept

        RejectOvercome ->
            guard RejectingOvercome model Effect.PostOvercomeReject

        -- Player moves: each is queued as a proposal for the facilitator. The
        -- Moves card disables a button the player cannot afford; the Worker
        -- checks the cost again.
        ProposeHighlight ->
            guard (RaisingMove Kind.Highlight) model Effect.PostHighlight

        ProposeComplicate targetSlot ->
            guard (RaisingMove Kind.Complicate) model (\auth -> Effect.PostComplicate auth targetSlot)

        ProposeAddDetail ->
            let
                suggestion =
                    case String.trim model.addDetailDraft of
                        "" ->
                            Nothing

                        trimmed ->
                            Just trimmed
            in
            guard (RaisingMove Kind.AddDetail)
                { model | addDetailDraft = "" }
                (\auth -> Effect.PostAddDetail auth suggestion)

        ProposeAlter ->
            guard (RaisingMove Kind.Alter) model Effect.PostAlter

        ProposeUseSessionBoon sessionAspectId ->
            guard (RaisingMove Kind.UseSessionBoon) model (\auth -> Effect.PostUseSessionBoon auth sessionAspectId)

        AddDetailDraftChanged s ->
            ( { model | addDetailDraft = s }, Effect.None )

        SessionGoalChanged s ->
            ( { model | newSessionGoal = s }, Effect.None )

        SessionGoalEditChanged s ->
            ( { model | goalEdit = s }, Effect.None )

        SaveSessionGoal ->
            if String.trim model.goalEdit == "" then
                ( { model | confirming = Nothing }, Effect.None )

            else
                guard SavingGoal
                    { model | confirming = Nothing }
                    (\auth -> Effect.PostSessionGoal auth model.goalEdit)

        StartSession ->
            if String.trim model.newSessionGoal == "" then
                ( model, Effect.None )

            else
                guard StartingSession
                    { model | newSessionGoal = "" }
                    (\auth -> Effect.PostStartSession auth model.newSessionGoal)

        EndSession ->
            guard EndingSession { model | confirming = Nothing } Effect.PostEndSession

        RequestConfirm key ->
            ( { model | confirming = Just key }, Effect.None )

        CancelConfirm ->
            ( { model | confirming = Nothing }, Effect.None )

        DismissError ->
            ( { model | error = Nothing }, Effect.None )

        ToggleGuide ->
            ( { model | guideExpanded = not model.guideExpanded }, Effect.None )

        ToggleSessionControls ->
            ( { model | sessionControlsExpanded = not model.sessionControlsExpanded }, Effect.None )

        SelectRightPanelTab tab ->
            ( { model | rightPanelTab = tab }, Effect.None )

        ToggleLeftSection section ->
            ( { model | openLeftSections = toggleLeftSection section model.openLeftSections }, Effect.None )

        DividerDragStarted ->
            ( { model | draggingDivider = True }, Effect.None )

        DividerDragged deltaX ->
            ( { model
                | leftPanelWidth =
                    clamp minLeftPanelWidth maxLeftPanelWidth (model.leftPanelWidth + deltaX)
              }
            , Effect.None
            )

        DividerDragEnded ->
            ( { model | draggingDivider = False }, Effect.None )

        ToggleAspectExamples slot aspect ->
            let
                next =
                    if model.aspectExamplesOpen == Just ( slot, aspect ) then
                        Nothing

                    else
                        Just ( slot, aspect )
            in
            ( { model | aspectExamplesOpen = next }, Effect.None )

        WsStatusChanged raw ->
            ( { model | connection = connectionFromString raw }, Effect.None )

        RetryGetGameState ->
            case ( model.auth, model.gameState ) of
                ( Just auth, Nothing ) ->
                    ( model, Effect.GetGameState auth )

                _ ->
                    ( model, Effect.None )

        -- Facilitator-only hand-edits of the shared pool (23.2), independent
        -- of a draw and of each other.
        AddStone stone ->
            guard (AddingStone stone) model (\auth -> Effect.PostAddStone auth stone)

        RemoveStone stone ->
            guard (RemovingStone stone) model (\auth -> Effect.PostRemoveStone auth stone)

        SessionAspectDraftChanged s ->
            ( { model | newSessionAspectNote = s }, Effect.None )

        SessionAspectKindChanged kind ->
            ( { model | newSessionAspectKind = kind }, Effect.None )

        AddSessionAspect ->
            if String.trim model.newSessionAspectNote == "" then
                ( model, Effect.None )

            else
                guard AddingSessionAspect
                    { model | newSessionAspectNote = "" }
                    (\auth -> Effect.PostAddSessionAspect auth model.newSessionAspectKind model.newSessionAspectNote)

        UseSessionAspect sessionAspectId ->
            guard (UsingSessionAspect sessionAspectId)
                model
                (\auth -> Effect.PostUseSessionAspect auth sessionAspectId)

        UnconsumeSessionAspect sessionAspectId ->
            guard (UnconsumingSessionAspect sessionAspectId)
                model
                (\auth -> Effect.PostUnconsumeSessionAspect auth sessionAspectId)

        SessionAspectTextChanged sessionAspectId s ->
            ( { model | sessionAspectEdits = Dict.insert sessionAspectId s model.sessionAspectEdits }
            , Effect.None
            )

        -- Saved when the field loses focus, and only if it actually changed.
        SaveSessionAspectText sessionAspectId ->
            case Dict.get sessionAspectId model.sessionAspectEdits of
                Nothing ->
                    ( model, Effect.None )

                Just draft ->
                    let
                        released =
                            { model | sessionAspectEdits = Dict.remove sessionAspectId model.sessionAspectEdits }

                        current =
                            model.gameState
                                |> Maybe.andThen (\gs -> gs.sessionAspects |> List.filter (\a -> a.id == sessionAspectId) |> List.head)
                                |> Maybe.map .text
                    in
                    if String.trim draft == "" || Just (String.trim draft) == current then
                        ( released, Effect.None )

                    else
                        guard (EditingSessionAspect sessionAspectId)
                            released
                            (\auth -> Effect.PostUpdateSessionAspect auth sessionAspectId (String.trim draft))

        DeleteSessionAspect sessionAspectId ->
            guard (DeletingSessionAspect sessionAspectId)
                model
                (\auth -> Effect.PostDeleteSessionAspect auth sessionAspectId)

        -- Field edits update the local sheet at once and mark the slot dirty; the
        -- write is deferred to a single debounced flush (`FieldSaveDue`).
        CharacterFieldInput slot fieldTag value ->
            armFieldSave
                { model
                    | gameState =
                        Maybe.map (mapCharacterAtSlot slot (setCharacterField fieldTag value)) model.gameState
                    , editingSlot = Just slot
                    , dirtySlots = Set.insert slot model.dirtySlots
                }

        CharacterFieldBlur slot ->
            let
                released =
                    if model.editingSlot == Just slot then
                        { model | editingSlot = Nothing }

                    else
                        model
            in
            if Set.member slot released.dirtySlots then
                armFieldSave released

            else
                ( released, Effect.None )

        FieldSaveDue seq ->
            if seq /= model.fieldSaveSeq then
                ( model, Effect.None )

            else
                flushFieldSaves model

        FateIncrement slot ->
            guard (GrantingFate slot) model (\auth -> Effect.PostFate auth slot 1)

        FateDecrement slot ->
            guard (GrantingFate slot) model (\auth -> Effect.PostFate auth slot -1)

        AddEntity kind ->
            guard (creatingEntity kind) model (\auth -> Effect.PostCreateEntity auth kind)

        EntityFieldInput kind entityId fieldTag value ->
            armFieldSave
                { model
                    | gameState =
                        Maybe.map
                            (mapEntityAtId kind entityId (setEntityField fieldTag value))
                            model.gameState
                    , editingEntity = Just entityId
                    , dirtyEntities = Set.insert entityId model.dirtyEntities
                }

        EntityFieldBlur _ entityId ->
            let
                released =
                    if model.editingEntity == Just entityId then
                        { model | editingEntity = Nothing }

                    else
                        model
            in
            if Set.member entityId released.dirtyEntities then
                armFieldSave released

            else
                ( released, Effect.None )

        DeleteEntity kind entityId ->
            let
                released =
                    if model.editingEntity == Just entityId then
                        { model | editingEntity = Nothing }

                    else
                        model
            in
            guard (DeletingEntity entityId)
                { released | dirtyEntities = Set.remove entityId released.dirtyEntities }
                (\auth -> Effect.PostDeleteEntity auth kind entityId)

        WsGameStateRaw value ->
            case Decode.decodeValue Api.decodeGameState value of
                Ok gs ->
                    ( { model
                        | gameState = Just (applyServerState model gs)
                        , connection = Connected
                      }
                    , if model.logAtBottom then
                        Effect.ScrollLogToBottom

                      else
                        Effect.None
                    )

                Err _ ->
                    ( model, Effect.None )

        AuthFailed message ->
            ( { model | status = "Discord authorization failed: " ++ message }, Effect.None )

        GotTimeZone zone ->
            ( { model | timeZone = zone }, Effect.None )

        NoOp ->
            ( model, Effect.None )



-- STATE MERGING


{-| Accept a server snapshot, but keep every character sheet / reference row that
has a local edit not yet saved. Broadcasts arrive on every table action, and
taking the server copy wholesale would wipe a field being typed into or an edit
still sitting in the debounce window before its flush.
-}
applyServerState : Model -> GameState -> GameState
applyServerState model incoming =
    let
        dirtySlots =
            case model.editingSlot of
                Just slot ->
                    Set.insert slot model.dirtySlots

                Nothing ->
                    model.dirtySlots

        dirtyEntities =
            case model.editingEntity of
                Just entityId ->
                    Set.insert entityId model.dirtyEntities

                Nothing ->
                    model.dirtyEntities
    in
    case model.gameState of
        Just local ->
            incoming
                |> (\gs -> Set.foldl (keepLocalCharacter local) gs dirtySlots)
                |> (\gs -> Set.foldl (keepLocalEntity local) gs dirtyEntities)

        Nothing ->
            incoming


keepLocalCharacter : GameState -> Int -> GameState -> GameState
keepLocalCharacter local slot incoming =
    case characterAtSlot slot local.characters of
        Just localCharacter ->
            mapCharacterAtSlot slot (\_ -> localCharacter) incoming

        Nothing ->
            incoming


keepLocalEntity : GameState -> String -> GameState -> GameState
keepLocalEntity local entityId incoming =
    case findEntityWithKind entityId local of
        Just ( kind, localEntity ) ->
            mapEntityAtId kind entityId (\_ -> localEntity) incoming

        Nothing ->
            incoming


findEntityAtId : EntityKind -> String -> GameState -> Maybe TableEntity
findEntityAtId kind entityId gs =
    entitiesForKind kind gs |> List.filter (\e -> e.id == entityId) |> List.head


mapEntityAtId : EntityKind -> String -> (TableEntity -> TableEntity) -> GameState -> GameState
mapEntityAtId kind entityId f gs =
    let
        apply entities =
            List.map
                (\e ->
                    if e.id == entityId then
                        f e

                    else
                        e
                )
                entities
    in
    case kind of
        Npc ->
            { gs | npcs = apply gs.npcs }

        Location ->
            { gs | locations = apply gs.locations }


{-| POSIX-millisecond timestamp of the oldest message currently loaded — the
cursor the "load earlier" fetch asks for rows before. Messages are ordered oldest
first, so this is the head.
-}
oldestMessageMillis : Maybe GameState -> Maybe Int
oldestMessageMillis maybeGs =
    maybeGs
        |> Maybe.andThen (.messages >> List.head)
        |> Maybe.map (.createdAt >> Time.posixToMillis)


{-| Prepend a page of older messages, dropping any already present (a broadcast
could have re-sent an overlapping row) and keeping oldest-first order.
-}
prependMessages : List Message -> GameState -> GameState
prependMessages older gs =
    let
        knownIds =
            List.map .id gs.messages |> Set.fromList

        fresh =
            List.filter (\m -> not (Set.member m.id knownIds)) older
    in
    { gs | messages = fresh ++ gs.messages }


mapCharacterAtSlot : Int -> (CharacterSheet -> CharacterSheet) -> GameState -> GameState
mapCharacterAtSlot slot f gs =
    { gs
        | characters =
            List.map
                (\c ->
                    if c.slot == slot then
                        f c

                    else
                        c
                )
                gs.characters
    }
