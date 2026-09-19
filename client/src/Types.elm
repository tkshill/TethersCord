module Types exposing
    ( Aspect(..)
    , AspectBanes
    , Auth
    , CharacterField(..)
    , CharacterSheet
    , Connection(..)
    , EntityField(..)
    , EntityKind(..)
    , Overcome
    , SessionAspect
    , Flags
    , GameState
    , Message
    , Model
    , Msg(..)
    , MutationOutcome
    , Proposal
    , Role(..)
    , ToolTab(..)
    , Session
    , SessionSummary
    , TableEntity
    , actionPending
    , aspectBaneCount
    , aspectLabel
    , characterAtSlot
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

import Action exposing (Action)
import Dict exposing (Dict)
import Http
import Json.Decode as Decode
import Kind exposing (ProposalKind)
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


{-| The Overcome in progress: one roll waiting on the facilitator to accept or
reject it (roadmap 26.2). `stones` is the current draw — a reroll replaces it —
`rerolls` counts redraws, and `alteredSlots` lists the characters whose Alter Fate
has already been accepted this Overcome (each may succeed at one). The pool is not
touched by a roll, so nothing here shows the pool.
-}
type alias Overcome =
    { rolledBy : String
    , stones : List Stone
    , rerolls : Int
    , alteredSlots : List Int
    }


{-| The character holding `slot`, if any. One shared slot lookup for `Main` (the
state-merge helpers) and `View` (the panels that resolve a proposal's target,
e.g. a Complicate).
-}
characterAtSlot : Int -> List CharacterSheet -> Maybe CharacterSheet
characterAtSlot slot characters =
    characters |> List.filter (\c -> c.slot == slot) |> List.head


{-| A player move waiting on the facilitator (Overcome is not one — it needs no
approval). See `Kind.ProposalKind` for the kinds. `sessionAspectId` names the
boon for `UseSessionBoon`; `targetSlot` names the target character for
`Complicate`; `text` is an Add Detail's suggested wording, if the player gave
one.
-}
type alias Proposal =
    { id : String
    , kind : ProposalKind
    , proposerId : String
    , proposerName : String
    , slot : Maybe Int
    , sessionAspectId : Maybe String
    , targetSlot : Maybe Int
    , text : Maybe String
    }


{-| A session boon or session bane: a note of something true in the fiction,
owned by nobody, that can be spent into the pool. It comes from an accepted
Overcome pair, an accepted Add Detail (always a Boon) or the facilitator.
Spending it marks it `consumed` rather than deleting it, and a consumed one
cannot be spent again (roadmap 26.2).
-}
type alias SessionAspect =
    { id : String
    , kind : Stone
    , text : String
    , createdByName : String
    , consumed : Bool
    }


{-| Whether the given action currently has a request in flight. Controls consult this to disable themselves and show a pending state.
-}
actionPending : Action -> Model -> Bool
actionPending action model =
    Action.isPending action model.inflight


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
    , overcome : Maybe Overcome
    , proposals : List Proposal
    , session : Maybe Session
    , characters : List CharacterSheet
    , sessionHistory : List SessionSummary
    , sessionAspects : List SessionAspect
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

    -- Mutations with a request in flight (`Action`). A control whose action is in
    -- here is disabled and shown pending, so an impatient double-click cannot
    -- fire the same POST twice. Cleared, a family at a time, when the matching
    -- result lands.
    , inflight : List Action

    -- Character slots / entity ids with unsaved local edits, waiting for the
    -- debounced save (`FieldSaveDue`). A whole sheet edit becomes one write
    -- instead of one per field blur. Server pushes keep the local copy of any
    -- slot / id in these sets, the same way `editingSlot` protects one.
    , dirtySlots : Set Int
    , dirtyEntities : Set String

    -- Monotonic token for the field-save debounce: every edit bumps it, and a
    -- `FieldSaveDue` only fires the write if it still carries the latest value.
    , fieldSaveSeq : Int

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

    -- Whether the top bar's session controls (start / end / edit goal) are
    -- expanded. Collapsed on load so the bar stays one line at rest; toggled
    -- by `ToggleSessionControls`, purely local view state.
    , sessionControlsExpanded : Bool

    -- The wording the facilitator has typed for an Add Detail proposal before
    -- accepting it (it starts as the player's suggestion, if any), keyed by
    -- proposal id so each queued proposal has its own field.
    , proposalDrafts : Dict String String

    -- The player's own suggested wording in the Moves card's Add Detail field.
    , addDetailDraft : String

    -- Unsaved edits to a session aspect's text, keyed by aspect id; saved when
    -- the field loses focus.
    , sessionAspectEdits : Dict String String

    -- Draft text in the facilitator's "add a session boon or bane" field —
    -- planting one directly, not through a move.
    , newSessionAspectNote : String

    -- Which kind the facilitator's next planted session boon or bane will be
    -- (23.3) — toggled by the Boon / Bane picker next to the draft field.
    , newSessionAspectKind : Stone

    -- A `GET /messages/history` fetch for older log rows is in flight.
    , loadingHistory : Bool

    -- The last history fetch came back short, so there is no earlier history to
    -- ask for and the "load earlier" affordance is hidden.
    , noMoreHistory : Bool

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

    -- Which tool the left panel's glyph strip is showing (roadmap section
    -- 27). Purely local view state, toggled by `SelectTool`; the event log and
    -- composer are not tools — they own the right panel outright.
    , toolTab : ToolTab

    -- The left panel's width in pixels, dragged by the divider handle between
    -- the two panels. `draggingDivider` is true for the duration of a drag,
    -- gating the mouse-move/mouse-up subscriptions that track it
    -- (`Main.subscriptions`).
    , leftPanelWidth : Float
    , draggingDivider : Bool
    }


{-| Backend WebSocket health, driven by the `wsStatus` port.
-}
type Connection
    = Connected
    | Reconnecting
    | Offline
    | Rejected


{-| The left panel's tool strip (roadmap section 27, mockup 2a): one tool shown
at a time under a row of glyph tabs. The facilitator's queue and pool edits
(`FacilitatorTab`) are for the facilitator only; `MovesTab` is for a player who
holds a sheet. The event log is not a tool — it fills the right panel.
-}
type ToolTab
    = SheetTab
    | FacilitatorTab
    | MovesTab
    | CastTab
    | ContextTab
    | GuideTab



-- MESSAGES


{-| The result of an acknowledge-only mutation (the Worker replies `204`, so
there is nothing to fold in). `family` is the in-flight `Action.Family` released on
either outcome; `failMsg` is the transient error shown when the request failed.
Ten near-identical `…Updated` messages collapsed into `MutationDone` carrying
this.
-}
type alias MutationOutcome =
    { family : Action.Family
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
    | SelectSlot Int
    | ClaimSlot Int
    | ReleaseSlot Int
    | AcceptProposal String
    | RejectProposal String
    | WithdrawProposal String
    | ProposalResolved String (Result Http.Error ())
    | ProposalDraftChanged String String
    | PressOvercome
    | RerollOvercome
    | AcceptOvercome
    | RejectOvercome
    | ProposeHighlight
    | ProposeComplicate Int
    | ProposeAddDetail
    | ProposeAlter
    | ProposeUseSessionBoon String
    | AddDetailDraftChanged String
    | SessionGoalChanged String
    | SessionGoalEditChanged String
    | SaveSessionGoal
    | StartSession
    | EndSession
    | RequestConfirm String
    | CancelConfirm
    | DismissError
    | ToggleSessionControls
    | SelectTool ToolTab
    | DividerDragStarted
    | DividerDragged Float
    | DividerDragEnded
    | ToggleAspectExamples Int Aspect
    | WsStatusChanged String
    | RetryGetGameState
    | AddStone Stone
    | RemoveStone Stone
    | SessionAspectDraftChanged String
    | SessionAspectKindChanged Stone
    | AddSessionAspect
    | DeleteSessionAspect String
    | UseSessionAspect String
    | UnconsumeSessionAspect String
    | SessionAspectTextChanged String String
    | SaveSessionAspectText String
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
