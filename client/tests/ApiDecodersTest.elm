module ApiDecodersTest exposing (suite)

{-| The `Api.decodeGameState` decoder against a full captured wire payload. One
snapshot exercises every sub-decoder, including the shapes that are easy to get
wrong: session aspects, used abilities, and a proposal of each `kind`.
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
        , test "reads committed boons" <|
            \_ ->
                decoded
                    |> Result.map .committedBoons
                    |> Expect.equal (Ok [ { slot = 1, count = 2 } ])
        , test "reads every proposal kind, with nullable slot/sessionAspectId/targetSlot" <|
            \_ ->
                decoded
                    |> Result.map (.proposals >> List.map (\p -> ( p.kind, p.slot, p.targetSlot )))
                    |> Expect.equal
                        (Ok
                            [ ( Kind.AddBoon, Nothing, Nothing )
                            , ( Kind.Highlight, Just 1, Nothing )
                            , ( Kind.AbilityProposal Kind.Complicate, Just 1, Just 2 )
                            , ( Kind.UseSessionBoon, Just 1, Nothing )
                            ]
                        )
        , test "carries the use-session-boon proposal's sessionAspectId" <|
            \_ ->
                decoded
                    |> Result.map (.proposals >> List.filterMap .sessionAspectId)
                    |> Expect.equal (Ok [ "f1" ])
        , test "reads session aspects, their kind, and their context note" <|
            \_ ->
                decoded
                    |> Result.map (.sessionAspects >> List.map (\b -> ( b.id, b.kind, b.text )))
                    |> Expect.equal (Ok [ ( "f1", Bane, "the rope still holds" ) ])
        , test "reads used abilities per slot" <|
            \_ ->
                decoded
                    |> Result.map .usedAbilities
                    |> Expect.equal (Ok [ { slot = 1, kinds = [ Kind.Alter, Kind.AddDetail ] } ])
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
