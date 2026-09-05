module Types exposing
    ( Auth
    , CharacterField(..)
    , CharacterSheet
    , Flags
    , GameState
    , Message
    , Model
    , Msg(..)
    , PendingRoll
    , Role(..)
    , decodeRole
    , roleLabel
    , setCharacterField
    )

{-| Shared data types for the Activity client.

`Model` and `Msg` live here rather than in `Main` so that `View` can import them
without creating an import cycle (`Main` imports `View`, so `View` cannot import
`Main`).

-}

import Http
import Json.Decode as Decode
import Roll exposing (Stone)
import Time



-- FLAGS


type alias Flags =
    { apiBaseUrl : String
    , tableId : String
    }



-- DOMAIN


type Role
    = Facilitator
    | Player


roleLabel : Role -> String
roleLabel role =
    case role of
        Facilitator ->
            "Facilitator"

        Player ->
            "Player"


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



-- MODEL


type alias Model =
    { flags : Flags
    , auth : Maybe Auth
    , gameState : Maybe GameState
    , newMessage : String
    , status : String

    -- Slot the user is currently typing into, if any. Server pushes must not
    -- overwrite a sheet while it is being edited.
    , editingSlot : Maybe Int

    -- Viewer's local time zone, used to render message timestamps. Starts at
    -- UTC and is replaced once Time.here resolves.
    , timeZone : Time.Zone
    }



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
    | GotTimeZone Time.Zone
    | NoOp



-- WIRE FORMAT


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
