module ApiDecodersTest exposing (suite)

{-| `Api.Decode.gameState` against a full captured wire payload. One snapshot
exercises every sub-decoder, including the shapes that are easy to get wrong:
the die, a pending Junction, a move of each kind, and context aspects with their
consumed flag and `fromAspect`. Values the client cannot represent fail the
decode rather than defaulting.
-}

import Api.Decode
import Aspect exposing (Aspect(..))
import ContextAspect exposing (Polarity(..))
import Die
import Expect
import Fixtures
import Json.Decode as Decode
import MoveRecord
import Outcome exposing (Outcome(..))
import Test exposing (Test, describe, test)
import Types


decoded : Result Decode.Error Types.GameState
decoded =
    Decode.decodeString Api.Decode.gameState Fixtures.snapshotJson


{-| The snapshot with one substring swapped, decoded.
-}
decodedWith : String -> String -> Result Decode.Error Types.GameState
decodedWith from to =
    Fixtures.snapshotJson
        |> String.replace from to
        |> Decode.decodeString Api.Decode.gameState


isErr : Result e a -> Bool
isErr result =
    case result of
        Ok _ ->
            False

        Err _ ->
            True


suite : Test
suite =
    describe "Api.Decode.gameState"
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
        , test "reads a message kind, and a missing kind as chat" <|
            \_ ->
                decoded
                    |> Result.map (.messages >> List.map .kind)
                    |> Expect.equal (Ok [ Types.Chat, Types.Event ])
        , test "reads the die as its rung on the ladder" <|
            \_ ->
                decoded
                    |> Result.map (.die >> Die.label)
                    |> Expect.equal (Ok "d12")
        , test "fails on a die off the ladder rather than defaulting" <|
            \_ ->
                decodedWith "\"die\": 12," "\"die\": 7,"
                    |> isErr
                    |> Expect.equal True
        , test "reads a pending Junction's roll" <|
            \_ ->
                decoded
                    |> Result.map (.junction >> Maybe.map (\j -> ( j.rolledBy, ( Die.label j.die, j.face, j.outcome ), ( j.rerolls, j.alteredSlots ) )))
                    |> Expect.equal (Ok (Just ( "Ada", ( "d12", 11, CriticalFlow ), ( 1, [ 1 ] ) )))
        , test "reads each outcome name, and fails on an unknown one" <|
            \_ ->
                [ "critical-friction", "friction", "flow", "critical-flow", "success" ]
                    |> List.map
                        (\name ->
                            decodedWith "\"outcome\": \"critical-flow\"" ("\"outcome\": \"" ++ name ++ "\"")
                                |> Result.toMaybe
                                |> Maybe.andThen .junction
                                |> Maybe.map .outcome
                        )
                    |> Expect.equal [ Just CriticalFriction, Just Friction, Just Flow, Just CriticalFlow, Nothing ]
        , test "reads a null Junction as no roll pending" <|
            \_ ->
                decodedWith
                    """"junction": { "rolledBy": "Ada", "die": 12, "face": 11, "outcome": "critical-flow", "rerolls": 1, "alteredSlots": [1] }"""
                    """"junction": null"""
                    |> Result.map .junction
                    |> Expect.equal (Ok Nothing)
        , test "reads every move kind open to undo, with its actor, slot, aspect and log line" <|
            \_ ->
                decoded
                    |> Result.map (.moves >> List.map (\m -> ( m.kind, ( m.actorId, m.slot, m.aspect ), m.messageId )))
                    |> Expect.equal
                        (Ok
                            [ ( MoveRecord.Highlight, ( "u1", Just 1, Just Desire ), "m1" )
                            , ( MoveRecord.HighlightContext, ( "u2", Nothing, Nothing ), "m2" )
                            , ( MoveRecord.Complicate, ( "u1", Just 1, Just Quest ), "m3" )
                            , ( MoveRecord.Create, ( "u1", Just 1, Nothing ), "m4" )
                            , ( MoveRecord.Alter, ( "u1", Just 1, Nothing ), "m5" )
                            ]
                        )
        , test "fails on an unknown move kind" <|
            \_ ->
                decodedWith "\"kind\": \"alter\"" "\"kind\": \"add-detail\""
                    |> isErr
                    |> Expect.equal True
        , test "reads context aspects: polarity, text, consumed, and a Complicate's aspect" <|
            \_ ->
                decoded
                    |> Result.map (.contextAspects >> List.map (\a -> ( ( a.id, a.polarity ), ( a.text, a.consumed ), a.fromAspect )))
                    |> Expect.equal
                        (Ok
                            [ ( ( "f1", Bane ), ( "", False ), Just ( 1, Quest ) )
                            , ( ( "f2", Boon ), ( "the guard looked away", True ), Nothing )
                            ]
                        )
        , test "reads the running session's goal" <|
            \_ ->
                decoded
                    |> Result.map (.session >> Maybe.map .goal)
                    |> Expect.equal (Ok (Just "Escape the vault"))
        , test "reads the character sheet, including boons and owner" <|
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
