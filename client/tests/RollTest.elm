module RollTest exposing (suite)

import Expect
import Roll exposing (Stone(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Roll.without"
        [ test "removes one of each taken stone, by kind" <|
            \_ ->
                Roll.without [ Boon, Bane ] [ Boon, Bane, Boon, Bane, Boon ]
                    |> Expect.equal [ Boon, Bane, Boon ]
        , test "removes only as many as were taken, when the pool holds several" <|
            \_ ->
                Roll.without [ Boon, Boon ] [ Boon, Bane, Boon, Boon ]
                    |> Expect.equal [ Bane, Boon ]
        , test "ignores a stone the pool does not hold" <|
            \_ ->
                Roll.without [ Bane ] [ Boon, Boon ]
                    |> Expect.equal [ Boon, Boon ]
        , test "taking nothing leaves the pool alone" <|
            \_ ->
                Roll.without [] [ Boon, Bane ]
                    |> Expect.equal [ Boon, Bane ]
        ]
