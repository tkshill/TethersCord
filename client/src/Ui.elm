module Ui exposing
    ( accent
    , banner
    , card
    , danger
    , facilitatorTint
    , ghostButton
    , ink
    , inkSoft
    , line
    , lg
    , md
    , mono
    , onBlur
    , onEnter
    , page
    , primaryButton
    , sans
    , sectionTitle
    , sm
    , stoneChip
    , xl
    , xs
    )

{-| The visual system for the Activity: one warm-paper surface, one slate accent,
a small spacing and type scale, and the handful of building blocks the views
assemble. Deliberately spare — it should read like a printed play aid, not a
dashboard.
-}

import Element exposing (Attribute, Color, Element, el, fill, maximum, padding, rgb255, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Events
import Json.Decode as Decode



-- PALETTE


paper : Color
paper =
    rgb255 253 252 250


panel : Color
panel =
    rgb255 255 255 255


ink : Color
ink =
    rgb255 38 38 42


inkSoft : Color
inkSoft =
    rgb255 122 120 116


line : Color
line =
    rgb255 228 225 220


accent : Color
accent =
    rgb255 74 96 130


accentText : Color
accentText =
    rgb255 253 252 250


facilitatorTint : Color
facilitatorTint =
    rgb255 122 74 44


danger : Color
danger =
    rgb255 168 74 74



-- SPACING SCALE


xs : Int
xs =
    4


sm : Int
sm =
    8


md : Int
md =
    12


lg : Int
lg =
    20


xl : Int
xl =
    32



-- TYPE


sans : List Font.Font
sans =
    [ Font.typeface "Inter"
    , Font.typeface "-apple-system"
    , Font.typeface "Segoe UI"
    , Font.typeface "Roboto"
    , Font.sansSerif
    ]


mono : List Font.Font
mono =
    [ Font.typeface "SF Mono"
    , Font.typeface "Menlo"
    , Font.typeface "Consolas"
    , Font.monospace
    ]



-- LAYOUT


{-| The outer frame. Centres a readable column on the paper surface.
-}
page : List (Element msg) -> Html msg
page children =
    Element.layout
        [ Background.color paper
        , Font.color ink
        , Font.family sans
        , Font.size 14
        , padding lg
        ]
        (Element.column
            [ spacing lg
            , width (fill |> maximum 880)
            , Element.centerX
            ]
            children
        )


card : List (Element msg) -> Element msg
card children =
    Element.column
        [ Background.color panel
        , Border.color line
        , Border.width 1
        , Border.rounded 8
        , padding lg
        , spacing md
        , width fill
        ]
        children


sectionTitle : String -> Element msg
sectionTitle label =
    el
        [ Font.size 12
        , Font.semiBold
        , Font.color inkSoft
        , Font.letterSpacing 0.8
        ]
        (text (String.toUpper label))


{-| A quiet status line. Errors (anything mentioning "Failed") tint red.
-}
banner : String -> Element msg
banner status =
    let
        tone =
            if String.contains "Failed" status || String.contains "failed" status then
                danger

            else
                inkSoft
    in
    el [ Font.size 12, Font.color tone ] (text status)



-- CONTROLS


primaryButton : { onPress : Maybe msg, label : String } -> Element msg
primaryButton config =
    Input.button
        [ Background.color accent
        , Font.color accentText
        , Font.size 13
        , Font.semiBold
        , paddingXY_ md sm
        , Border.rounded 6
        , Element.mouseOver [ Background.color ink ]
        ]
        { onPress = config.onPress, label = text config.label }


ghostButton : { onPress : Maybe msg, label : String } -> Element msg
ghostButton config =
    Input.button
        [ Background.color panel
        , Font.color ink
        , Font.size 13
        , paddingXY_ md sm
        , Border.color line
        , Border.width 1
        , Border.rounded 6
        , Element.mouseOver [ Border.color accent, Font.color accent ]
        ]
        { onPress = config.onPress, label = text config.label }


{-| A stone: a filled circle with its name captioned beneath. `swatch` is the
fill.
-}
stoneChip : Color -> String -> Element msg
stoneChip swatch label =
    Element.column
        [ spacing xs, Font.size 10, Font.color inkSoft ]
        [ el
            [ width (Element.px 22)
            , Element.height (Element.px 22)
            , Background.color swatch
            , Border.color line
            , Border.width 1
            , Border.rounded 999
            , Element.centerX
            ]
            Element.none
        , el [ Element.centerX ] (text label)
        ]


paddingXY_ : Int -> Int -> Attribute msg
paddingXY_ x y =
    Element.paddingXY x y



-- EVENTS


{-| Fire `msg` when the Enter key is pressed inside an input.
-}
onEnter : msg -> Attribute msg
onEnter msg =
    Element.htmlAttribute
        (Html.Events.on "keydown"
            (Decode.field "key" Decode.string
                |> Decode.andThen
                    (\key ->
                        if key == "Enter" then
                            Decode.succeed msg

                        else
                            Decode.fail "not Enter"
                    )
            )
        )


{-| Fire `msg` when an input loses focus.
-}
onBlur : msg -> Attribute msg
onBlur msg =
    Element.htmlAttribute (Html.Events.onBlur msg)
