module ApiDecodersTest exposing (suite)

{-| The `Api.decodeGameState` decoder against a full captured wire payload. One
snapshot exercises every sub-decoder, including the shapes that are easy to get
wrong: a pending Overcome, session aspects with their consumed flag, and a
proposal of each `kind`.
-}

import Api
import Expect
import Fixtures
import Json.Decode as Decode
import Kind
import Roll exposing (Stone(..))
import Test exposing (Test, describe, test)
import Types


decoded : Result Decode.Error Types.GameState
decoded =
    Decode.decodeString Api.decodeGameState Fixtures.snapshotJson


suite : Test
suite =
    describe "Api.decodeGameState"
        [ test "decodes the whole snapshot without error" <|
            \_ ->
                case decoded of
                    Ok _ ->
                        Expect.pass

                    Err err ->
                        Expect.fail (Decode.errorToString err)
        , test "keeps message order and roles" <|
            \_ ->
                decoded
                    |> Result.map (.messages >> List.map (\m -> ( m.authorName, roleTag m.role )))
                    |> Expect.equal (Ok [ ( "Ada", "player" ), ( "Gm", "facilitator" ) ])
        , test "maps stone wire strings to the Stone type" <|
            \_ ->
                decoded
                    |> Result.map .stonePool
                    |> Expect.equal (Ok [ Boon, Bane, Boon ])
        , test "reads a pending Overcome, and null as none" <|
            \_ ->
                decoded
                    |> Result.map .overcome
                    |> Expect.equal
                        (Ok
                            (Just
                                { rolledBy = "Ada"
                                , stones = [ Boon, Bane ]
                                , rerolls = 1
                                , alteredSlots = [ 1 ]
                                }
                            )
                        )
        , test "reads a null Overcome as no roll pending" <|
            \_ ->
                Fixtures.snapshotJson
                    |> String.replace """"overcome": { "rolledBy": "Ada", "stones": ["Boon", "Bane"], "rerolls": 1, "alteredSlots": [1] }""" """"overcome": null"""
                    |> Decode.decodeString Api.decodeGameState
                    |> Result.map .overcome
                    |> Expect.equal (Ok Nothing)
        , test "reads every proposal kind, with nullable slot/targetSlot" <|
            \_ ->
                decoded
                    |> Result.map (.proposals >> List.map (\p -> ( p.kind, p.slot, p.targetSlot )))
                    |> Expect.equal
                        (Ok
                            [ ( Kind.Alter, Just 1, Nothing )
                            , ( Kind.Highlight, Just 1, Nothing )
                            , ( Kind.Complicate, Just 1, Just 2 )
                            , ( Kind.UseSessionBoon, Just 1, Nothing )
                            , ( Kind.AddDetail, Just 1, Nothing )
                            ]
                        )
        , test "carries the use-session-boon proposal's sessionAspectId and an Add Detail's suggested text" <|
            \_ ->
                decoded
                    |> Result.map
                        (\gs ->
                            ( List.filterMap .sessionAspectId gs.proposals
                            , List.filterMap .text gs.proposals
                            )
                        )
                    |> Expect.equal (Ok ( [ "f1" ], [ "the door is barred" ] ))
        , test "reads session aspects: kind, text, and whether each is consumed" <|
            \_ ->
                decoded
                    |> Result.map (.sessionAspects >> List.map (\b -> { id = b.id, kind = b.kind, text = b.text, consumed = b.consumed }))
                    |> Expect.equal
                        (Ok
                            [ { id = "f1", kind = Bane, text = "the rope still holds", consumed = False }
                            , { id = "f2", kind = Boon, text = "the guard looked away", consumed = True }
                            ]
                        )
        , test "reads the running session's goal" <|
            \_ ->
                decoded
                    |> Result.map (.session >> Maybe.map .goal)
                    |> Expect.equal (Ok (Just "Escape the vault"))
        , test "reads the character sheet, including fate and owner" <|
            \_ ->
                decoded
                    |> Result.map (.characters >> List.map (\c -> ( c.name, c.fate, c.ownerId )))
                    |> Expect.equal (Ok [ ( "Ada", 3, Just "u1" ) ])
        , test "reads each aspect's Bane count" <|
            \_ ->
                decoded
                    |> Result.map (.characters >> List.map .aspectBanes)
                    |> Expect.equal (Ok [ { archetype = 2, desire = 0, quest = 1 } ])
        , test "reads completed sessions in history: goal and dates, no verdict" <|
            \_ ->
                decoded
                    |> Result.map (.sessionHistory >> List.map .goal)
                    |> Expect.equal (Ok [ "The bridge" ])
        , test "reads NPC and location reference rows" <|
            \_ ->
                decoded
                    |> Result.map
                        (\gs ->
                            ( List.map (\e -> ( e.name, e.notes )) gs.npcs
                            , List.map .name gs.locations
                            )
                        )
                    |> Expect.equal
                        (Ok
                            ( [ ( "The Archivist", "keeps the vault keys" ) ]
                            , [ "The Vault" ]
                            )
                        )
        ]


roleTag : Types.Role -> String
roleTag role =
    case role of
        Types.Facilitator ->
            "facilitator"

        Types.Player ->
            "player"
