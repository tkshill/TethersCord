module Types exposing
    ( Aspect(..)
    , AspectBanes
    , Auth
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
    , MutationOutcome
    , Proposal
    , Role(..)
    , Session
    , SessionSummary
    , TableEntity
    , UsedAbility
    , abilityUsed
    , actionPending
    , aspectBaneCount
    , aspectLabel
    , characterAtSlot
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
import Kind exposing (AbilityKind, ProposalKind)
import Roll exposing (Stone)
import Set exposing (Set)
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


{-| Boons a character has pledged toward the next draw's odds; only slots with
a non-zero pledge appear. 23.1 retired the roll/reroll/accept lifecycle that
used to spend these from `fate` on accept — what a pledge costs, if anything,
going forward is an open question (see ROADMAP.md 23).
-}
type alias CommittedBoon =
    { slot : Int
    , count : Int
    }


{-| The character holding `slot`, if any. One shared slot lookup for `Main` (the
state-merge helpers) and `View` (the panels that resolve a proposal's target,
e.g. a Suggest Compel).
-}
characterAtSlot : Int -> List CharacterSheet -> Maybe CharacterSheet
characterAtSlot slot characters =
    characters |> List.filter (\c -> c.slot == slot) |> List.head


committedBoonsForSlot : Int -> List CommittedBoon -> Int
committedBoonsForSlot slot committed =
    committed
        |> List.filter (\c -> c.slot == slot)
        |> List.head
        |> Maybe.map .count
        |> Maybe.withDefault 0


{-| A player-initiated request the facilitator resolves through the accept /
reject queue. See `Kind.ProposalKind` for the kinds. `delta` is `±1` for a
pledge; `floatingId` names the boon for `UseFloating`; `targetSlot` names the
compelled character for `AbilityProposal SuggestCompel`.
-}
type alias Proposal =
    { id : String
    , kind : ProposalKind
    , proposerId : String
    , proposerName : String
    , slot : Maybe Int
    , delta : Int
    , floatingId : Maybe String
    , targetSlot : Maybe Int
    }


{-| A session context owned by no character — a Boon or (23.3) a Bane, with
`text` as the note of the context it stands for. The facilitator plants one
directly, or approves an Add a Detail / Gain Insight (always a Boon); either
way, the facilitator removing it is the only way it goes.
-}
type alias FloatingBoon =
    { id : String
    , kind : Stone
    , text : String
    , createdByName : String
    }


{-| Which once-per-session abilities a character has already spent this session.
-}
type alias UsedAbility =
    { slot : Int
    , kinds : List AbilityKind
    }


{-| Whether a mutation with the given action key currently has a request in
flight. Controls consult this to disable themselves and show a pending state.
-}
actionPending : String -> Model -> Bool
actionPending key model =
    Set.member key model.inflight


{-| Whether the character in `slot` has already used the ability `kind` this
session.
-}
abilityUsed : Int -> AbilityKind -> List UsedAbility -> Bool
abilityUsed slot kind used =
    used
        |> List.filter (\u -> u.slot == slot)
        |> List.head
        |> Maybe.map (\u -> List.member kind u.kinds)
        |> Maybe.withDefault False


{-| The running game session: just an id (ties back to the `game_sessions` row)
and a free-text goal the facilitator sets and can rewrite. Nothing about ending
a session resolves the goal — there is no roll or verdict.
-}
type alias Session =
    { id : String
    , goal : String
    }


{-| A completed session, as read back from the `game_sessions` rows for the
table's history view. The running session is not included here.
-}
type alias SessionSummary =
    { id : String
    , goal : String
    , startedAt : Time.Posix
    , endedAt : Time.Posix
    }


{-| The three fixed aspects a character is written around. An aspect only ever
accumulates Banes (section 19).
-}
type Aspect
    = Archetype
    | Desire
    | Quest


aspectLabel : Aspect -> String
aspectLabel aspect =
    case aspect of
        Archetype ->
            "Archetype"

        Desire ->
            "Desire"

        Quest ->
            "Quest"


{-| Bane counts for a character's three aspects. Carried between sessions.
-}
type alias AspectBanes =
    { archetype : Int
    , desire : Int
    , quest : Int
    }


aspectBaneCount : Aspect -> AspectBanes -> Int
aspectBaneCount aspect banes =
    case aspect of
        Archetype ->
            banes.archetype

        Desire ->
            banes.desire

        Quest ->
            banes.quest


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
    , aspectBanes : AspectBanes

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
    , committedBoons : List CommittedBoon
    , proposals : List Proposal
    , session : Maybe Session
    , characters : List CharacterSheet
    , sessionHistory : List SessionSummary
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

    -- Mutation "action keys" with a request in flight. A control whose key is in
    -- here is disabled and shown pending, so an impatient double-click cannot
    -- fire the same POST twice. Cleared when the matching result lands.
    , inflight : Set String

    -- Character slots / entity ids with unsaved local edits, waiting for the
    -- debounced save (`FieldSaveDue`). A whole sheet edit becomes one write
    -- instead of one per field blur. Server pushes keep the local copy of any
    -- slot / id in these sets, the same way `editingSlot` protects one.
    , dirtySlots : Set Int
    , dirtyEntities : Set String

    -- Monotonic token for the field-save debounce: every edit bumps it, and a
    -- `FieldSaveDue` only fires the write if it still carries the latest value.
    , fieldSaveSeq : Int

    -- Net pledge delta the Highlight +/- buttons have accumulated but not yet
    -- sent, coalesced into a single `/stones/commit` after a short pause, with
    -- `pledgeSeq` as its debounce token.
    , pendingPledgeDelta : Int
    , pledgeSeq : Int

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

    -- Draft text in the facilitator's "add a floating boon" field (23.2) —
    -- planting a session context directly, not through an ability proposal.
    , newFloatingBoonNote : String

    -- Which kind the facilitator's next planted session context will be
    -- (23.3) — toggled by the Boon / Bane picker next to the draft field.
    , newFloatingBoonKind : Stone

    -- A `GET /messages/history` fetch for older log rows is in flight.
    , loadingHistory : Bool

    -- The last history fetch came back short, so there is no earlier history to
    -- ask for and the "load earlier" affordance is hidden.
    , noMoreHistory : Bool

    -- Whether the "How to play" glossary card is expanded. Collapsed on load;
    -- toggled by `ToggleGuide`, purely local view state.
    , guideExpanded : Bool

    -- Which aspect field, if any, has its "see examples" list open on the
    -- character sheet: `Just ( slot, aspect )`. One at a time; `ToggleAspectExamples`.
    , aspectExamplesOpen : Maybe ( Int, Aspect )

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


{-| The result of an acknowledge-only mutation (the Worker replies `204`, so
there is nothing to fold in). `family` is the in-flight key prefix released on
either outcome; `failMsg` is the transient error shown when the request failed.
Ten near-identical `…Updated` messages collapsed into `MutationDone` carrying
this.
-}
type alias MutationOutcome =
    { family : String
    , failMsg : String
    }


type Msg
    = GotBackendAuth (Result Http.Error Auth)
    | GotGameState (Result Http.Error GameState)
    | NewMessageChanged String
    | SendMessage
    | LogScrolled Bool
    | LoadEarlierMessages
    | GotEarlierMessages (Result Http.Error (List Message))
    | ClearLog
    | FromDiscordRaw Decode.Value
    | AddBoon
    | CommitBoonIncrement
    | CommitBoonDecrement
    | PledgeDue Int
    | SelectSlot Int
    | ClaimSlot Int
    | ReleaseSlot Int
    | AcceptProposal String
    | RejectProposal String
    | WithdrawProposal String
    | ProposalResolved String (Result Http.Error ())
    | ProposalDraftChanged String String
    | UseAbility AbilityKind
    | SuggestCompel Int
    | AcceptCompelMove
    | UseFloatingBoon String
    | SessionGoalChanged String
    | SessionGoalEditChanged String
    | SaveSessionGoal
    | StartSession
    | EndSession
    | RequestConfirm String
    | CancelConfirm
    | DismissError
    | ToggleGuide
    | ToggleAspectExamples Int Aspect
    | WsStatusChanged String
    | RetryGetGameState
    | DrawStones
    | AddStone Stone
    | RemoveStone Stone
    | FloatingBoonDraftChanged String
    | FloatingBoonKindChanged Stone
    | AddFloatingBoon
    | DeleteFloatingBoon String
    | CharacterFieldInput Int CharacterField String
    | CharacterFieldBlur Int
    | FieldSaveDue Int
    | FateIncrement Int
    | FateDecrement Int
    | AddEntity EntityKind
    | EntityFieldInput EntityKind String EntityField String
    | EntityFieldBlur EntityKind String
    | DeleteEntity EntityKind String
    | MutationDone MutationOutcome (Result Http.Error ())
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
