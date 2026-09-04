port module Main exposing (main)

import Browser
import Html exposing (Html, button, div, h1, input, li, text, ul)
import Html.Attributes exposing (..)
import Html.Events exposing (onBlur, onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Roll exposing (Stone(..))
import Time



-- FLAGS


type alias Flags =
    { apiBaseUrl : String
    , tableId : String
    }



-- MODEL


type Role
    = Facilitator
    | Player


type alias Auth =
    { userId : String
    , username : String
    , role : Role
    , sessionToken : String
    }


type alias Message =
    { id : String
    , authorId : String
    , authorName : String
    , role : Role
    , content : String
    , createdAt : Time.Posix
    }


type alias PendingRoll =
    { chosen : List Stone
    , rest : List Stone
    }


type alias CharacterSheet =
    { id : String
    , slot : Int
    , name : String
    , notableFeatures : String
    , archetype : String
    , desire : String
    , quest : String
    , condition : String
    , notes : String
    , fate : Int
    }


type CharacterField
    = NameField
    | NotableFeaturesField
    | ArchetypeField
    | DesireField
    | QuestField
    | ConditionField
    | NotesField


setCharacterField : CharacterField -> String -> CharacterSheet -> CharacterSheet
setCharacterField field value character =
    case field of
        NameField ->
            { character | name = value }

        NotableFeaturesField ->
            { character | notableFeatures = value }

        ArchetypeField ->
            { character | archetype = value }

        DesireField ->
            { character | desire = value }

        QuestField ->
            { character | quest = value }

        ConditionField ->
            { character | condition = value }

        NotesField ->
            { character | notes = value }


type alias GameState =
    { sessionId : String
    , messages : List Message
    , stonePool : List Stone
    , pendingRoll : Maybe PendingRoll
    , characters : List CharacterSheet
    }


type alias Model =
    { flags : Flags
    , auth : Maybe Auth
    , gameState : Maybe GameState
    , newMessage : String
    , status : String

    -- Slot the user is currently typing into, if any. Server pushes must not
    -- overwrite a sheet while it is being edited.
    , editingSlot : Maybe Int
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { flags = flags
      , auth = Nothing
      , gameState = Nothing
      , newMessage = ""
      , status = "Authorizing with Discord..."
      , editingSlot = Nothing
      }
    , authorizeCmd [ "identify" ]
    )



-- MESSAGES


type Msg
    = GotBackendAuth (Result Http.Error Auth)
    | GotGameState (Result Http.Error GameState)
    | NewMessageChanged String
    | SendMessage
    | MessagePosted (Result Http.Error ())
    | FromDiscordRaw Decode.Value
    | AddWhiteStone
    | RollStones
    | RerollStones
    | AcceptRoll
    | StonesUpdated (Result Http.Error ())
    | CharacterFieldInput Int CharacterField String
    | CharacterFieldBlur Int
    | FateIncrement Int
    | FateDecrement Int
    | CharacterUpdated (Result Http.Error ())
    | WsGameStateRaw Decode.Value
    | AuthFailed String
    | NoOp



-- PORTS


port toDiscord : Encode.Value -> Cmd msg


port fromDiscord : (Decode.Value -> msg) -> Sub msg


port wsGameState : (Decode.Value -> msg) -> Sub msg


authorizeCmd : List String -> Cmd Msg
authorizeCmd scopes =
    toDiscord <|
        Encode.object
            [ ( "type", Encode.string "Authorize" )
            , ( "scopes", Encode.list Encode.string scopes )
            ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ fromDiscord FromDiscordRaw
        , wsGameState WsGameStateRaw
        ]



-- DECODERS / ENCODERS


decodeRole : Decode.Decoder Role
decodeRole =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "facilitator" ->
                        Decode.succeed Facilitator

                    "player" ->
                        Decode.succeed Player

                    _ ->
                        Decode.fail "Unknown role"
            )


decodeAuth : Decode.Decoder Auth
decodeAuth =
    Decode.map4 Auth
        (Decode.field "userId" Decode.string)
        (Decode.field "username" Decode.string)
        (Decode.field "role" decodeRole)
        (Decode.field "sessionToken" Decode.string)


decodeMessage : Decode.Decoder Message
decodeMessage =
    Decode.map6 Message
        (Decode.field "id" Decode.string)
        (Decode.field "authorId" Decode.string)
        (Decode.field "authorName" Decode.string)
        (Decode.field "role" decodeRole)
        (Decode.field "content" Decode.string)
        (Decode.field "createdAt" (Decode.map Time.millisToPosix Decode.int))


decodeStoneList : Decode.Decoder (List Stone)
decodeStoneList =
    Decode.list Decode.string
        |> Decode.map
            (List.map
                (\s ->
                    if s == "WhiteStone" then
                        WhiteStone

                    else
                        BlackStone
                )
            )


decodePendingRoll : Decode.Decoder PendingRoll
decodePendingRoll =
    Decode.map2 PendingRoll
        (Decode.field "chosen" decodeStoneList)
        (Decode.field "rest" decodeStoneList)


decodeCharacterSheet : Decode.Decoder CharacterSheet
decodeCharacterSheet =
    Decode.map8
        (\id slot name notableFeatures archetype desire quest condition ->
            \notes fate ->
                { id = id
                , slot = slot
                , name = name
                , notableFeatures = notableFeatures
                , archetype = archetype
                , desire = desire
                , quest = quest
                , condition = condition
                , notes = notes
                , fate = fate
                }
        )
        (Decode.field "id" Decode.string)
        (Decode.field "slot" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "notableFeatures" Decode.string)
        (Decode.field "archetype" Decode.string)
        (Decode.field "desire" Decode.string)
        (Decode.field "quest" Decode.string)
        (Decode.field "condition" Decode.string)
        |> Decode.andThen
            (\toSheet ->
                Decode.map2 toSheet
                    (Decode.field "notes" Decode.string)
                    (Decode.field "fate" Decode.int)
            )


decodeGameState : Decode.Decoder GameState
decodeGameState =
    Decode.map5 GameState
        (Decode.field "sessionId" Decode.string)
        (Decode.field "messages" (Decode.list decodeMessage))
        (Decode.field "stonePool" decodeStoneList)
        (Decode.field "pendingRoll" (Decode.nullable decodePendingRoll))
        (Decode.field "characters" (Decode.list decodeCharacterSheet))


decodeFromDiscord : Decode.Decoder Msg
decodeFromDiscord =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "BackendAuthResult" ->
                        Decode.map (Ok >> GotBackendAuth)
                            (Decode.field "data" decodeAuth)

                    "AuthFailed" ->
                        Decode.map AuthFailed
                            (Decode.at [ "data", "message" ] Decode.string)

                    _ ->
                        Decode.succeed NoOp
            )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromDiscordRaw value ->
            case Decode.decodeValue decodeFromDiscord value of
                Ok innerMsg ->
                    update innerMsg model

                Err _ ->
                    ( model, Cmd.none )

        GotBackendAuth (Ok auth) ->
            let
                cmd =
                    getGameStateCmd model.flags auth
            in
            ( { model
                | auth = Just auth
                , status = "Loaded auth as " ++ auth.username
              }
            , cmd
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
                    ( { model | gameState = Just (applyServerState model gs), status = "Connected." }, Cmd.none )

        GotGameState (Err _) ->
            ( { model | status = "Failed to load game state." }, Cmd.none )

        NewMessageChanged s ->
            ( { model | newMessage = s }, Cmd.none )

        SendMessage ->
            case ( model.auth, model.gameState ) of
                ( Just auth, Just _ ) ->
                    if String.trim model.newMessage == "" then
                        ( model, Cmd.none )

                    else
                        let
                            cmd =
                                postMessageCmd model.flags auth model.newMessage
                        in
                        ( { model | newMessage = "" }, cmd )

                _ ->
                    ( model, Cmd.none )

        -- Mutations acknowledge only; the resulting state arrives on the socket.
        MessagePosted (Ok ()) ->
            ( model, Cmd.none )

        MessagePosted (Err _) ->
            ( { model | status = "Failed to post message." }, Cmd.none )

        AddWhiteStone ->
            ( model, postStonesCmd model.flags model.auth "/stones/add-white" )

        RollStones ->
            ( model, postStonesCmd model.flags model.auth "/stones/roll" )

        RerollStones ->
            ( model, postStonesCmd model.flags model.auth "/stones/reroll" )

        AcceptRoll ->
            ( model, postStonesCmd model.flags model.auth "/stones/accept" )

        StonesUpdated (Ok ()) ->
            ( model, Cmd.none )

        StonesUpdated (Err _) ->
            ( { model | status = "Failed to update stones." }, Cmd.none )

        CharacterFieldInput slot field value ->
            ( { model
                | gameState =
                    Maybe.map (mapCharacterAtSlot slot (setCharacterField field value)) model.gameState
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
                    ( released, postCharacterUpdateCmd model.flags auth slot character )

                _ ->
                    ( released, Cmd.none )

        FateIncrement slot ->
            ( model, postFateCmd model.flags model.auth slot 1 )

        FateDecrement slot ->
            ( model, postFateCmd model.flags model.auth slot -1 )

        CharacterUpdated (Ok ()) ->
            ( model, Cmd.none )

        CharacterUpdated (Err _) ->
            ( { model | status = "Failed to update character sheet." }, Cmd.none )

        WsGameStateRaw value ->
            case Decode.decodeValue decodeGameState value of
                Ok gs ->
                    ( { model | gameState = Just (applyServerState model gs) }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        AuthFailed message ->
            ( { model | status = "Discord authorization failed: " ++ message }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


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



-- HTTP HELPERS


backendBaseUrl : Flags -> String
backendBaseUrl flags =
    flags.apiBaseUrl


getGameStateCmd : Flags -> Auth -> Cmd Msg
getGameStateCmd flags auth =
    let
        url =
            backendBaseUrl flags
                ++ "/api/table/"
                ++ flags.tableId
                ++ "/messages"
    in
    Http.request
        { method = "GET"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken) ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson GotGameState decodeGameState
        , timeout = Nothing
        , tracker = Nothing
        }


postMessageCmd : Flags -> Auth -> String -> Cmd Msg
postMessageCmd flags auth content =
    let
        url =
            backendBaseUrl flags
                ++ "/api/table/"
                ++ flags.tableId
                ++ "/message"

        body =
            Encode.object
                [ ( "content", Encode.string content )
                ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken)
            , Http.header "Content-Type" "application/json"
            ]
        , url = url
        , body = Http.jsonBody body
        , expect = Http.expectWhatever MessagePosted
        , timeout = Nothing
        , tracker = Nothing
        }


postStonesCmd : Flags -> Maybe Auth -> String -> Cmd Msg
postStonesCmd flags maybeAuth path =
    case maybeAuth of
        Nothing ->
            Cmd.none

        Just auth ->
            let
                url =
                    backendBaseUrl flags
                        ++ "/api/table/"
                        ++ flags.tableId
                        ++ path
            in
            Http.request
                { method = "POST"
                , headers =
                    [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken) ]
                , url = url
                , body = Http.emptyBody
                , expect = Http.expectWhatever StonesUpdated
                , timeout = Nothing
                , tracker = Nothing
                }


postCharacterUpdateCmd : Flags -> Auth -> Int -> CharacterSheet -> Cmd Msg
postCharacterUpdateCmd flags auth slot character =
    let
        url =
            backendBaseUrl flags
                ++ "/api/table/"
                ++ flags.tableId
                ++ "/characters/"
                ++ String.fromInt slot
                ++ "/update"

        body =
            Encode.object
                [ ( "name", Encode.string character.name )
                , ( "notableFeatures", Encode.string character.notableFeatures )
                , ( "archetype", Encode.string character.archetype )
                , ( "desire", Encode.string character.desire )
                , ( "quest", Encode.string character.quest )
                , ( "condition", Encode.string character.condition )
                , ( "notes", Encode.string character.notes )
                ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken)
            , Http.header "Content-Type" "application/json"
            ]
        , url = url
        , body = Http.jsonBody body
        , expect = Http.expectWhatever CharacterUpdated
        , timeout = Nothing
        , tracker = Nothing
        }


postFateCmd : Flags -> Maybe Auth -> Int -> Int -> Cmd Msg
postFateCmd flags maybeAuth slot delta =
    case maybeAuth of
        Nothing ->
            Cmd.none

        Just auth ->
            let
                url =
                    backendBaseUrl flags
                        ++ "/api/table/"
                        ++ flags.tableId
                        ++ "/characters/"
                        ++ String.fromInt slot
                        ++ "/fate"

                body =
                    Encode.object [ ( "delta", Encode.int delta ) ]
            in
            Http.request
                { method = "POST"
                , headers =
                    [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken)
                    , Http.header "Content-Type" "application/json"
                    ]
                , url = url
                , body = Http.jsonBody body
                , expect = Http.expectWhatever CharacterUpdated
                , timeout = Nothing
                , tracker = Nothing
                }



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "board-root" ]
        [ h1 [] [ text "TTRPG Shared Board" ]
        , div [] [ text model.status ]
        , viewRollState model.gameState
        , viewCharacterSheets model.gameState
        , viewMessages model
        , viewComposer model
        ]


viewStoneList : List Stone -> Html Msg
viewStoneList stones =
    ul [ class "stone-list" ]
        (List.map (\stone -> li [] [ text (Roll.stoneLabel stone) ]) stones)


viewRollState : Maybe GameState -> Html Msg
viewRollState maybeGameState =
    case maybeGameState of
        Nothing ->
            div [ class "roll-panel" ] [ text "Loading stone pool..." ]

        Just gs ->
            div [ class "roll-panel" ]
                [ div []
                    [ text "Initial stones: "
                    , viewStoneList Roll.initialStones
                    ]
                , div []
                    [ text ("Current pool (" ++ String.fromInt (List.length gs.stonePool) ++ "): ")
                    , viewStoneList gs.stonePool
                    ]
                , button [ onClick AddWhiteStone ] [ text "Add White Stone" ]
                , case gs.pendingRoll of
                    Nothing ->
                        button [ onClick RollStones ] [ text "Roll" ]

                    Just pending ->
                        div [ class "roll-result" ]
                            [ div []
                                [ text "Rolled: "
                                , viewStoneList pending.chosen
                                ]
                            , button [ onClick RerollStones ] [ text "Reroll" ]
                            , button [ onClick AcceptRoll ] [ text "Accept" ]
                            ]
                ]


viewCharacterSheets : Maybe GameState -> Html Msg
viewCharacterSheets maybeGameState =
    case maybeGameState of
        Nothing ->
            div [ class "character-sheets" ] [ text "Loading character sheets..." ]

        Just gs ->
            div [ class "character-sheets" ]
                (List.map viewCharacterSheet gs.characters)


viewCharacterSheet : CharacterSheet -> Html Msg
viewCharacterSheet character =
    div [ class "character-sheet" ]
        [ viewCharacterField character.slot NameField "Character Name" character.name
        , viewCharacterField character.slot NotableFeaturesField "Notable Features" character.notableFeatures
        , viewCharacterField character.slot ArchetypeField "Archetype" character.archetype
        , viewCharacterField character.slot DesireField "Desire" character.desire
        , viewCharacterField character.slot QuestField "Quest" character.quest
        , viewCharacterField character.slot ConditionField "Condition" character.condition
        , viewCharacterField character.slot NotesField "Notes" character.notes
        , div [ class "fate" ]
            [ text ("Fate: " ++ String.fromInt character.fate)
            , button [ onClick (FateDecrement character.slot) ] [ text "-" ]
            , button [ onClick (FateIncrement character.slot) ] [ text "+" ]
            ]
        ]


viewCharacterField : Int -> CharacterField -> String -> String -> Html Msg
viewCharacterField slot field label fieldValue =
    div [ class "character-field" ]
        [ text label
        , input
            [ type_ "text"
            , value fieldValue
            , onInput (CharacterFieldInput slot field)
            , onBlur (CharacterFieldBlur slot)
            ]
            []
        ]


viewMessages : Model -> Html Msg
viewMessages model =
    case model.gameState of
        Nothing ->
            div [] [ text "Loading messages..." ]

        Just gs ->
            ul [ class "message-list" ]
                (List.map viewMessage gs.messages)


viewMessage : Message -> Html Msg
viewMessage msg =
    let
        roleLabel =
            case msg.role of
                Facilitator ->
                    "Facilitator"

                Player ->
                    ""
    in
    li []
        [ text (roleLabel ++ msg.authorName ++ ": " ++ msg.content) ]


viewComposer : Model -> Html Msg
viewComposer model =
    case model.auth of
        Nothing ->
            div [] [ text "Waiting for authentication..." ]

        Just _ ->
            div [ class "composer" ]
                [ input
                    [ type_ "text"
                    , placeholder "Write a message..."
                    , value model.newMessage
                    , onInput NewMessageChanged
                    ]
                    []
                , button [ onClick SendMessage ] [ text "Send" ]
                ]



-- PROGRAM


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
