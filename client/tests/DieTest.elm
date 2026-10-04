module DieTest exposing (suite)

{-| The client's copy of the die ladder: the rungs, the base, and stepping
refused at either end. The Worker's `LADDER` is pinned to `Die.sizes` by
`worker/test/rules/ladderParity.test.ts`.
-}

import Die
import Expect
import Test exposing (Test, describe, test)


labels : List (Maybe Die.Die) -> List (Maybe String)
labels =
    List.map (Maybe.map Die.label)


suite : Test
suite =
    describe "Die"
        [ test "the ladder runs d6 to d20 and the base is d10" <|
            \_ ->
                ( List.map Die.label Die.ladder, Die.label Die.base )
                    |> Expect.equal ( [ "d6", "d8", "d10", "d12", "d16", "d20" ], "d10" )
        , test "knows only the ladder's sizes" <|
            \_ ->
                labels (List.map Die.fromSize [ 4, 6, 7, 10, 14, 20, 100 ])
                    |> Expect.equal [ Nothing, Just "d6", Nothing, Just "d10", Nothing, Just "d20", Nothing ]
        , test "steps one rung each way" <|
            \_ ->
                labels [ Die.stepUp Die.base, Die.stepDown Die.base, Die.step Die.Up Die.base, Die.step Die.Down Die.base ]
                    |> Expect.equal [ Just "d12", Just "d8", Just "d12", Just "d8" ]
        , test "refuses to step past either end" <|
            \_ ->
                labels
                    [ Die.fromSize 20 |> Maybe.andThen Die.stepUp
                    , Die.fromSize 6 |> Maybe.andThen Die.stepDown
                    ]
                    |> Expect.equal [ Nothing, Nothing ]
        ]
