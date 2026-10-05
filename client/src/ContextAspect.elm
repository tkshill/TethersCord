module ContextAspect exposing (ContextAspect, Polarity(..), polarityLabel)

{-| A context boon or context bane: an aspect of the situation, owned by no
character, that can be highlighted once (CONTEXT.md "Context aspect"). It comes
from an accepted critical, a Create (a boon), a Complicate (a blank bane the
facilitator words, tagged with the aspect it drew on) or the facilitator.
Highlighting it marks it `consumed` rather than deleting it.
-}

import Aspect exposing (Aspect)


{-| Which way a context aspect pushes the die: a `Boon` steps it up, a `Bane`
steps it down.
-}
type Polarity
    = Boon
    | Bane


polarityLabel : Polarity -> String
polarityLabel polarity =
    case polarity of
        Boon ->
            "Boon"

        Bane ->
            "Bane"


type alias ContextAspect =
    { id : String
    , polarity : Polarity
    , text : String
    , createdByName : String
    , consumed : Bool

    -- The character aspect a Complicate drew this bane from: ( slot, aspect ).
    , fromAspect : Maybe ( Int, Aspect )
    }
