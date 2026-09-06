module Api exposing
    ( decodeGameState
    , getGameState
    , postCharacterUpdate
    , postClaimSlot
    , postClearMessages
    , postCommitBoon
    , postFate
    , postMessage
    , postProposalDecision
    , postReleaseSlot
    , postStones
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
import Types exposing (Auth, CharacterSheet, CommittedBoon, Flags, GameState, PendingRoll, Proposal, decodeRole)



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
-}
postProposalDecision : Flags -> Auth -> String -> String -> (Result Http.Error () -> msg) -> Cmd msg
postProposalDecision flags auth proposalId decision toMsg =
    Http.request
        { method = "POST"
        , headers = authHeaders auth
        , url = tableUrl flags ("/proposals/" ++ proposalId ++ "/" ++ decision)
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
    Decode.map6 Proposal
        (Decode.field "id" Decode.string)
        (Decode.field "kind" Decode.string)
        (Decode.field "proposerId" Decode.string)
        (Decode.field "proposerName" Decode.string)
        (Decode.field "slot" (Decode.nullable Decode.int))
        (Decode.field "delta" Decode.int)


decodeCharacterSheet : Decode.Decoder CharacterSheet
decodeCharacterSheet =
    Decode.map8
        (\id slot name notableFeatures archetype desire quest condition ->
            \notes fate ownerId ->
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
                Decode.map3 toSheet
                    (Decode.field "notes" Decode.string)
                    (Decode.field "fate" Decode.int)
                    (Decode.field "ownerId" (Decode.nullable Decode.string))
            )


decodeGameState : Decode.Decoder GameState
decodeGameState =
    Decode.map7 GameState
        (Decode.field "sessionId" Decode.string)
        (Decode.field "messages" (Decode.list decodeMessage))
        (Decode.field "stonePool" decodeStoneList)
        (Decode.field "pendingRoll" (Decode.nullable decodePendingRoll))
        (Decode.field "committedBoons" (Decode.list decodeCommittedBoon))
        (Decode.field "proposals" (Decode.list decodeProposal))
        (Decode.field "characters" (Decode.list decodeCharacterSheet))
