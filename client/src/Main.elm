module Main exposing (main)

{-| Program wiring only: `init`, `update`, `subscriptions`, `main`. Domain types
and `Model` / `Msg` live in `Types`; HTTP in `Api`; interop in `Ports`; the view
in `View`.
-}

import Api
import Browser
import Browser.Dom
import Json.Decode as Decode
import Ports
import Process
import Task
import Time
import Types exposing (..)
import View


{-| How many times the initial game-state seed is retried before giving up.
-}
maxGameStateAttempts : Int
maxGameStateAttempts =
    3


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
        { init = init
        , update = update
        , view = View.view
        , subscriptions = subscriptions
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { flags = flags
      , auth = Nothing
      , gameState = Nothing
      , newMessage = ""
      , status = "Authorizing with Discord…"
      , editingSlot = Nothing
      , selectedSlot = 0
      , logAtBottom = True
      , newSessionGoal = ""
      , proposalDraft = ""
      , connection = Connected
      , gameStateAttempts = 0
      , timeZone = Time.utc
      }
    , Cmd.batch
        [ Ports.authorize [ "identify" ]
        , Task.perform GotTimeZone Time.here
        ]
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.fromDiscord FromDiscordRaw
        , Ports.wsGameState WsGameStateRaw
        , Ports.wsStatus WsStatusChanged
        ]



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromDiscordRaw value ->
            case Ports.decodeInbound value of
                Ports.BackendAuth auth ->
                    update (GotBackendAuth (Ok auth)) model

                Ports.AuthRejected message ->
                    update (AuthFailed message) model

                Ports.UnknownInbound ->
                    ( model, Cmd.none )

        GotBackendAuth (Ok auth) ->
            ( { model | auth = Just auth, status = "Loaded auth as " ++ auth.username }
            , Api.getGameState model.flags auth GotGameState
            )

        GotBackendAuth (Err _) ->
            ( { model | status = "Failed to authorize with backend." }, Cmd.none )

        -- Seeds the board only. The socket is opened before this request is even
        -- issued, so its snapshot can already have arrived; taking this one on
        -- top of it would replace live state with an older read.
        GotGameState (Ok gs) ->
            case model.gameState of
                Just _ ->
                    ( { model | status = "Connected.", gameStateAttempts = 0 }, Cmd.none )

                Nothing ->
                    ( { model
                        | gameState = Just (applyServerState model gs)
                        , status = "Connected."
                        , gameStateAttempts = 0
                      }
                    , scrollLogToBottom
                    )

        -- The live socket is the real source of state, so a failed seed load is
        -- retried a few times with a short backoff before giving up.
        GotGameState (Err _) ->
            if model.gameState == Nothing && model.gameStateAttempts < maxGameStateAttempts then
                ( { model
                    | status = "Reconnecting to the table…"
                    , gameStateAttempts = model.gameStateAttempts + 1
                  }
                , Process.sleep 2000 |> Task.perform (\_ -> RetryGetGameState)
                )

            else
                ( { model | status = "Failed to load game state." }, Cmd.none )

        NewMessageChanged s ->
            ( { model | newMessage = s }, Cmd.none )

        -- The log reports its scroll position as the viewer moves it; new
        -- messages only auto-scroll while this stays True.
        LogScrolled atBottom ->
            ( { model | logAtBottom = atBottom }, Cmd.none )

        SendMessage ->
            case ( model.auth, model.gameState ) of
                ( Just auth, Just _ ) ->
                    if String.trim model.newMessage == "" then
                        ( model, Cmd.none )

                    else
                        -- Posting a message is an intent to see it: snap back to
                        -- the bottom even if reading history a moment ago.
                        ( { model | newMessage = "", logAtBottom = True }
                        , Api.postMessage model.flags auth model.newMessage MessagePosted
                        )

                _ ->
                    ( model, Cmd.none )

        -- Mutations acknowledge only; the resulting state arrives on the socket.
        MessagePosted (Ok ()) ->
            ( model, Cmd.none )

        MessagePosted (Err _) ->
            ( { model | status = "Failed to post message." }, Cmd.none )

        ClearLog ->
            case model.auth of
                Just auth ->
                    ( model, Api.postClearMessages model.flags auth LogCleared )

                Nothing ->
                    ( model, Cmd.none )

        LogCleared (Ok ()) ->
            ( model, Cmd.none )

        LogCleared (Err _) ->
            ( { model | status = "Failed to clear the log." }, Cmd.none )

        AddBoon ->
            ( model, stonesCmd model "/stones/add-boon" )

        CommitBoonIncrement ->
            ( model, commitCmd model 1 )

        CommitBoonDecrement ->
            ( model, commitCmd model -1 )

        SelectSlot slot ->
            ( { model | selectedSlot = slot }, Cmd.none )

        ClaimSlot slot ->
            -- Bring the claimed sheet's tab to the front as well.
            ( { model | selectedSlot = slot }, claimCmd model slot )

        ReleaseSlot slot ->
            ( model, releaseCmd model slot )

        SlotClaimed (Ok ()) ->
            ( model, Cmd.none )

        SlotClaimed (Err _) ->
            ( { model | status = "Couldn't claim that character sheet." }, Cmd.none )

        AcceptProposal id ->
            let
                context =
                    case String.trim model.proposalDraft of
                        "" ->
                            Nothing

                        text ->
                            Just text
            in
            ( model, proposalCmd model id "accept" context )

        RejectProposal id ->
            ( model, proposalCmd model id "reject" Nothing )

        ProposalDraftChanged s ->
            ( { model | proposalDraft = s }, Cmd.none )

        ProposalResolved (Ok ()) ->
            ( { model | proposalDraft = "" }, Cmd.none )

        ProposalResolved (Err _) ->
            ( { model | status = "Failed to resolve the proposal." }, Cmd.none )

        UseAbility kind ->
            case model.auth of
                Just auth ->
                    ( model, Api.postUseAbility model.flags auth kind MoveRaised )

                Nothing ->
                    ( model, Cmd.none )

        AcceptCompelMove ->
            case model.auth of
                Just auth ->
                    ( model, Api.postAcceptCompelMove model.flags auth MoveRaised )

                Nothing ->
                    ( model, Cmd.none )

        UseFloatingBoon floatingId ->
            case model.auth of
                Just auth ->
                    ( model, Api.postUseFloatingBoon model.flags auth floatingId MoveRaised )

                Nothing ->
                    ( model, Cmd.none )

        MoveRaised (Ok ()) ->
            ( model, Cmd.none )

        MoveRaised (Err _) ->
            ( { model | status = "Couldn't raise that move." }, Cmd.none )

        SessionGoalChanged s ->
            ( { model | newSessionGoal = s }, Cmd.none )

        StartSession ->
            case ( model.auth, String.trim model.newSessionGoal == "" ) of
                ( Just auth, False ) ->
                    ( { model | newSessionGoal = "" }
                    , Api.postStartSession model.flags auth model.newSessionGoal SessionUpdated
                    )

                _ ->
                    ( model, Cmd.none )

        EndSession ->
            case model.auth of
                Just auth ->
                    ( model, Api.postEndSession model.flags auth SessionUpdated )

                Nothing ->
                    ( model, Cmd.none )

        SessionUpdated (Ok ()) ->
            ( model, Cmd.none )

        SessionUpdated (Err _) ->
            ( { model | status = "Failed to update the session." }, Cmd.none )

        WsStatusChanged raw ->
            ( { model | connection = connectionFromString raw }, Cmd.none )

        RetryGetGameState ->
            case ( model.auth, model.gameState ) of
                ( Just auth, Nothing ) ->
                    ( model, Api.getGameState model.flags auth GotGameState )

                _ ->
                    ( model, Cmd.none )

        RollStones ->
            ( model, stonesCmd model "/stones/roll" )

        RerollStones ->
            ( model, stonesCmd model "/stones/reroll" )

        AcceptRoll ->
            ( model, stonesCmd model "/stones/accept" )

        StonesUpdated (Ok ()) ->
            ( model, Cmd.none )

        StonesUpdated (Err _) ->
            ( { model | status = "Failed to update stones." }, Cmd.none )

        StartOvercome slot ->
            case model.auth of
                Just auth ->
                    ( model, Api.postStartOvercome model.flags auth slot OvercomeUpdated )

                Nothing ->
                    ( model, Cmd.none )

        CancelOvercome ->
            case model.auth of
                Just auth ->
                    ( model, Api.postCancelOvercome model.flags auth OvercomeUpdated )

                Nothing ->
                    ( model, Cmd.none )

        OvercomeUpdated (Ok ()) ->
            ( model, Cmd.none )

        OvercomeUpdated (Err _) ->
            ( { model | status = "Failed to update the overcome." }, Cmd.none )

        CharacterFieldInput slot fieldTag value ->
            ( { model
                | gameState =
                    Maybe.map (mapCharacterAtSlot slot (setCharacterField fieldTag value)) model.gameState
                , editingSlot = Just slot
              }
            , Cmd.none
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
                    ( released
                    , Api.postCharacterUpdate model.flags auth slot character CharacterUpdated
                    )

                _ ->
                    ( released, Cmd.none )

        FateIncrement slot ->
            ( model, fateCmd model slot 1 )

        FateDecrement slot ->
            ( model, fateCmd model slot -1 )

        CharacterUpdated (Ok ()) ->
            ( model, Cmd.none )

        CharacterUpdated (Err _) ->
            ( { model | status = "Failed to update character sheet." }, Cmd.none )

        WsGameStateRaw value ->
            case Decode.decodeValue Api.decodeGameState value of
                Ok gs ->
                    ( { model
                        | gameState = Just (applyServerState model gs)
                        , connection = Connected
                      }
                    , if model.logAtBottom then
                        scrollLogToBottom

                      else
                        Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        AuthFailed message ->
            ( { model | status = "Discord authorization failed: " ++ message }, Cmd.none )

        GotTimeZone zone ->
            ( { model | timeZone = zone }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )



-- COMMANDS


stonesCmd : Model -> String -> Cmd Msg
stonesCmd model path =
    case model.auth of
        Just auth ->
            Api.postStones model.flags auth path StonesUpdated

        Nothing ->
            Cmd.none


fateCmd : Model -> Int -> Int -> Cmd Msg
fateCmd model slot delta =
    case model.auth of
        Just auth ->
            Api.postFate model.flags auth slot delta CharacterUpdated

        Nothing ->
            Cmd.none


commitCmd : Model -> Int -> Cmd Msg
commitCmd model delta =
    case model.auth of
        Just auth ->
            Api.postCommitBoon model.flags auth delta StonesUpdated

        Nothing ->
            Cmd.none


claimCmd : Model -> Int -> Cmd Msg
claimCmd model slot =
    case model.auth of
        Just auth ->
            Api.postClaimSlot model.flags auth slot SlotClaimed

        Nothing ->
            Cmd.none


releaseCmd : Model -> Int -> Cmd Msg
releaseCmd model slot =
    case model.auth of
        Just auth ->
            Api.postReleaseSlot model.flags auth slot SlotClaimed

        Nothing ->
            Cmd.none


proposalCmd : Model -> String -> String -> Maybe String -> Cmd Msg
proposalCmd model id decision context =
    case model.auth of
        Just auth ->
            Api.postProposalDecision model.flags auth id decision context ProposalResolved

        Nothing ->
            Cmd.none


{-| Jump the message log to the bottom. Runs after the view has been patched;
if the log is not on screen the task fails and is ignored.
-}
scrollLogToBottom : Cmd Msg
scrollLogToBottom =
    Browser.Dom.setViewportOf View.logDomId 0 1.0e7
        |> Task.attempt (\_ -> NoOp)



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
