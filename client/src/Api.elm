module Api exposing
    ( decodeGameState
    , getGameState
    , getMessageHistory
    , postAddDetail
    , postAddSessionAspect
    , postAddStone
    , postAlter
    , postCharacterUpdate
    , postClaimSlot
    , postClearMessages
    , postComplicate
    , postCreateEntity
    , postDeleteEntity
    , postDeleteSessionAspect
    , postEndSession
    , postFate
    , postHighlight
    , postMessage
    , postOvercome
    , postProposalDecision
    , postReleaseSlot
    , postRemoveStone
    , postSessionGoal
    , postStartSession
    , postUnconsumeSessionAspect
    , postUpdateEntity
    , postUpdateSessionAspect
    , postUseSessionAspect
    , postUseSessionBoon
    , postWithdrawProposal
    )

{-| Every call the client makes to the Worker backend, plus the JSON decoders
they depend on.

These functions take the message constructor for their result as an argument
rather than referring to `Types.Msg` directly, so this module has no knowledge
of the application's update loop.

-}

import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Kind
import Roll exposing (Stone(..), stoneLabel)
import Time
import Types exposing (Auth, CharacterSheet, EntityKind, Flags, GameState, Overcome, Proposal, Session, SessionAspect, SessionSummary, TableEntity, decodeRole, entityKindPath)



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
    get flags auth "/messages" decodeGameState toMsg


{-| Older log rows, for the "load earlier" affordance. `before` is a POSIX
millisecond timestamp; the Worker returns up to a windowful of messages older
than it, oldest first.
-}
getMessageHistory : Flags -> Auth -> Int -> (Result Http.Error (List Types.Message) -> msg) -> Cmd msg
getMessageHistory flags auth before toMsg =
    get flags
        auth
        ("/messages/history?before=" ++ String.fromInt before)
        (Decode.field "messages" (Decode.list decodeMessage))
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


{-| Highlight: propose paying one of the caller's own boons to add a Boon to the
pool. The slot is the caller's claimed sheet, resolved server-side.
-}
postHighlight : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postHighlight flags auth toMsg =
    postEmpty flags auth "/moves/highlight" toMsg


{-| One step of the Overcome loop. `step` is `"roll"` (any player), or
`"reroll"` / `"accept"` / `"reject"` (facilitator only).
-}
postOvercome : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postOvercome flags auth step toMsg =
    postEmpty flags auth ("/overcome/" ++ step) toMsg


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


{-| Facilitator-only: `decision` is `"accept"` or `"reject"` for the proposal.
`context` carries the facilitator's wording when accepting an Add Detail; it is
ignored for every other kind and for a reject.
-}
postProposalDecision : Flags -> Auth -> String -> String -> Maybe String -> (Result Http.Error () -> msg) -> Cmd msg
postProposalDecision flags auth proposalId decision context toMsg =
    let
        path =
            "/proposals/" ++ proposalId ++ "/" ++ decision
    in
    case context of
        Just text ->
            postJson flags auth path (Encode.object [ ( "text", Encode.string text ) ]) toMsg

        Nothing ->
            postEmpty flags auth path toMsg


{-| A proposer pulls back their own still-pending proposal. Gated on the caller
being the proposer, not the facilitator.
-}
postWithdrawProposal : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postWithdrawProposal flags auth proposalId toMsg =
    postEmpty flags auth ("/proposals/" ++ proposalId ++ "/withdraw") toMsg


{-| Complicate: propose a complication for the character in `targetSlot`. Free;
approved, that character's player gains two boons.
-}
postComplicate : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postComplicate flags auth targetSlot toMsg =
    postJson flags auth "/moves/complicate" (Encode.object [ ( "targetSlot", Encode.int targetSlot ) ]) toMsg


{-| Add Detail: propose establishing a fact, costing one boon on approval. `text`
is the player's suggested wording; `Nothing` leaves it to the facilitator.
-}
postAddDetail : Flags -> Auth -> Maybe String -> (Result Http.Error () -> msg) -> Cmd msg
postAddDetail flags auth text toMsg =
    postJson flags
        auth
        "/moves/add-detail"
        (Encode.object
            (case text of
                Just t ->
                    [ ( "text", Encode.string t ) ]

                Nothing ->
                    []
            )
        )
        toMsg


{-| Alter Fate: propose paying two boons to reroll the pending Overcome.
-}
postAlter : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postAlter flags auth toMsg =
    postEmpty flags auth "/moves/alter" toMsg


{-| Use Session Boon: propose spending an unconsumed session boon into the pool.
-}
postUseSessionBoon : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUseSessionBoon flags auth sessionAspectId toMsg =
    postJson flags auth "/moves/use-session-boon" (Encode.object [ ( "sessionAspectId", Encode.string sessionAspectId ) ]) toMsg


{-| Facilitator-only (23.2): add one stone directly to the shared pool,
independent of a draw.
-}
postAddStone : Flags -> Auth -> Stone -> (Result Http.Error () -> msg) -> Cmd msg
postAddStone flags auth stone toMsg =
    postJson flags auth "/stones/add" (Encode.object [ ( "kind", Encode.string (stoneLabel stone) ) ]) toMsg


{-| Facilitator-only (23.2): remove one stone of `stone`'s kind directly from
the shared pool. The Worker 400s if the pool holds none of that kind.
-}
postRemoveStone : Flags -> Auth -> Stone -> (Result Http.Error () -> msg) -> Cmd msg
postRemoveStone flags auth stone toMsg =
    postJson flags auth "/stones/remove" (Encode.object [ ( "kind", Encode.string (stoneLabel stone) ) ]) toMsg


{-| Facilitator-only: plant a session boon or bane directly, kind and note of
the facilitator's choosing.
-}
postAddSessionAspect : Flags -> Auth -> Stone -> String -> (Result Http.Error () -> msg) -> Cmd msg
postAddSessionAspect flags auth kind text toMsg =
    postJson flags
        auth
        "/session-aspects"
        (Encode.object
            [ ( "kind", Encode.string (stoneLabel kind) )
            , ( "text", Encode.string text )
            ]
        )
        toMsg


{-| Facilitator-only: remove a session boon or bane outright.
-}
postDeleteSessionAspect : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postDeleteSessionAspect flags auth sessionAspectId toMsg =
    postEmpty flags auth ("/session-aspects/" ++ sessionAspectId ++ "/delete") toMsg


{-| Facilitator-only: spend a session boon or bane into the pool directly, no
approval. It is marked consumed, not deleted.
-}
postUseSessionAspect : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUseSessionAspect flags auth sessionAspectId toMsg =
    postEmpty flags auth ("/session-aspects/" ++ sessionAspectId ++ "/use") toMsg


{-| Facilitator-only: clear a consumed mark, to correct a table miscommunication.
It does not touch the pool.
-}
postUnconsumeSessionAspect : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUnconsumeSessionAspect flags auth sessionAspectId toMsg =
    postEmpty flags auth ("/session-aspects/" ++ sessionAspectId ++ "/unconsume") toMsg


{-| Facilitator-only: rewrite a session boon or bane's text.
-}
postUpdateSessionAspect : Flags -> Auth -> String -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUpdateSessionAspect flags auth sessionAspectId text toMsg =
    postJson flags
        auth
        ("/session-aspects/" ++ sessionAspectId ++ "/update")
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
nothing else; the pool, proposals and session boons carry across.
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



-- DECODERS


decodeMessage : Decode.Decoder Types.Message
decodeMessage =
    Decode.map6 Types.Message
        (Decode.field "id" Decode.string)
        (Decode.field "authorId" Decode.string)
        (Decode.field "authorName" Decode.string)
        (Decode.field "role" decodeRole)
        (Decode.field "content" Decode.string)
        (Decode.field "createdAt" (Decode.map Time.millisToPosix Decode.int))


decodeStone : Decode.Decoder Stone
decodeStone =
    Decode.string
        |> Decode.map
            (\s ->
                if s == "Boon" then
                    Boon

                else
                    Bane
            )


decodeStoneList : Decode.Decoder (List Stone)
decodeStoneList =
    Decode.list decodeStone


decodeProposal : Decode.Decoder Proposal
decodeProposal =
    Decode.map8 Proposal
        (Decode.field "id" Decode.string)
        (Decode.field "kind" Kind.decodeProposalKind)
        (Decode.field "proposerId" Decode.string)
        (Decode.field "proposerName" Decode.string)
        (Decode.field "slot" (Decode.nullable Decode.int))
        (Decode.field "sessionAspectId" (Decode.nullable Decode.string))
        (Decode.field "targetSlot" (Decode.nullable Decode.int))
        (Decode.field "text" (Decode.nullable Decode.string))


decodeSessionAspect : Decode.Decoder SessionAspect
decodeSessionAspect =
    Decode.map5 SessionAspect
        (Decode.field "id" Decode.string)
        (Decode.field "kind" decodeStone)
        (Decode.field "text" Decode.string)
        (Decode.field "createdByName" Decode.string)
        (Decode.field "consumed" Decode.bool)


decodeOvercome : Decode.Decoder Overcome
decodeOvercome =
    Decode.map4 Overcome
        (Decode.field "rolledBy" Decode.string)
        (Decode.field "stones" decodeStoneList)
        (Decode.field "rerolls" Decode.int)
        (Decode.field "alteredSlots" (Decode.list Decode.int))


decodeSession : Decode.Decoder Session
decodeSession =
    Decode.map2 Session
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)


decodeAspectBanes : Decode.Decoder Types.AspectBanes
decodeAspectBanes =
    Decode.map3 Types.AspectBanes
        (Decode.field "archetype" Decode.int)
        (Decode.field "desire" Decode.int)
        (Decode.field "quest" Decode.int)


decodeTableEntity : Decode.Decoder TableEntity
decodeTableEntity =
    Decode.map3 TableEntity
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "notes" Decode.string)


decodeSessionSummary : Decode.Decoder SessionSummary
decodeSessionSummary =
    Decode.map4 SessionSummary
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)
        (Decode.field "startedAt" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "endedAt" (Decode.map Time.millisToPosix Decode.int))


decodeCharacterSheet : Decode.Decoder CharacterSheet
decodeCharacterSheet =
    Decode.map8
        (\id slot name notableFeatures archetype desire quest condition ->
            \notes fate aspectBanes ownerId ->
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
                , aspectBanes = aspectBanes
                , ownerId = ownerId
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
                Decode.map4 toSheet
                    (Decode.field "notes" Decode.string)
                    (Decode.field "fate" Decode.int)
                    (Decode.field "aspectBanes" decodeAspectBanes)
                    (Decode.field "ownerId" (Decode.nullable Decode.string))
            )


{-| Applies the next field decoder in a pipeline, so a record decoder can grow
past the `Decode.map8` ceiling.
-}
andMap : Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
andMap =
    Decode.map2 (|>)


decodeGameState : Decode.Decoder GameState
decodeGameState =
    Decode.map8 GameState
        (Decode.field "sessionId" Decode.string)
        (Decode.field "messages" (Decode.list decodeMessage))
        (Decode.field "stonePool" decodeStoneList)
        (Decode.field "overcome" (Decode.nullable decodeOvercome))
        (Decode.field "proposals" (Decode.list decodeProposal))
        (Decode.field "session" (Decode.nullable decodeSession))
        (Decode.field "characters" (Decode.list decodeCharacterSheet))
        (Decode.field "sessionHistory" (Decode.list decodeSessionSummary))
        |> andMap (Decode.field "sessionAspects" (Decode.list decodeSessionAspect))
        |> andMap (Decode.field "npcs" (Decode.list decodeTableEntity))
        |> andMap (Decode.field "locations" (Decode.list decodeTableEntity))
