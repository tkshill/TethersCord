module Junction exposing (Junction, hasAltered)

{-| The junction in progress: the last roll, waiting on the facilitator to
accept or reject it (RULES.md "The junction"). `die`, `face` and `outcome` are
the current roll — a reroll or an Alter replaces them, on the same die —
`rerolls` counts the replacements, and `alteredSlots` lists the characters
that have already Altered this junction.
-}

import Die exposing (Die)
import Outcome exposing (Outcome)


type alias Junction =
    { rolledBy : String
    , die : Die
    , face : Int
    , outcome : Outcome
    , rerolls : Int
    , alteredSlots : List Int
    }


{-| Whether the character in `slot` has used its one Alter this junction.
-}
hasAltered : Int -> Junction -> Bool
hasAltered slot junction =
    List.member slot junction.alteredSlots
