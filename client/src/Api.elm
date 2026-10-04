module Api exposing
    ( getGameState
    , getMessageHistory
    , postAddContextAspect
    , postAlter
    , postCharacterUpdate
    , postClaimSlot
    , postClearMessages
    , postComplicate
    , postCreate
    , postCreateEntity
    , postDeleteContextAspect
    , postDeleteEntity
    , postEndSession
    , postFate
    , postHighlight
    , postHighlightContext
    , postJunction
    , postMessage
    , postReleaseSlot
    , postSessionGoal
    , postStartSession
    , postStepDie
    , postUndo
    , postUpdateContextAspect
    , postUpdateEntity
    )

{-| Every call the client makes to the Worker backend. What comes back is
decoded in `Api.Decode`, the one wire boundary.

These functions take the message constructor for their result as an argument
rather than referring to `Types.Msg` directly, so this module has no knowledge
of the application's update loop.

-}

import Api.Decode
import Aspect exposing (Aspect)
import ContextAspect exposing (Polarity)
import Die
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Types exposing (Auth, CharacterSheet, EntityKind, Flags, GameState, TableEntity, entityKindPath)



-- REQUESTS
--
-- Every endpoint is one line over the three privates below (`get` / `postEmpty`
-- / `postJson`), which own the URL shape, the auth header, the JSON content
-- type, `expect`, and the (always `Nothing`) timeout / tracker.


tableUrl : Flags -> String -> String
tableUrl flags path =
    flags.apiBaseUrl ++ "/api/table/" ++ flags.tableId ++ path


authHeaders : Auth -> List Http.Header
authHeaders auth =
    [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken) ]


jsonContentType : Http.Header
jsonContentType =
    Http.header "Content-Type" "application/json"


{-| An authenticated `GET` on a table path, decoding the JSON response.
-}
get : Flags -> Auth -> String -> Decode.Decoder a -> (Result Http.Error a -> msg) -> Cmd msg
get flags auth path decoder toMsg =
    Http.request
        { method = "GET"
        , headers = authHeaders auth
        , url = tableUrl flags path
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg decoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| An authenticated `POST` with no body — the shape of every mutation that
takes its arguments from the URL. The Worker replies `204`, so the result is
just `()`.
-}
postEmpty : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postEmpty flags auth path toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags path
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| An authenticated `POST` carrying a JSON body. Same `204` / `()` reply as
`postEmpty`.
-}
postJson : Flags -> Auth -> String -> Encode.Value -> (Result Http.Error () -> msg) -> Cmd msg
postJson flags auth path body toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags path
        , body = Http.jsonBody body
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


getGameState : Flags -> Auth -> (Result Http.Error GameState -> msg) -> Cmd msg
getGameState flags auth toMsg =
    get flags auth "/messages" Api.Decode.gameState toMsg


{-| Older log rows, for the "load earlier" affordance. `before` is a POSIX
millisecond timestamp; the Worker returns up to a windowful of messages older
than it, oldest first.
-}
getMessageHistory : Flags -> Auth -> Int -> (Result Http.Error (List Types.Message) -> msg) -> Cmd msg
getMessageHistory flags auth before toMsg =
    get flags
        auth
        ("/messages/history?before=" ++ String.fromInt before)
        (Decode.field "messages" (Decode.list Api.Decode.message))
        toMsg


postMessage : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postMessage flags auth content toMsg =
    postJson flags auth "/message" (Encode.object [ ( "content", Encode.string content ) ]) toMsg


{-| Facilitator-only: wipe this table's log. The resulting empty state arrives
on the socket like any other mutation.
-}
postClearMessages : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postClearMessages flags auth toMsg =
    postEmpty flags auth "/messages/clear" toMsg


postCharacterUpdate : Flags -> Auth -> Int -> CharacterSheet -> (Result Http.Error () -> msg) -> Cmd msg
postCharacterUpdate flags auth slot character toMsg =
    postJson flags
        auth
        ("/characters/" ++ String.fromInt slot ++ "/update")
        (Encode.object
            [ ( "name", Encode.string character.name )
            , ( "notableFeatures", Encode.string character.notableFeatures )
            , ( "archetype", Encode.string character.archetype )
            , ( "desire", Encode.string character.desire )
            , ( "quest", Encode.string character.quest )
            , ( "condition", Encode.string character.condition )
            , ( "notes", Encode.string character.notes )
            ]
        )
        toMsg


postFate : Flags -> Auth -> Int -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postFate flags auth slot delta toMsg =
    postJson flags
        auth
        ("/characters/" ++ String.fromInt slot ++ "/fate")
        (Encode.object [ ( "delta", Encode.int delta ) ])
        toMsg


{-| One step of the Junction loop. `step` is `"roll"` (any player), or
`"reroll"` / `"accept"` / `"reject"` (facilitator only).
-}
postJunction : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postJunction flags auth step toMsg =
    postEmpty flags auth ("/junction/" ++ step) toMsg


{-| Claim a character sheet for the calling user, or release one. Releasing is
allowed for the sheet's owner or the facilitator.
-}
postClaimSlot : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postClaimSlot flags auth slot toMsg =
    slotAction flags auth slot "claim" toMsg


postReleaseSlot : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postReleaseSlot flags auth slot toMsg =
    slotAction flags auth slot "release" toMsg


slotAction : Flags -> Auth -> Int -> String -> (Result Http.Error () -> msg) -> Cmd msg
slotAction flags auth slot action toMsg =
    postEmpty flags auth ("/characters/" ++ String.fromInt slot ++ "/" ++ action) toMsg


{-| Highlight: pay a boon to step the die up, drawing on one of the caller's
own character aspects. The sheet is the caller's claimed one, resolved by the
Worker, as for every move.
-}
postHighlight : Flags -> Auth -> Aspect -> (Result Http.Error () -> msg) -> Cmd msg
postHighlight flags auth aspect toMsg =
    postJson flags auth "/moves/highlight" (aspectBody aspect) toMsg


{-| Highlight Context: use a context aspect's one use. Open to anyone.
-}
postHighlightContext : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postHighlightContext flags auth contextAspectId toMsg =
    postJson flags auth "/moves/highlight-context" (Encode.object [ ( "contextAspectId", Encode.string contextAspectId ) ]) toMsg


{-| Complicate: gain two boons, and a context bane drawn from `aspect` appears.
-}
postComplicate : Flags -> Auth -> Aspect -> (Result Http.Error () -> msg) -> Cmd msg
postComplicate flags auth aspect toMsg =
    postJson flags auth "/moves/complicate" (aspectBody aspect) toMsg


{-| Create: pay a boon for a context boon in the player's words. A blank `text`
is recorded by the Worker as a detail from the player.
-}
postCreate : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postCreate flags auth text toMsg =
    postJson flags auth "/moves/create" (Encode.object [ ( "text", Encode.string text ) ]) toMsg


{-| Alter: pay two boons to reroll the pending junction on its own die.
-}
postAlter : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postAlter flags auth toMsg =
    postEmpty flags auth "/moves/alter" toMsg


{-| Undo one move: the facilitator's for any move, a player's for their own.
-}
postUndo : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUndo flags auth moveId toMsg =
    postEmpty flags auth ("/moves/" ++ moveId ++ "/undo") toMsg


aspectBody : Aspect -> Encode.Value
aspectBody aspect =
    Encode.object [ ( "aspect", Encode.string (Aspect.toWire aspect) ) ]


{-| Facilitator-only: step the die one rung, as a direct edit.
-}
postStepDie : Flags -> Auth -> Die.Direction -> (Result Http.Error () -> msg) -> Cmd msg
postStepDie flags auth direction toMsg =
    case direction of
        Die.Up ->
            postEmpty flags auth "/die/step-up" toMsg

        Die.Down ->
            postEmpty flags auth "/die/step-down" toMsg


{-| Facilitator-only: plant a context boon or bane directly, kind and note of
the facilitator's choosing.
-}
postAddContextAspect : Flags -> Auth -> Polarity -> String -> (Result Http.Error () -> msg) -> Cmd msg
postAddContextAspect flags auth polarity text toMsg =
    postJson flags
        auth
        "/context-aspects"
        (Encode.object
            [ ( "kind", Encode.string (ContextAspect.polarityLabel polarity) )
            , ( "text", Encode.string text )
            ]
        )
        toMsg


{-| Facilitator-only: remove a context boon or bane outright.
-}
postDeleteContextAspect : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postDeleteContextAspect flags auth contextAspectId toMsg =
    postEmpty flags auth ("/context-aspects/" ++ contextAspectId ++ "/delete") toMsg


{-| Facilitator-only: rewrite a context boon or bane's text.
-}
postUpdateContextAspect : Flags -> Auth -> String -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUpdateContextAspect flags auth contextAspectId text toMsg =
    postJson flags
        auth
        ("/context-aspects/" ++ contextAspectId ++ "/update")
        (Encode.object [ ( "text", Encode.string text ) ])
        toMsg


{-| Facilitator-only: open a session with a goal.
-}
postStartSession : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postStartSession flags auth goal toMsg =
    postJson flags auth "/session/start" (Encode.object [ ( "goal", Encode.string goal ) ]) toMsg


{-| Facilitator-only: rewrite the running session's goal.
-}
postSessionGoal : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postSessionGoal flags auth goal toMsg =
    postJson flags auth "/session/goal" (Encode.object [ ( "goal", Encode.string goal ) ]) toMsg


{-| Facilitator-only: end the running session. Records it in the history and
nothing else; the die and context aspects carry across.
-}
postEndSession : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postEndSession flags auth toMsg =
    postEmpty flags auth "/session/end" toMsg


{-| Facilitator-only: add a blank NPC / location row for the table.
-}
postCreateEntity : Flags -> Auth -> EntityKind -> (Result Http.Error () -> msg) -> Cmd msg
postCreateEntity flags auth kind toMsg =
    postJson flags auth ("/" ++ entityKindPath kind) (Encode.object []) toMsg


{-| Facilitator-only: write an NPC / location row's name and notes.
-}
postUpdateEntity : Flags -> Auth -> EntityKind -> TableEntity -> (Result Http.Error () -> msg) -> Cmd msg
postUpdateEntity flags auth kind entity toMsg =
    postJson flags
        auth
        ("/" ++ entityKindPath kind ++ "/" ++ entity.id ++ "/update")
        (Encode.object
            [ ( "name", Encode.string entity.name )
            , ( "notes", Encode.string entity.notes )
            ]
        )
        toMsg


{-| Facilitator-only: remove an NPC / location row.
-}
postDeleteEntity : Flags -> Auth -> EntityKind -> String -> (Result Http.Error () -> msg) -> Cmd msg
postDeleteEntity flags auth kind entityId toMsg =
    postEmpty flags auth ("/" ++ entityKindPath kind ++ "/" ++ entityId ++ "/delete") toMsg

