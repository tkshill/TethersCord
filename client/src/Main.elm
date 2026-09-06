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
import Task
import Time
import Types exposing (..)
import View


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
      , logAtBottom = True
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
                    ( { model | status = "Connected." }, Cmd.none )

                Nothing ->
                    ( { model
                        | gameState = Just (applyServerState model gs)
                        , status = "Connected."
                      }
                    , scrollLogToBottom
                    )

        GotGameState (Err _) ->
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

        CommitBoonIncrement slot ->
            ( model, commitCmd model slot 1 )

        CommitBoonDecrement slot ->
            ( model, commitCmd model slot -1 )

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
                    ( { model | gameState = Just (applyServerState model gs) }
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


commitCmd : Model -> Int -> Int -> Cmd Msg
commitCmd model slot delta =
    case model.auth of
        Just auth ->
            Api.postCommitBoon model.flags auth slot delta StonesUpdated

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
