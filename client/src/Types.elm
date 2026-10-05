module Types exposing
    ( AspectBanes
    , Auth
    , CharacterField(..)
    , CharacterSheet
    , Connection(..)
    , EntityField(..)
    , EntityKind(..)
    , Flags
    , GameState
    , Message
    , MessageKind(..)
    , Model
    , Msg(..)
    , MutationOutcome
    , Role(..)
    , ToolTab(..)
    , Session
    , SessionSummary
    , TableEntity
    , actionPending
    , aspectBaneCount
    , characterAtSlot
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
import Aspect exposing (Aspect(..))
import ContextAspect exposing (ContextAspect, Polarity)
import Die exposing (Die)
import Dict exposing (Dict)
import Http
import Json.Decode as Decode
import Junction exposing (Junction)
import MoveRecord exposing (MoveRecord)
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


{-| `Chat` is a line someone typed into the composer; `Event` is a line the
table wrote when something happened (a roll, a move, a session starting). The log styles them apart.
-}
type MessageKind
    = Chat
    | Event


type alias Message =
    { id : String
    , authorId : String
    , authorName : String
    , role : Role
    , kind : MessageKind
    , content : String
    , createdAt : Time.Posix
    }


{-| The character holding `slot`, if any. One shared slot lookup for `Main` (the
state-merge helpers) and `View` (the panels that resolve a move's character).
-}
characterAtSlot : Int -> List CharacterSheet -> Maybe CharacterSheet
characterAtSlot slot characters =
    characters |> List.filter (\c -> c.slot == slot) |> List.head


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
    , die : Die
    , junction : Maybe Junction
    , moves : List MoveRecord
    , session : Maybe Session
    , characters : List CharacterSheet
    , sessionHistory : List SessionSummary
    , contextAspects : List ContextAspect
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

    -- The player's wording for their next Create.
    , createDraft : String

    -- Unsaved edits to a context aspect's text, keyed by aspect id; saved when
    -- the field loses focus.
    , contextAspectEdits : Dict String String

    -- Draft text in the facilitator's "add a context boon or bane" field —
    -- planting one directly, not through a move.
    , newContextAspectNote : String

    -- Which kind the facilitator's next planted context boon or bane will be
    -- — toggled by the Boon / Bane picker next to the draft field.
    , newContextAspectKind : Polarity

    -- A `GET /messages/history` fetch for older log rows is in flight.
    , loadingHistory : Bool

    -- The last history fetch came back short, so there is no earlier history to
    -- ask for and the "load earlier" affordance is hidden.
    , noMoreHistory : Bool

    -- Which aspect field, if any, has its "see examples" list open on the
    -- character sheet: `Just ( slot, aspect )`. One at a time; `ToggleAspectExamples`.
    , aspectExamplesOpen : Maybe ( Int, Aspect )

    -- The character aspect whose text field is swapped in for its split
    -- button (✎), on the viewer's own sheet: `Just ( slot, aspect )`. Leaving
    -- the field swaps the button back.
    , aspectEditing : Maybe ( Int, Aspect )

    -- Backend WebSocket connection state, as last reported by the JS socket.
    , connection : Connection

    -- How many times the initial game-state load has been retried after a
    -- transient failure. The live socket is the real source of state; this is
    -- only the first-paint seed.
    , gameStateAttempts : Int

    -- Viewer's local time zone, used to render message timestamps. Starts at
    -- UTC and is replaced once Time.here resolves.
    , timeZone : Time.Zone

    -- What the left panel's tool strip is showing: one character's sheet, the
    -- World or the Guide (roadmap 32.2). Purely local view state, toggled by
    -- `SelectTool`; the event log and composer are not tools — they own the
    -- right column outright.
    , toolTab : ToolTab
    }


{-| Backend WebSocket health, driven by the `wsStatus` port.
-}
type Connection
    = Connected
    | Reconnecting
    | Offline
    | Rejected


{-| The left panel's tool strip (roadmap 32.2): one strip holding a tab per
character sheet, then the World (NPCs and locations) and the Guide, with one
selected item across all of them. `SheetTab` carries the sheet's slot. The
event log is not a tool — it fills the right column.
-}
type ToolTab
    = SheetTab Int
    | WorldTab
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
    | ClaimSlot Int
    | ReleaseSlot Int
    | PressJunction
    | RerollJunction
    | AcceptJunction
    | RejectJunction
    | StepDie Die.Direction
    | MakeHighlight Aspect
    | MakeHighlightContext String
    | MakeComplicate Aspect
    | MakeCreate
    | CreateDraftChanged String
    | MakeAlter
    | UndoMove String
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
    | ToggleAspectExamples Int Aspect
    | EditAspect Int Aspect
    | EditContextAspect String
    | WsStatusChanged String
    | RetryGetGameState
    | ContextAspectDraftChanged String
    | ContextAspectKindChanged Polarity
    | AddContextAspect
    | DeleteContextAspect String
    | ContextAspectTextChanged String String
    | SaveContextAspectText String
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

