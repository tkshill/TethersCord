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
    , postUntetherResolve
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
import Roll exposing (Stone(..))
import Time
import Types exposing (Auth, CharacterSheet, CommittedBoon, EntityKind, FloatingBoon, Flags, GameState, Overcome, PendingRoll, Proposal, Session, SessionSummary, TableEntity, UsedAbility, decodeRole, entityKindPath)



-- REQUESTS


tableUrl : Flags -> String -> String
tableUrl flags path =
    flags.apiBaseUrl ++ "/api/table/" ++ flags.tableId ++ path


authHeaders : Auth -> List Http.Header
authHeaders auth =
    [ Http.header "Authorization" ("Bearer " ++ auth.sessionToken) ]


getGameState : Flags -> Auth -> (Result Http.Error GameState -> msg) -> Cmd msg
getGameState flags auth toMsg =
    Http.request
        { method = "GET"
        , headers = authHeaders auth
        , url = tableUrl flags "/messages"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg decodeGameState
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Older log rows, for the "load earlier" affordance. `before` is a POSIX
millisecond timestamp; the Worker returns up to a windowful of messages older
than it, oldest first.
-}
getMessageHistory : Flags -> Auth -> Int -> (Result Http.Error (List Types.Message) -> msg) -> Cmd msg
getMessageHistory flags auth before toMsg =
    Http.request
        { method = "GET"
        , headers = authHeaders auth
        , url = tableUrl flags ("/messages/history?before=" ++ String.fromInt before)
        , body = Http.emptyBody
        , expect =
            Http.expectJson toMsg
                (Decode.field "messages" (Decode.list decodeMessage))
        , timeout = Nothing
        , tracker = Nothing
        }


postMessage : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postMessage flags auth content toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/message"
        , body = Http.jsonBody (Encode.object [ ( "content", Encode.string content ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


postStones : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postStones flags auth path toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags path
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: wipe this table's log. The resulting empty state arrives
on the socket like any other mutation.
-}
postClearMessages : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postClearMessages flags auth toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags "/messages/clear"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


postCharacterUpdate : Flags -> Auth -> Int -> CharacterSheet -> (Result Http.Error () -> msg) -> Cmd msg
postCharacterUpdate flags auth slot character toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags ("/characters/" ++ String.fromInt slot ++ "/update")
        , body =
            Http.jsonBody
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
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


postFate : Flags -> Auth -> Int -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postFate flags auth slot delta toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags ("/characters/" ++ String.fromInt slot ++ "/fate")
        , body = Http.jsonBody (Encode.object [ ( "delta", Encode.int delta ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Pledge (positive `delta`) or withdraw (negative) boons from the next roll.
The slot is the caller's own claimed sheet, resolved server-side; the Worker
clamps the pledge to what that character holds.
-}
postCommitBoon : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postCommitBoon flags auth delta toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/stones/commit"
        , body = Http.jsonBody (Encode.object [ ( "delta", Encode.int delta ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


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
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags ("/characters/" ++ String.fromInt slot ++ "/" ++ action)
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: `decision` is `"accept"` or `"reject"` for the proposal.
`context` carries the facilitator's note when accepting an Add a Detail /
Gain Insight; it is ignored for every other kind and for a reject.
-}
postProposalDecision : Flags -> Auth -> String -> String -> Maybe String -> (Result Http.Error () -> msg) -> Cmd msg
postProposalDecision flags auth proposalId decision context toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags ("/proposals/" ++ proposalId ++ "/" ++ decision)
        , body =
            case context of
                Just text ->
                    Http.jsonBody (Encode.object [ ( "text", Encode.string text ) ])

                Nothing ->
                    Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| A proposer pulls back their own still-pending proposal. Gated on the caller
being the proposer, not the facilitator.
-}
postWithdrawProposal : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postWithdrawProposal flags auth proposalId toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags ("/proposals/" ++ proposalId ++ "/withdraw")
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Raise a once-per-session ability: `kind` is `"help-out"`, `"add-detail"`, or
`"gain-insight"`. Queued for the facilitator like any other proposal.
-}
postUseAbility : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUseAbility flags auth kind toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/abilities/use"
        , body = Http.jsonBody (Encode.object [ ( "kind", Encode.string kind ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Raise the Accept Compel move — take on a complication for 2 boons on
facilitator approval.
-}
postAcceptCompelMove : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postAcceptCompelMove flags auth toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags "/moves/accept-compel"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Raise the Suggest Compel ability against the character in `targetSlot` — a
once-per-session ability, queued like the others. Approved → 1 boon to the
suggester, 2 to the compelled character.
-}
postSuggestCompel : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postSuggestCompel flags auth targetSlot toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/abilities/use"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "kind", Encode.string "suggest-compel" )
                    , ( "targetSlot", Encode.int targetSlot )
                    ]
                )
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Ask to spend a floating boon on the roll; the facilitator approves it like a
Highlight.
-}
postUseFloatingBoon : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postUseFloatingBoon flags auth floatingId toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/stones/use-floating"
        , body = Http.jsonBody (Encode.object [ ( "floatingId", Encode.string floatingId ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: open a session with a goal.
-}
postStartSession : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postStartSession flags auth goal toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/session/start"
        , body = Http.jsonBody (Encode.object [ ( "goal", Encode.string goal ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: rewrite the running session's goal.
-}
postSessionGoal : Flags -> Auth -> String -> (Result Http.Error () -> msg) -> Cmd msg
postSessionGoal flags auth goal toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/session/goal"
        , body = Http.jsonBody (Encode.object [ ( "goal", Encode.string goal ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: end the running session and roll its pool for the outcome.
-}
postEndSession : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postEndSession flags auth toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags "/session/end"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: close an in-progress reckoning (section 19).
-}
postUntetherResolve : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postUntetherResolve flags auth toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags "/untether/resolve"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: open an overcome against the character in `slot`.
-}
postStartOvercome : Flags -> Auth -> Int -> (Result Http.Error () -> msg) -> Cmd msg
postStartOvercome flags auth slot toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags "/overcome/start"
        , body = Http.jsonBody (Encode.object [ ( "slot", Encode.int slot ) ])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: call off the open overcome without resolving it.
-}
postCancelOvercome : Flags -> Auth -> (Result Http.Error () -> msg) -> Cmd msg
postCancelOvercome flags auth toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags "/overcome/cancel"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: add a blank NPC / location row for the table.
-}
postCreateEntity : Flags -> Auth -> EntityKind -> (Result Http.Error () -> msg) -> Cmd msg
postCreateEntity flags auth kind toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags ("/" ++ entityKindPath kind)
        , body = Http.jsonBody (Encode.object [])
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: write an NPC / location row's name and notes.
-}
postUpdateEntity : Flags -> Auth -> EntityKind -> TableEntity -> (Result Http.Error () -> msg) -> Cmd msg
postUpdateEntity flags auth kind entity toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth ++ [ jsonContentType ]
        , url = tableUrl flags ("/" ++ entityKindPath kind ++ "/" ++ entity.id ++ "/update")
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "name", Encode.string entity.name )
                    , ( "notes", Encode.string entity.notes )
                    ]
                )
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Facilitator-only: remove an NPC / location row.
-}
postDeleteEntity : Flags -> Auth -> EntityKind -> String -> (Result Http.Error () -> msg) -> Cmd msg
postDeleteEntity flags auth kind entityId toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags ("/" ++ entityKindPath kind ++ "/" ++ entityId ++ "/delete")
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


jsonContentType : Http.Header
jsonContentType =
    Http.header "Content-Type" "application/json"



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
        (Decode.field "kind" Decode.string)
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
        (Decode.field "kinds" (Decode.list Decode.string))


decodeSession : Decode.Decoder Session
decodeSession =
    Decode.map4 Session
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)
        (Decode.field "pool" decodeStoneList)
        (Decode.field "carriedBanes" Decode.int)


decodeOvercome : Decode.Decoder Overcome
decodeOvercome =
    Decode.map Overcome (Decode.field "targetSlot" Decode.int)


decodeAspect : Decode.Decoder Types.Aspect
decodeAspect =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "archetype" ->
                        Decode.succeed Types.Archetype

                    "desire" ->
                        Decode.succeed Types.Desire

                    "quest" ->
                        Decode.succeed Types.Quest

                    _ ->
                        Decode.fail ("Unknown aspect " ++ s)
            )


decodeAspectBanes : Decode.Decoder Types.AspectBanes
decodeAspectBanes =
    Decode.map3 Types.AspectBanes
        (Decode.field "archetype" Decode.int)
        (Decode.field "desire" Decode.int)
        (Decode.field "quest" Decode.int)


decodeUntether : Decode.Decoder Types.Untether
decodeUntether =
    Decode.map2 Types.Untether
        (Decode.field "slot" Decode.int)
        (Decode.field "aspect" decodeAspect)


decodeTableEntity : Decode.Decoder TableEntity
decodeTableEntity =
    Decode.map3 TableEntity
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "notes" Decode.string)


decodeSessionSummary : Decode.Decoder SessionSummary
decodeSessionSummary =
    Decode.map5 SessionSummary
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)
        (Decode.field "startedAt" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "endedAt" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "outcome" Decode.string)


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
        |> andMap (Decode.field "untether" (Decode.nullable decodeUntether))
