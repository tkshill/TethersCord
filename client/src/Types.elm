module Types exposing
    ( Auth
    , CharacterField(..)
    , CharacterSheet
    , CommittedBoon
    , Connection(..)
    , EntityField(..)
    , EntityKind(..)
    , FloatingBoon
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
    , TableEntity
    , UsedAbility
    , abilityUsed
    , committedBoonsForSlot
    , decodeRole
    , entitiesForKind
    , entityKindPath
    , roleLabel
    , setCharacterField
    , setEntityField
    )

{-| Shared data types for the Activity client.

`Model` and `Msg` live here rather than in `Main` so that `View` can import them
without creating an import cycle (`Main` imports `View`, so `View` cannot import
`Main`).

-}

import Dict exposing (Dict)
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


{-| A player-initiated request the facilitator resolves through the accept /
reject queue. `kind` is `"add-boon"`, `"pledge"`, one of the ability kinds
(`"help-out"`, `"add-detail"`, `"gain-insight"`, `"suggest-compel"`),
`"accept-compel"`, or `"use-floating"`. `delta` is `±1` for a pledge;
`floatingId` names the boon for `use-floating`; `targetSlot` names the compelled
character for `suggest-compel`.
-}
type alias Proposal =
    { id : String
    , kind : String
    , proposerId : String
    , proposerName : String
    , slot : Maybe Int
    , delta : Int
    , floatingId : Maybe String
    , targetSlot : Maybe Int
    }


{-| A boon owned by no character, created when the facilitator approves an
Add a Detail / Gain Insight. `text` is the facilitator's note of the context it
stands for. Any player can ask to spend it on a roll.
-}
type alias FloatingBoon =
    { id : String
    , text : String
    , createdByName : String
    }


{-| Which once-per-session abilities a character has already spent this session
(`kinds` holds the ability-kind strings).
-}
type alias UsedAbility =
    { slot : Int
    , kinds : List String
    }


{-| Whether the character in `slot` has already used the ability `kind` this
session.
-}
abilityUsed : Int -> String -> List UsedAbility -> Bool
abilityUsed slot kind used =
    used
        |> List.filter (\u -> u.slot == slot)
        |> List.head
        |> Maybe.map (\u -> List.member kind u.kinds)
        |> Maybe.withDefault False


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


{-| A facilitator-owned reference row: an NPC or a location. Broadcast to the
whole table; only the facilitator may edit it. First cut is name + notes.
-}
type alias TableEntity =
    { id : String
    , name : String
    , notes : String
    }


{-| Which reference collection a row belongs to. The constructor doubles as the
route segment (`npcs` / `locations`) via `entityKindPath`.
-}
type EntityKind
    = Npc
    | Location


entityKindPath : EntityKind -> String
entityKindPath kind =
    case kind of
        Npc ->
            "npcs"

        Location ->
            "locations"


entitiesForKind : EntityKind -> GameState -> List TableEntity
entitiesForKind kind gs =
    case kind of
        Npc ->
            gs.npcs

        Location ->
            gs.locations


type EntityField
    = EntityNameField
    | EntityNotesField


setEntityField : EntityField -> String -> TableEntity -> TableEntity
setEntityField field value entity =
    case field of
        EntityNameField ->
            { entity | name = value }

        EntityNotesField ->
            { entity | notes = value }


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
    , floatingBoons : List FloatingBoon
    , usedAbilities : List UsedAbility
    , npcs : List TableEntity
    , locations : List TableEntity
    }



-- MODEL


type alias Model =
    { flags : Flags
    , auth : Maybe Auth
    , gameState : Maybe GameState
    , newMessage : String

    -- Steady-state status line: auth progress, "Connected.", reconnection. Not
    -- used for failures — those go in `error` and clear themselves.
    , status : String

    -- A transient failure note, shown in red beneath the status line and
    -- auto-dismissed a few seconds after it is set (`DismissError`).
    , error : Maybe String

    -- A destructive facilitator action that has been armed but not yet
    -- confirmed (an action key like "end-session" / "clear-log" / "edit-goal").
    -- The second click on the armed control performs it; anything else disarms.
    , confirming : Maybe String

    -- Slot the user is currently typing into, if any. Server pushes must not
    -- overwrite a sheet while it is being edited.
    , editingSlot : Maybe Int

    -- Id of the NPC / location row the facilitator is currently typing into, if
    -- any. Same purpose as `editingSlot` for the reference cards.
    , editingEntity : Maybe String

    -- Which character sheet's tab is open. Sheets are shown one at a time.
    , selectedSlot : Int

    -- Whether the message log is scrolled to (or near) its bottom. New messages
    -- only pull the log down when this holds, so a viewer reading back history
    -- is left where they are.
    , logAtBottom : Bool

    -- Draft goal in the facilitator's "start session" field.
    , newSessionGoal : String

    -- Draft goal in the facilitator's mid-session "edit goal" field, seeded
    -- from the running session's goal.
    , goalEdit : String

    -- Context note the facilitator types when approving an Add a Detail or Gain
    -- Insight proposal (the text attached to the resulting floating boon), keyed
    -- by proposal id so each queued proposal has its own field.
    , proposalDrafts : Dict String String

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
    | WithdrawProposal String
    | ProposalResolved String (Result Http.Error ())
    | ProposalDraftChanged String String
    | UseAbility String
    | SuggestCompel Int
    | AcceptCompelMove
    | UseFloatingBoon String
    | MoveRaised (Result Http.Error ())
    | SessionGoalChanged String
    | SessionGoalEditChanged String
    | SaveSessionGoal
    | StartSession
    | EndSession
    | SessionUpdated (Result Http.Error ())
    | RequestConfirm String
    | CancelConfirm
    | DismissError
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
    | AddEntity EntityKind
    | EntityFieldInput EntityKind String EntityField String
    | EntityFieldBlur EntityKind String
    | DeleteEntity EntityKind String
    | EntityMutated (Result Http.Error ())
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
