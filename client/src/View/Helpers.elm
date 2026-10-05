module View.Helpers exposing
    ( ViewContext
    , aspectFieldId
    , characterLabel
    , contextAspectFieldId
    , glossaryTitle
    , inlineInputAttrs
    , inputAttrs
    , placeholder
    , tip
    , tipAttrs
    )

{-| Small view helpers shared by more than one of the `View.*` section modules:
the `ViewContext` record threaded through every section, the DOM ids ✎ focuses,
the bordered-input
attributes (boxed, and the hairline-only form the sheet and context rows use),
the plain placeholder line, and the two glossary-tooltip helpers that pair a
label with its `Copy.Terms` gloss.
-}

import Action exposing (Action)
import Copy
import Copy.Terms as Terms
import Element exposing (Element, el, none, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html.Attributes
import Aspect exposing (Aspect)
import Time
import Types exposing (..)
import Ui


{-| The slices of `Model` every section needs. Computed once in `View.view` and
passed to each `View.*` module; a section that needs more model state takes its
own small record alongside this.
-}
type alias ViewContext =
    { facilitator : Bool
    , myId : Maybe String
    , zone : Time.Zone
    , inflight : List Action
    , username : String
    }


{-| The DOM id of an aspect's text field on a sheet, so ✎ can focus it.
-}
aspectFieldId : Int -> Aspect -> String
aspectFieldId slot aspect =
    "aspect-" ++ String.fromInt slot ++ "-" ++ Aspect.toWire aspect


{-| The DOM id of a context aspect's text field, so ✎ can focus it.
-}
contextAspectFieldId : String -> String
contextAspectFieldId contextAspectId =
    "context-" ++ contextAspectId


placeholder : String -> Element msg
placeholder label =
    el [ Font.size 13, Font.color Ui.inkSoft ] (text label)


{-| A section-card title carrying a native tooltip with its glossary gloss.
`label` is the card heading; `termKey` is the `Copy.Terms` name to look the gloss
up by (they differ where the card is plural, e.g. "Moves" / "Move").
-}
glossaryTitle : String -> String -> Element msg
glossaryTitle label termKey =
    Ui.withTip (Terms.termShort termKey) (Ui.sectionTitle label)


{-| Wrap an inline label or button in a native tooltip for a glossary term,
looked up by name. An unknown name adds no tooltip. Shrink-wraps, so it is for
an element that is already its own size; for a full-width form field, put
`tipAttrs` on the input instead so its width is untouched.
-}
tip : String -> Element msg -> Element msg
tip termKey child =
    Ui.withTip (Terms.termShort termKey) child


{-| The `title`-attribute form of `tip`, to drop straight into an input's
attribute list so the tooltip covers the field without a wrapping element. Empty
list for an unknown term.
-}
tipAttrs : String -> List (Element.Attribute msg)
tipAttrs termKey =
    case Terms.termShort termKey of
        "" ->
            []

        gloss ->
            [ Element.htmlAttribute (Html.Attributes.title gloss) ]


inputAttrs : List (Element.Attribute msg)
inputAttrs =
    [ Element.paddingXY 8 5
    , Border.color Ui.edge
    , Border.width 1
    , Border.rounded 5
    , Font.size 13
    ]


{-| A field with only a hairline beneath it, turning accent on focus — the
sheet's fields and the context rows, where a box around every value would be
noise.
-}
inlineInputAttrs : List (Element.Attribute msg)
inlineInputAttrs =
    [ Element.paddingXY 4 2
    , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
    , Border.color Ui.line
    , Border.rounded 0
    , Background.color (Element.rgba255 0 0 0 0)
    , Font.size 13
    , Element.focused [ Border.color Ui.accent ]
    ]


{-| A character's name, falling back to its slot number. Matches the worker's
`characterLabel` used in log lines.
-}
characterLabel : CharacterSheet -> String
characterLabel ch =
    if String.trim ch.name /= "" then
        ch.name

    else
        Copy.characterFallback ch.slot
