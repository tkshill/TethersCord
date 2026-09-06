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
import Time
import Types exposing (..)
import View


{-| How many times the initial game-state seed is retried before giving up.
-}
maxGameStateAttempts : Int
maxGameStateAttempts =
    3


{-| Backoff before a retried game-state seed load, in milliseconds.
-}
gameStateRetryDelay : Float
gameStateRetryDelay =
    2000


{-| How long a transient error stays on screen before it dismisses itself, in
milliseconds.
-}
errorDismissDelay : Float
errorDismissDelay =
    6000


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
      , selectedSlot = 0
      , logAtBottom = True
      , newSessionGoal = ""
      , goalEdit = ""
      , proposalDrafts = Dict.empty
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


{-| Issue an effect that needs an authenticated user, or nothing if there is no
auth yet. Covers the many branches that were `case model.auth of Just auth -> …`.
-}
withAuth : Model -> (Auth -> Effect) -> ( Model, Effect )
withAuth model toEffect =
    case model.auth of
        Just auth ->
            ( model, toEffect auth )

        Nothing ->
            ( model, Effect.None )


{-| Show a transient failure note and schedule its own dismissal. Used for the
per-action mutation failures, which are worth flagging but not worth keeping on
screen once the user has moved on.
-}
fail : String -> Model -> ( Model, Effect )
fail message model =
    ( { model | error = Just message }, Effect.DismissErrorIn errorDismissDelay )


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

        GotBackendAuth (Ok auth) ->
            ( { model | auth = Just auth, status = "Loaded auth as " ++ auth.username }
            , Effect.GetGameState auth
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
            withAuth { model | confirming = Nothing } Effect.PostClearMessages

        LogCleared (Ok ()) ->
            ( model, Effect.None )

        LogCleared (Err _) ->
            fail "Failed to clear the log." model

        AddBoon ->
            withAuth model (\auth -> Effect.PostStones auth "/stones/add-boon")

        CommitBoonIncrement ->
            withAuth model (\auth -> Effect.PostCommitBoon auth 1)

        CommitBoonDecrement ->
            withAuth model (\auth -> Effect.PostCommitBoon auth -1)

        SelectSlot slot ->
            ( { model | selectedSlot = slot }, Effect.None )

        ClaimSlot slot ->
            -- Bring the claimed sheet's tab to the front as well.
            withAuth { model | selectedSlot = slot } (\auth -> Effect.PostClaimSlot auth slot)

        ReleaseSlot slot ->
            withAuth model (\auth -> Effect.PostReleaseSlot auth slot)

        SlotClaimed (Ok ()) ->
            ( model, Effect.None )

        SlotClaimed (Err _) ->
            fail "Couldn't claim that character sheet." model

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
            withAuth model (\auth -> Effect.PostProposalDecision auth id "accept" context)

        RejectProposal id ->
            withAuth model (\auth -> Effect.PostProposalDecision auth id "reject" Nothing)

        WithdrawProposal id ->
            withAuth model (\auth -> Effect.PostWithdrawProposal auth id)

        ProposalDraftChanged id s ->
            ( { model | proposalDrafts = Dict.insert id s model.proposalDrafts }, Effect.None )

        ProposalResolved id (Ok ()) ->
            ( { model | proposalDrafts = Dict.remove id model.proposalDrafts }, Effect.None )

        ProposalResolved _ (Err _) ->
            fail "Failed to resolve the proposal." model

        UseAbility kind ->
            withAuth model (\auth -> Effect.PostUseAbility auth kind)

        SuggestCompel targetSlot ->
            withAuth model (\auth -> Effect.PostSuggestCompel auth targetSlot)

        AcceptCompelMove ->
            withAuth model Effect.PostAcceptCompelMove

        UseFloatingBoon floatingId ->
            withAuth model (\auth -> Effect.PostUseFloatingBoon auth floatingId)

        MoveRaised (Ok ()) ->
            ( model, Effect.None )

        MoveRaised (Err _) ->
            fail "Couldn't raise that move." model

        SessionGoalChanged s ->
            ( { model | newSessionGoal = s }, Effect.None )

        SessionGoalEditChanged s ->
            ( { model | goalEdit = s }, Effect.None )

        SaveSessionGoal ->
            case ( model.auth, String.trim model.goalEdit == "" ) of
                ( Just auth, False ) ->
                    ( { model | confirming = Nothing }
                    , Effect.PostSessionGoal auth model.goalEdit
                    )

                _ ->
                    ( { model | confirming = Nothing }, Effect.None )

        StartSession ->
            case ( model.auth, String.trim model.newSessionGoal == "" ) of
                ( Just auth, False ) ->
                    ( { model | newSessionGoal = "" }
                    , Effect.PostStartSession auth model.newSessionGoal
                    )

                _ ->
                    ( model, Effect.None )

        EndSession ->
            withAuth { model | confirming = Nothing } Effect.PostEndSession

        SessionUpdated (Ok ()) ->
            ( model, Effect.None )

        SessionUpdated (Err _) ->
            fail "Failed to update the session." model

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
            withAuth model (\auth -> Effect.PostStones auth "/stones/roll")

        RerollStones ->
            withAuth model (\auth -> Effect.PostStones auth "/stones/reroll")

        AcceptRoll ->
            withAuth model (\auth -> Effect.PostStones auth "/stones/accept")

        StonesUpdated (Ok ()) ->
            ( model, Effect.None )

        StonesUpdated (Err _) ->
            fail "Failed to update stones." model

        StartOvercome slot ->
            withAuth model (\auth -> Effect.PostStartOvercome auth slot)

        CancelOvercome ->
            withAuth model Effect.PostCancelOvercome

        OvercomeUpdated (Ok ()) ->
            ( model, Effect.None )

        OvercomeUpdated (Err _) ->
            fail "Failed to update the overcome." model

        CharacterFieldInput slot fieldTag value ->
            ( { model
                | gameState =
                    Maybe.map (mapCharacterAtSlot slot (setCharacterField fieldTag value)) model.gameState
                , editingSlot = Just slot
              }
            , Effect.None
            )

        CharacterFieldBlur slot ->
            let
                released =
                    if model.editingSlot == Just slot then
                        { model | editingSlot = Nothing }

                    else
                        model
            in
            case ( model.auth, model.gameState |> Maybe.andThen (findCharacterAtSlot slot) ) of
                ( Just auth, Just character ) ->
                    ( released, Effect.PostCharacterUpdate auth slot character )

                _ ->
                    ( released, Effect.None )

        FateIncrement slot ->
            withAuth model (\auth -> Effect.PostFate auth slot 1)

        FateDecrement slot ->
            withAuth model (\auth -> Effect.PostFate auth slot -1)

        CharacterUpdated (Ok ()) ->
            ( model, Effect.None )

        CharacterUpdated (Err _) ->
            fail "Failed to update character sheet." model

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


{-| Accept a server snapshot, but keep the character sheet the user is part-way
through typing into. Broadcasts arrive on every table action, and replacing the
whole state wholesale would wipe the field under the cursor.
-}
applyServerState : Model -> GameState -> GameState
applyServerState model incoming =
    case ( model.editingSlot, model.gameState ) of
        ( Just slot, Just local ) ->
            case findCharacterAtSlot slot local of
                Just localCharacter ->
                    mapCharacterAtSlot slot (\_ -> localCharacter) incoming

                Nothing ->
                    incoming

        _ ->
            incoming


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
