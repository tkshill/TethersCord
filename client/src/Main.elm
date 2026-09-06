module Main exposing (applyServerState, init, main, update)

{-| Program wiring only: `init`, `update`, `subscriptions`, `main`. Domain types
and `Model` / `Msg` live in `Types`; HTTP in `Api`; interop in `Ports`; the view
in `View`.

`update` returns `( Model, Effect )` — a pure value — and `Effect.perform` turns
that into a `Cmd` once, here at the boundary.

-}

import Api
import Browser
import Dict
import Effect exposing (Effect)
import Json.Decode as Decode
import Ports
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


{-| Idle time after the last Highlight +/- tap before the coalesced net pledge is
sent as a single proposal.
-}
pledgeDelay : Float
pledgeDelay =
    700


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
      , inflight = Set.empty
      , dirtySlots = Set.empty
      , dirtyEntities = Set.empty
      , fieldSaveSeq = 0
      , pendingPledgeDelta = 0
      , pledgeSeq = 0
      , selectedSlot = 0
      , logAtBottom = True
      , newSessionGoal = ""
      , goalEdit = ""
      , proposalDrafts = Dict.empty
      , loadingHistory = False
      , noMoreHistory = False
      , connection = Connected
      , gameStateAttempts = 0
      , timeZone = Time.utc
      }
    , Effect.Batch [ Effect.Authorize, Effect.GetTimeZone ]
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.fromDiscord FromDiscordRaw
        , Ports.wsGameState WsGameStateRaw
        , Ports.wsStatus WsStatusChanged
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
guard : String -> Model -> (Auth -> Effect) -> ( Model, Effect )
guard key model toEffect =
    if Set.member key model.inflight then
        ( model, Effect.None )

    else
        case model.auth of
            Just auth ->
                ( { model | inflight = Set.insert key model.inflight }, toEffect auth )

            Nothing ->
                ( model, Effect.None )


{-| Release every in-flight key sharing a prefix, once its (often shared) result
message has come back. Mutations are driven one at a time from the UI, so
clearing by family rather than exact key is enough.
-}
clearInflight : String -> Model -> Model
clearInflight prefix model =
    { model
        | inflight = Set.filter (\key -> not (String.startsWith prefix key)) model.inflight
    }


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


{-| Accumulate a Highlight +/- tap into the pending net delta and arm the pledge
debounce.
-}
armPledge : Int -> Model -> ( Model, Effect )
armPledge step model =
    let
        seq =
            model.pledgeSeq + 1
    in
    ( { model | pendingPledgeDelta = model.pendingPledgeDelta + step, pledgeSeq = seq }
    , Effect.DebouncePledge seq pledgeDelay
    )


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
                                    |> Maybe.andThen (findCharacterAtSlot slot)
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

        -- Mutations acknowledge only; the resulting state arrives on the socket.
        MessagePosted (Ok ()) ->
            ( model, Effect.None )

        MessagePosted (Err _) ->
            fail "Failed to post message." model

        ClearLog ->
            guard "log:clear" { model | confirming = Nothing } Effect.PostClearMessages

        LogCleared (Ok ()) ->
            ( clearInflight "log:" model, Effect.None )

        LogCleared (Err _) ->
            fail "Failed to clear the log." (clearInflight "log:" model)

        AddBoon ->
            guard "stones:add-boon" model (\auth -> Effect.PostStones auth "/stones/add-boon")

        -- The +/- taps only nudge a running total; one coalesced proposal is
        -- sent once the taps stop (`PledgeDue`).
        CommitBoonIncrement ->
            armPledge 1 model

        CommitBoonDecrement ->
            armPledge -1 model

        PledgeDue seq ->
            if seq /= model.pledgeSeq || model.pendingPledgeDelta == 0 then
                ( model, Effect.None )

            else
                case model.auth of
                    Just auth ->
                        ( { model
                            | pendingPledgeDelta = 0
                            , inflight = Set.insert "stones:pledge" model.inflight
                          }
                        , Effect.PostCommitBoon auth model.pendingPledgeDelta
                        )

                    Nothing ->
                        ( { model | pendingPledgeDelta = 0 }, Effect.None )

        SelectSlot slot ->
            -- Leaving a tab flushes any unsaved edits on the sheet behind it.
            flushFieldSaves { model | selectedSlot = slot }

        ClaimSlot slot ->
            -- Bring the claimed sheet's tab to the front as well.
            guard "slot:claim" { model | selectedSlot = slot } (\auth -> Effect.PostClaimSlot auth slot)

        ReleaseSlot slot ->
            guard "slot:release" model (\auth -> Effect.PostReleaseSlot auth slot)

        SlotClaimed (Ok ()) ->
            ( clearInflight "slot:" model, Effect.None )

        SlotClaimed (Err _) ->
            fail "Couldn't claim that character sheet." (clearInflight "slot:" model)

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
            guard ("proposal:accept:" ++ id)
                model
                (\auth -> Effect.PostProposalDecision auth id "accept" context)

        RejectProposal id ->
            guard ("proposal:reject:" ++ id)
                model
                (\auth -> Effect.PostProposalDecision auth id "reject" Nothing)

        WithdrawProposal id ->
            guard ("proposal:withdraw:" ++ id)
                model
                (\auth -> Effect.PostWithdrawProposal auth id)

        ProposalDraftChanged id s ->
            ( { model | proposalDrafts = Dict.insert id s model.proposalDrafts }, Effect.None )

        ProposalResolved id (Ok ()) ->
            ( clearInflight "proposal:" { model | proposalDrafts = Dict.remove id model.proposalDrafts }
            , Effect.None
            )

        ProposalResolved _ (Err _) ->
            fail "Failed to resolve the proposal." (clearInflight "proposal:" model)

        UseAbility kind ->
            guard ("move:" ++ kind) model (\auth -> Effect.PostUseAbility auth kind)

        SuggestCompel targetSlot ->
            guard "move:suggest-compel" model (\auth -> Effect.PostSuggestCompel auth targetSlot)

        AcceptCompelMove ->
            guard "move:accept-compel" model Effect.PostAcceptCompelMove

        UseFloatingBoon floatingId ->
            guard "move:use-floating" model (\auth -> Effect.PostUseFloatingBoon auth floatingId)

        MoveRaised (Ok ()) ->
            ( clearInflight "move:" model, Effect.None )

        MoveRaised (Err _) ->
            fail "Couldn't raise that move." (clearInflight "move:" model)

        SessionGoalChanged s ->
            ( { model | newSessionGoal = s }, Effect.None )

        SessionGoalEditChanged s ->
            ( { model | goalEdit = s }, Effect.None )

        SaveSessionGoal ->
            if String.trim model.goalEdit == "" then
                ( { model | confirming = Nothing }, Effect.None )

            else
                guard "session:goal"
                    { model | confirming = Nothing }
                    (\auth -> Effect.PostSessionGoal auth model.goalEdit)

        StartSession ->
            if String.trim model.newSessionGoal == "" then
                ( model, Effect.None )

            else
                guard "session:start"
                    { model | newSessionGoal = "" }
                    (\auth -> Effect.PostStartSession auth model.newSessionGoal)

        EndSession ->
            guard "session:end" { model | confirming = Nothing } Effect.PostEndSession

        SessionUpdated (Ok ()) ->
            ( clearInflight "session:" model, Effect.None )

        SessionUpdated (Err _) ->
            fail "Failed to update the session." (clearInflight "session:" model)

        ResolveUntether ->
            guard "untether:resolve" { model | confirming = Nothing } Effect.PostUntetherResolve

        UntetherResolved (Ok ()) ->
            ( clearInflight "untether:" model, Effect.None )

        UntetherResolved (Err _) ->
            fail "Failed to resolve the untether." (clearInflight "untether:" model)

        RequestConfirm key ->
            ( { model | confirming = Just key }, Effect.None )

        CancelConfirm ->
            ( { model | confirming = Nothing }, Effect.None )

        DismissError ->
            ( { model | error = Nothing }, Effect.None )

        WsStatusChanged raw ->
            ( { model | connection = connectionFromString raw }, Effect.None )

        RetryGetGameState ->
            case ( model.auth, model.gameState ) of
                ( Just auth, Nothing ) ->
                    ( model, Effect.GetGameState auth )

                _ ->
                    ( model, Effect.None )

        RollStones ->
            guard "stones:roll" model (\auth -> Effect.PostStones auth "/stones/roll")

        RerollStones ->
            guard "stones:reroll" model (\auth -> Effect.PostStones auth "/stones/reroll")

        AcceptRoll ->
            guard "stones:accept" model (\auth -> Effect.PostStones auth "/stones/accept")

        StonesUpdated (Ok ()) ->
            ( clearInflight "stones:" model, Effect.None )

        StonesUpdated (Err _) ->
            fail "Failed to update stones." (clearInflight "stones:" model)

        StartOvercome slot ->
            guard "overcome:start" model (\auth -> Effect.PostStartOvercome auth slot)

        CancelOvercome ->
            guard "overcome:cancel" model Effect.PostCancelOvercome

        OvercomeUpdated (Ok ()) ->
            ( clearInflight "overcome:" model, Effect.None )

        OvercomeUpdated (Err _) ->
            fail "Failed to update the overcome." (clearInflight "overcome:" model)

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
            guard ("fate:" ++ String.fromInt slot) model (\auth -> Effect.PostFate auth slot 1)

        FateDecrement slot ->
            guard ("fate:" ++ String.fromInt slot) model (\auth -> Effect.PostFate auth slot -1)

        CharacterUpdated (Ok ()) ->
            ( clearInflight "fate:" model, Effect.None )

        CharacterUpdated (Err _) ->
            fail "Failed to update character sheet." (clearInflight "fate:" model)

        AddEntity kind ->
            guard ("entity:create:" ++ entityKindPath kind) model (\auth -> Effect.PostCreateEntity auth kind)

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
            guard ("entity:delete:" ++ entityId)
                { released | dirtyEntities = Set.remove entityId released.dirtyEntities }
                (\auth -> Effect.PostDeleteEntity auth kind entityId)

        EntityMutated (Ok ()) ->
            ( clearInflight "entity:" model, Effect.None )

        EntityMutated (Err _) ->
            fail "Failed to update the table entry." (clearInflight "entity:" model)

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
    case findCharacterAtSlot slot local of
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


findCharacterAtSlot : Int -> GameState -> Maybe CharacterSheet
findCharacterAtSlot slot gs =
    List.filter (\c -> c.slot == slot) gs.characters |> List.head


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
