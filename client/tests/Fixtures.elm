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

import Dict
import Roll exposing (Stone(..))
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
    , stonePool = []
    , committedBoons = []
    , proposals = []
    , session = Nothing
    , characters = [ character ]
    , sessionHistory = []
    , floatingBoons = []
    , usedAbilities = []
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
    , inflight = Set.empty
    , dirtySlots = Set.empty
    , dirtyEntities = Set.empty
    , fieldSaveSeq = 0
    , pendingPledgeDelta = 0
    , pledgeSeq = 0
    , selectedSlot = 0
    , logAtBottom = True
    , newSessionGoal = ""
    , goalEdit = ""
    , sessionControlsExpanded = False
    , proposalDrafts = Dict.empty
    , newFloatingBoonNote = ""
    , newFloatingBoonKind = Boon
    , loadingHistory = False
    , noMoreHistory = False
    , guideExpanded = False
    , aspectExamplesOpen = Nothing
    , connection = Connected
    , gameStateAttempts = 0
    , timeZone = Time.utc
    }


{-| A full `GameState` wire payload as the Worker broadcasts it, exercising every
sub-decoder: floating boons, used abilities, and a proposal of each awkward
`kind`.
-}
snapshotJson : String
snapshotJson =
    """
    { "sessionId": "sess-1"
    , "messages":
        [ { "id": "m1", "authorId": "u1", "authorName": "Ada", "role": "player"
          , "content": "hello", "createdAt": 1700000000000 }
        , { "id": "m2", "authorId": "u2", "authorName": "Gm", "role": "facilitator"
          , "content": "welcome", "createdAt": 1700000001000 }
        ]
    , "stonePool": ["Boon", "Bane", "Boon"]
    , "committedBoons": [ { "slot": 1, "count": 2 } ]
    , "proposals":
        [ { "id": "p1", "kind": "add-boon", "proposerId": "u1", "proposerName": "Ada"
          , "slot": null, "delta": 0, "floatingId": null, "targetSlot": null }
        , { "id": "p2", "kind": "pledge", "proposerId": "u1", "proposerName": "Ada"
          , "slot": 1, "delta": 1, "floatingId": null, "targetSlot": null }
        , { "id": "p3", "kind": "suggest-compel", "proposerId": "u1", "proposerName": "Ada"
          , "slot": 1, "delta": 0, "floatingId": null, "targetSlot": 2 }
        , { "id": "p4", "kind": "use-floating", "proposerId": "u1", "proposerName": "Ada"
          , "slot": 1, "delta": 0, "floatingId": "f1", "targetSlot": null }
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
    , "floatingBoons":
        [ { "id": "f1", "kind": "Bane", "text": "the rope still holds", "createdByName": "Gm"
          , "createdAt": 1700000002000 }
        ]
    , "usedAbilities": [ { "slot": 1, "kinds": ["help-out", "add-detail"] } ]
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
