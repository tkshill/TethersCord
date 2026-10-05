module Fixtures exposing
    ( character
    , facilitatorAuth
    , gameState
    , model
    , playerAuth
    , snapshotJson
    )

{-| Shared builders for the client test suite. Each returns a plausible default
value; a test overrides only the fields it cares about with record update.
-}

import ContextAspect exposing (Polarity(..))
import Dict
import Die
import Set
import Time
import Types
    exposing
        ( Auth
        , CharacterSheet
        , Connection(..)
        , Flags
        , GameState
        , Model
        , ToolTab(..)
        , Role(..)
        )


flags : Flags
flags =
    { apiBaseUrl = "", tableId = "guild-channel" }


facilitatorAuth : Auth
facilitatorAuth =
    { userId = "fac-1"
    , username = "Gm"
    , role = Facilitator
    , sessionToken = "tok-fac"
    }


playerAuth : Auth
playerAuth =
    { userId = "player-1"
    , username = "Ada"
    , role = Player
    , sessionToken = "tok-player"
    }


character : CharacterSheet
character =
    { id = "char-1"
    , slot = 1
    , name = "Ada"
    , notableFeatures = ""
    , archetype = ""
    , desire = ""
    , quest = ""
    , condition = ""
    , notes = ""
    , fate = 0
    , aspectBanes = { archetype = 0, desire = 0, quest = 0 }
    , ownerId = Nothing
    }


gameState : GameState
gameState =
    { sessionId = "sess-1"
    , messages = []
    , die = Die.base
    , junction = Nothing
    , moves = []
    , session = Nothing
    , characters = [ character ]
    , sessionHistory = []
    , contextAspects = []
    , npcs = []
    , locations = []
    }


{-| A freshly-initialised model with no auth and no game state, the state the
app is in before the Discord handshake completes.
-}
model : Model
model =
    { flags = flags
    , auth = Nothing
    , gameState = Nothing
    , newMessage = ""
    , status = "Authorizing with Discord…"
    , error = Nothing
    , confirming = Nothing
    , editingSlot = Nothing
    , editingEntity = Nothing
    , inflight = []
    , dirtySlots = Set.empty
    , dirtyEntities = Set.empty
    , fieldSaveSeq = 0
    , logAtBottom = True
    , newSessionGoal = ""
    , goalEdit = ""
    , sessionControlsExpanded = False
    , createDraft = ""
    , contextAspectEdits = Dict.empty
    , newContextAspectNote = ""
    , newContextAspectKind = Boon
    , loadingHistory = False
    , noMoreHistory = False
    , aspectExamplesOpen = Nothing
    , aspectEditing = Nothing
    , connection = Connected
    , gameStateAttempts = 0
    , timeZone = Time.utc
    , toolTab = SheetTab 0
    }


{-| A full `GameState` wire payload as the Worker broadcasts it (the 31.3
shape), exercising every sub-decoder: the die, a pending Junction, a move of
each kind open to undo, and context aspects with their consumed flag and
`fromAspect`.
-}
snapshotJson : String
snapshotJson =
    """
    { "sessionId": "sess-1"
    , "messages":
        [ { "id": "m1", "authorId": "u1", "authorName": "Ada", "role": "player"
          , "content": "hello", "createdAt": 1700000000000 }
        , { "id": "m2", "authorId": "u2", "authorName": "Gm", "role": "facilitator"
          , "kind": "event", "content": "welcome", "createdAt": 1700000001000 }
        ]
    , "die": 12
    , "junction": { "rolledBy": "Ada", "die": 12, "face": 11, "outcome": "critical-flow", "rerolls": 1, "alteredSlots": [1] }
    , "moves":
        [ { "id": "mv1", "kind": "highlight", "actorId": "u1", "actorName": "Ada", "slot": 1
          , "aspect": "desire", "effects": [{ "type": "die", "direction": "up" }], "messageId": "m1" }
        , { "id": "mv2", "kind": "highlight-context", "actorId": "u2", "actorName": "Gm", "slot": null
          , "aspect": null, "effects": [], "messageId": "m2" }
        , { "id": "mv3", "kind": "complicate", "actorId": "u1", "actorName": "Ada", "slot": 1
          , "aspect": "quest", "effects": [], "messageId": "m3" }
        , { "id": "mv4", "kind": "create", "actorId": "u1", "actorName": "Ada", "slot": 1
          , "aspect": null, "effects": [], "messageId": "m4" }
        , { "id": "mv5", "kind": "alter", "actorId": "u1", "actorName": "Ada", "slot": 1
          , "aspect": null, "effects": [], "messageId": "m5" }
        ]
    , "session": { "id": "s1", "goal": "Escape the vault" }
    , "characters":
        [ { "id": "char-1", "slot": 1, "name": "Ada", "notableFeatures": "quick"
          , "archetype": "rogue", "desire": "out", "quest": "the map", "condition": ""
          , "notes": "n", "fate": 3, "ownerId": "u1"
          , "aspectBanes": { "archetype": 2, "desire": 0, "quest": 1 } }
        ]
    , "sessionHistory":
        [ { "id": "s0", "goal": "The bridge", "startedAt": 1699000000000
          , "endedAt": 1699000900000 }
        ]
    , "contextAspects":
        [ { "id": "f1", "kind": "Bane", "text": "", "createdByName": "Ada"
          , "createdAt": 1700000002000, "consumed": false
          , "fromAspect": { "slot": 1, "aspect": "quest" } }
        , { "id": "f2", "kind": "Boon", "text": "the guard looked away", "createdByName": "Ada"
          , "createdAt": 1700000002500, "consumed": true, "fromAspect": null }
        ]
    , "npcs":
        [ { "id": "n1", "name": "The Archivist", "notes": "keeps the vault keys"
          , "createdAt": 1700000003000, "updatedAt": 1700000004000 }
        ]
    , "locations":
        [ { "id": "l1", "name": "The Vault", "notes": ""
          , "createdAt": 1700000005000, "updatedAt": 1700000005000 }
        ]
    }
    """
