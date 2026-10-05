module Outcome exposing (Outcome(..), label)

{-| What a roll's face means (CONTEXT.md "Outcome"). The Worker classifies the
face and sends the outcome; the client never reads a face itself.
-}


type Outcome
    = CriticalFriction
    | Friction
    | Flow
    | CriticalFlow


label : Outcome -> String
label outcome =
    case outcome of
        CriticalFriction ->
            "Critical Friction"

        Friction ->
            "Friction"

        Flow ->
            "Flow"

        CriticalFlow ->
            "Critical Flow"
