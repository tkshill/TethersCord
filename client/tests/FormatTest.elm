module FormatTest exposing (suite)

{-| The pure log-formatting helpers.
-}

import Expect
import Format
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "formatting helpers"
        [ describe "Format.timestamp (UTC)"
            [ test "the epoch renders as YYYY-MM-DD HH:MM" <|
                \_ ->
                    Format.timestamp Time.utc (Time.millisToPosix 0)
                        |> Expect.equal "1970-01-01 00:00"
            , test "zero-pads the month, day, hour, and minute" <|
                \_ ->
                    -- 2024-03-07 05:09 UTC
                    Format.timestamp Time.utc (Time.millisToPosix 1709788140000)
                        |> Expect.equal "2024-03-07 05:09"
            , test "date and clock compose into timestamp" <|
                \_ ->
                    let
                        t =
                            Time.millisToPosix 1709788140000
                    in
                    Format.timestamp Time.utc t
                        |> Expect.equal (Format.date Time.utc t ++ " " ++ Format.clock Time.utc t)
            ]
        ]
