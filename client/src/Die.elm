module Die exposing (Die, Direction(..), base, fromSize, label, ladder, size, sizes, step, stepDown, stepUp)

{-| The one die the table rolls at a junction, as its rung on the ladder
(RULES.md "The die", ADR 0001). The Worker owns the rules — it rolls and
classifies — but the client needs the ladder to disable a step at either end.

`Die` is opaque: the only dice are the six rungs, so a size off the ladder
cannot be represented, and `Api.Decode` fails on one rather than defaulting.
`sizes` is pinned to the Worker's `LADDER` by a parity test
(`worker/test/rules/ladderParity.test.ts`, which reads this file).

-}


type Die
    = Die Int


{-| The ladder's sizes, low to high. The parity test reads this list from
this file's source, so keep it a literal on one line.
-}
sizes : List Int
sizes =
    [ 6, 8, 10, 12, 16, 20 ]


ladder : List Die
ladder =
    List.map Die sizes


{-| The d10, the die's rung whenever no junction has changed it.
-}
base : Die
base =
    Die 10


fromSize : Int -> Maybe Die
fromSize n =
    if List.member n sizes then
        Just (Die n)

    else
        Nothing


size : Die -> Int
size (Die n) =
    n


{-| `d10`.
-}
label : Die -> String
label (Die n) =
    "d" ++ String.fromInt n


{-| One rung up, or `Nothing` at the top of the ladder.
-}
stepUp : Die -> Maybe Die
stepUp (Die n) =
    sizes |> List.filter (\s -> s > n) |> List.head |> Maybe.map Die


{-| One rung down, or `Nothing` at the bottom of the ladder.
-}
stepDown : Die -> Maybe Die
stepDown (Die n) =
    sizes |> List.filter (\s -> s < n) |> List.reverse |> List.head |> Maybe.map Die


{-| Which way a step moves the die.
-}
type Direction
    = Up
    | Down


step : Direction -> Die -> Maybe Die
step direction =
    case direction of
        Up ->
            stepUp

        Down ->
            stepDown
