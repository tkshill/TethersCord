module Format exposing (clock, date, timestamp)

{-| Small pure formatting helpers.
-}

import Time


{-| Render a message's creation time as `YYYY-MM-DD HH:MM` in the given zone.
The date is included because a table's log persists across sessions on
different days.
-}
timestamp : Time.Zone -> Time.Posix -> String
timestamp zone posix =
    date zone posix ++ " " ++ clock zone posix


{-| Just the wall-clock time, `HH:MM`. The log pairs this with day dividers, so
rows do not repeat the date.
-}
clock : Time.Zone -> Time.Posix -> String
clock zone posix =
    let
        pad n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    pad (Time.toHour zone posix) ++ ":" ++ pad (Time.toMinute zone posix)


{-| Just the calendar date, `YYYY-MM-DD`, in the given zone. Used for the log's
day dividers.
-}
date : Time.Zone -> Time.Posix -> String
date zone posix =
    let
        pad n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    String.fromInt (Time.toYear zone posix)
        ++ "-"
        ++ pad (monthNumber (Time.toMonth zone posix))
        ++ "-"
        ++ pad (Time.toDay zone posix)


monthNumber : Time.Month -> Int
monthNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
