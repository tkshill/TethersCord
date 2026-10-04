module Aspect exposing (Aspect(..), all, label, toWire)

{-| The three character aspects every character is written around (CONTEXT.md
"Character aspect"). Its own module so that `ContextAspect` (a Complicate's
bane names the aspect it came from) and `Types` can both use it without an
import cycle.
-}


type Aspect
    = Archetype
    | Desire
    | Quest


all : List Aspect
all =
    [ Archetype, Desire, Quest ]


label : Aspect -> String
label aspect =
    case aspect of
        Archetype ->
            "Archetype"

        Desire ->
            "Desire"

        Quest ->
            "Quest"


{-| The aspect's name on the wire (`archetype` / `desire` / `quest`).
`Api.Decode.aspect` is its inverse.
-}
toWire : Aspect -> String
toWire aspect =
    case aspect of
        Archetype ->
            "archetype"

        Desire ->
            "desire"

        Quest ->
            "quest"
