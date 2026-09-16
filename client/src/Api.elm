module Api exposing
    ( decodeGameState
    , getGameState
    , getMessageHistory
    , postAcceptCompelMove
    , postCancelOvercome
    , postCharacterUpdate
    , postClaimSlot
    , postClearMessages
    , postCommitBoon
    , postCreateEntity
    , postDeleteEntity
    , postEndSession
    , postFate
    , postMessage
    , postProposalDecision
    , postReleaseSlot
    , postSessionGoal
    , postStartOvercome
    , postStartSession
    , postStones
    , postSuggestCompel
    , postUpdateEntity
    , postUseAbility
    , postUseFloatingBoon
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
import Roll exposing (Stone(..))
import Time
import Types exposing (Auth, CharacterSheet, CommittedBoon, EntityKind, FloatingBoon, Flags, GameState, Overcome, PendingRoll, Proposal, Session, SessionSummary, TableEntity, UsedAbility, decodeRole, entityKindPath)



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


postStones : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postStones flags auth path toMsg =
    postEmpty flags auth path toMsg


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


{-| Pledge (positive `delta`) or withdraw (negative) boons from the next roll.
The slot is the caller's own claimed sheet, resolved server-side; the Worker
clamps the pledge to what that character holds.
-}
postCommitBoon : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postCommitBoon flags auth delta toMsg =
    postJson flags auth "/stones/commit" (Encode.object [ ( "delta", Encode.int delta ) ]) toMsg


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
`context` carries the facilitator's note when accepting an Add a Detail /
Gain Insight; it is ignored for every other kind and for a reject.
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


{-| Raise a once-per-session ability: `kind` is `"help-out"`, `"add-detail"`, or
`"gain-insight"`. Queued for the facilitator like any other proposal.
-}
postUseAbility : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUseAbility flags auth kind toMsg =
    postJson flags auth "/abilities/use" (Encode.object [ ( "kind", Encode.string kind ) ]) toMsg


{-| Raise the Accept Compel move — take on a complication for 2 boons on
facilitator approval.
-}
postAcceptCompelMove : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postAcceptCompelMove flags auth toMsg =
    postEmpty flags auth "/moves/accept-compel" toMsg


{-| Raise the Suggest Compel ability against the character in `targetSlot` — a
once-per-session ability, queued like the others. Approved → 1 boon to the
suggester, 2 to the compelled character.
-}
postSuggestCompel : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postSuggestCompel flags auth targetSlot toMsg =
    postJson flags
        auth
        "/abilities/use"
        (Encode.object
            [ ( "kind", Encode.string "suggest-compel" )
            , ( "targetSlot", Encode.int targetSlot )
            ]
        )
        toMsg


{-| Ask to spend a floating boon on the roll; the facilitator approves it like a
Highlight.
-}
postUseFloatingBoon : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUseFloatingBoon flags auth floatingId toMsg =
    postJson flags auth "/stones/use-floating" (Encode.object [ ( "floatingId", Encode.string floatingId ) ]) toMsg


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


{-| Facilitator-only: end the running session. Tops the shared pool back up to
its floor of 2 Boon / 2 Bane if it has fallen short of either.
-}
postEndSession : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postEndSession flags auth toMsg =
    postEmpty flags auth "/session/end" toMsg


{-| Facilitator-only: open an overcome against the character in `slot`.
-}
postStartOvercome : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postStartOvercome flags auth slot toMsg =
    postJson flags auth "/overcome/start" (Encode.object [ ( "slot", Encode.int slot ) ]) toMsg


{-| Facilitator-only: call off the open overcome without resolving it.
-}
postCancelOvercome : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postCancelOvercome flags auth toMsg =
    postEmpty flags auth "/overcome/cancel" toMsg


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


decodeStoneList : Decode.Decoder (List Stone)
decodeStoneList =
    Decode.list Decode.string
        |> Decode.map
            (List.map
                (\s ->
                    if s == "Boon" then
                        Boon

                    else
                        Bane
                )
            )


decodePendingRoll : Decode.Decoder PendingRoll
decodePendingRoll =
    Decode.map2 PendingRoll
        (Decode.field "chosen" decodeStoneList)
        (Decode.field "rest" decodeStoneList)


decodeCommittedBoon : Decode.Decoder CommittedBoon
decodeCommittedBoon =
    Decode.map2 CommittedBoon
        (Decode.field "slot" Decode.int)
        (Decode.field "count" Decode.int)


decodeProposal : Decode.Decoder Proposal
decodeProposal =
    Decode.map8 Proposal
        (Decode.field "id" Decode.string)
        (Decode.field "kind" Kind.decodeProposalKind)
        (Decode.field "proposerId" Decode.string)
        (Decode.field "proposerName" Decode.string)
        (Decode.field "slot" (Decode.nullable Decode.int))
        (Decode.field "delta" Decode.int)
        (Decode.field "floatingId" (Decode.nullable Decode.string))
        (Decode.field "targetSlot" (Decode.nullable Decode.int))


decodeFloatingBoon : Decode.Decoder FloatingBoon
decodeFloatingBoon =
    Decode.map3 FloatingBoon
        (Decode.field "id" Decode.string)
        (Decode.field "text" Decode.string)
        (Decode.field "createdByName" Decode.string)


decodeUsedAbility : Decode.Decoder UsedAbility
decodeUsedAbility =
    Decode.map2 UsedAbility
        (Decode.field "slot" Decode.int)
        (Decode.field "kinds" (Decode.list Kind.decodeAbilityKind))


decodeSession : Decode.Decoder Session
decodeSession =
    Decode.map2 Session
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)


decodeOvercome : Decode.Decoder Overcome
decodeOvercome =
    Decode.map Overcome (Decode.field "targetSlot" Decode.int)


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
        (Decode.field "pendingRoll" (Decode.nullable decodePendingRoll))
        (Decode.field "committedBoons" (Decode.list decodeCommittedBoon))
        (Decode.field "proposals" (Decode.list decodeProposal))
        (Decode.field "session" (Decode.nullable decodeSession))
        (Decode.field "characters" (Decode.list decodeCharacterSheet))
        |> andMap (Decode.field "sessionHistory" (Decode.list decodeSessionSummary))
        |> andMap (Decode.field "overcome" (Decode.nullable decodeOvercome))
        |> andMap (Decode.field "floatingBoons" (Decode.list decodeFloatingBoon))
        |> andMap (Decode.field "usedAbilities" (Decode.list decodeUsedAbility))
        |> andMap (Decode.field "npcs" (Decode.list decodeTableEntity))
        |> andMap (Decode.field "locations" (Decode.list decodeTableEntity))
