module Types exposing
    ( Auth
    , CharacterField(..)
    , CharacterSheet
    , CommittedBoon
    , Connection(..)
    , Flags
    , GameState
    , Message
    , Model
    , Msg(..)
    , Overcome
    , PendingRoll
    , Proposal
    , Role(..)
    , Session
    , SessionSummary
    , committedBoonsForSlot
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


{-| An open overcome: the facilitator has framed a risky attempt and named one
character (`targetSlot`) to resolve it. While it is set, that character's player
may Roll and Reroll, and a Reroll costs the target boons.
-}
type alias Overcome =
    { targetSlot : Int }


{-| Boons a character has pledged into the next roll. Spent from their `fate`
stock when the roll is accepted; only slots with a non-zero pledge appear.
-}
type alias CommittedBoon =
    { slot : Int
    , count : Int
    }


committedBoonsForSlot : Int -> List CommittedBoon -> Int
committedBoonsForSlot slot committed =
    committed
        |> List.filter (\c -> c.slot == slot)
        |> List.head
        |> Maybe.map .count
        |> Maybe.withDefault 0


{-| A player-initiated change to shared stone state awaiting the facilitator.
`kind` is `"add-boon"` or `"pledge"`; `delta` is `1` or `-1`.
-}
type alias Proposal =
    { id : String
    , kind : String
    , proposerId : String
    , proposerName : String
    , slot : Maybe Int
    , delta : Int
    }


{-| The running game session. `pool` is the session stone pool, which grows one
stone per accepted roll.
-}
type alias Session =
    { id : String
    , goal : String
    , pool : List Stone
    }


{-| A completed session, as read back from the `game_sessions` rows for the
table's history view. The running session is not included here.
-}
type alias SessionSummary =
    { id : String
    , goal : String
    , startedAt : Time.Posix
    , endedAt : Time.Posix
    , outcome : String
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

    -- Discord user id of the player who claimed this sheet, if any.
    , ownerId : Maybe String
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
    , committedBoons : List CommittedBoon
    , proposals : List Proposal
    , session : Maybe Session
    , characters : List CharacterSheet
    , sessionHistory : List SessionSummary
    , overcome : Maybe Overcome
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

    -- Which character sheet's tab is open. Sheets are shown one at a time.
    , selectedSlot : Int

    -- Whether the message log is scrolled to (or near) its bottom. New messages
    -- only pull the log down when this holds, so a viewer reading back history
    -- is left where they are.
    , logAtBottom : Bool

    -- Draft goal in the facilitator's "start session" field.
    , newSessionGoal : String

    -- Backend WebSocket connection state, as last reported by the JS socket.
    , connection : Connection

    -- How many times the initial game-state load has been retried after a
    -- transient failure. The live socket is the real source of state; this is
    -- only the first-paint seed.
    , gameStateAttempts : Int

    -- Viewer's local time zone, used to render message timestamps. Starts at
    -- UTC and is replaced once Time.here resolves.
    , timeZone : Time.Zone
    }


{-| Backend WebSocket health, driven by the `wsStatus` port.
-}
type Connection
    = Connected
    | Reconnecting
    | Offline
    | Rejected



-- MESSAGES


type Msg
    = GotBackendAuth (Result Http.Error Auth)
    | GotGameState (Result Http.Error GameState)
    | NewMessageChanged String
    | SendMessage
    | LogScrolled Bool
    | MessagePosted (Result Http.Error ())
    | ClearLog
    | LogCleared (Result Http.Error ())
    | FromDiscordRaw Decode.Value
    | AddBoon
    | CommitBoonIncrement
    | CommitBoonDecrement
    | SelectSlot Int
    | ClaimSlot Int
    | ReleaseSlot Int
    | SlotClaimed (Result Http.Error ())
    | AcceptProposal String
    | RejectProposal String
    | ProposalResolved (Result Http.Error ())
    | SessionGoalChanged String
    | StartSession
    | EndSession
    | SessionUpdated (Result Http.Error ())
    | WsStatusChanged String
    | RetryGetGameState
    | RollStones
    | RerollStones
    | AcceptRoll
    | StonesUpdated (Result Http.Error ())
    | StartOvercome Int
    | CancelOvercome
    | OvercomeUpdated (Result Http.Error ())
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
