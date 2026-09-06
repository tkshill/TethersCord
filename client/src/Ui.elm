module Ui exposing
    ( accent
    , baneFill
    , banner
    , boonDot
    , confirmButton
    , errorNote
    , boonFill
    , card
    , danger
    , divider
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
    , onScrolledToBottom
    , page
    , pledgedStoneChip
    , primaryButton
    , sans
    , sectionTitle
    , sm
    , speakerColor
    , stoneChip
    , tab
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


{-| Stone fills. A Boon is near-white on the paper surface; a Bane is near-black.
-}
boonFill : Color
boonFill =
    rgb255 249 248 246


baneFill : Color
baneFill =
    rgb255 42 42 46


danger : Color
danger =
    rgb255 168 74 74


{-| A stable colour per speaker at the table. `0` is the facilitator; players
take `1`, `2`, `3` in the order they first appear in the log. Wraps defensively.
-}
speakerColor : Int -> Color
speakerColor index =
    case modBy 4 index of
        1 ->
            rgb255 74 96 130

        2 ->
            rgb255 74 122 90

        3 ->
            rgb255 138 82 122

        _ ->
            facilitatorTint



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


{-| The steady-state status line: auth progress, "Connected.", reconnection.
Always the quiet tone — failures are shown separately by `errorNote`.
-}
banner : String -> Element msg
banner status =
    el [ Font.size 12, Font.color inkSoft ] (text status)


{-| A transient failure note, shown in the danger tone beneath the status line.
Renders nothing when there is no error.
-}
errorNote : Maybe String -> Element msg
errorNote maybeError =
    case maybeError of
        Just message ->
            el [ Font.size 12, Font.color danger ] (text message)

        Nothing ->
            Element.none


{-| A centred caption with a hairline either side. Used for the log's day
dividers.
-}
divider : String -> Element msg
divider label =
    Element.row
        [ width fill, spacing sm, Element.paddingXY 0 xs ]
        [ rule
        , el [ Font.size 10, Font.color inkSoft, Font.letterSpacing 0.5 ] (text label)
        , rule
        ]


rule : Element msg
rule =
    el
        [ width fill
        , Element.height (Element.px 1)
        , Background.color line
        , Element.centerY
        ]
        Element.none



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


{-| A destructive action behind a one-click arming step. Idle, it is a single
ghost button; armed, it becomes a danger-tinted confirm button beside a Cancel.
The caller flips `armed` from its own model.
-}
confirmButton :
    { armed : Bool
    , idle : String
    , confirm : String
    , onArm : msg
    , onConfirm : msg
    , onCancel : msg
    }
    -> Element msg
confirmButton config =
    if config.armed then
        Element.row [ Element.spacing sm ]
            [ Input.button
                [ Background.color danger
                , Font.color accentText
                , Font.size 13
                , Font.semiBold
                , paddingXY_ md sm
                , Border.rounded 6
                ]
                { onPress = Just config.onConfirm, label = text config.confirm }
            , ghostButton { onPress = Just config.onCancel, label = "Cancel" }
            ]

    else
        ghostButton { onPress = Just config.onArm, label = config.idle }


{-| One entry in a tab strip. The selected tab reads as the accent button; the
rest are quiet until hovered.
-}
tab : Bool -> String -> msg -> Element msg
tab selected label msg =
    Input.button
        [ Font.size 12
        , paddingXY_ md xs
        , Border.rounded 6
        , Border.width 1
        , Background.color
            (if selected then
                accent

             else
                panel
            )
        , Font.color
            (if selected then
                accentText

             else
                inkSoft
            )
        , Border.color
            (if selected then
                accent

             else
                line
            )
        , Element.mouseOver
            (if selected then
                []

             else
                [ Border.color accent, Font.color accent ]
            )
        ]
        { onPress = Just msg, label = text label }


{-| A stone: a filled circle with its name captioned beneath. `swatch` is the
fill.
-}
stoneChip : Color -> String -> Element msg
stoneChip swatch label =
    labeledStone swatch False label


{-| As `stoneChip`, but marked with a centre dot — used to show a boon that has
been pledged into the current roll sitting in the bag.
-}
pledgedStoneChip : Color -> String -> Element msg
pledgedStoneChip swatch label =
    labeledStone swatch True label


labeledStone : Color -> Bool -> String -> Element msg
labeledStone swatch marked label =
    Element.column
        [ spacing xs, Font.size 10, Font.color inkSoft ]
        [ el [ Element.centerX ] (stoneCircle swatch marked 22)
        , el [ Element.centerX ] (text label)
        ]


{-| A small boon circle with no caption, for the row of boons on a character
sheet. Marked with a centre dot when the boon is pledged into the current roll.
-}
boonDot : Bool -> Element msg
boonDot marked =
    stoneCircle boonFill marked 16


{-| The bare circle both stone shapes are built from. `marked` draws an accent
centre dot; `size` is the diameter in pixels.
-}
stoneCircle : Color -> Bool -> Int -> Element msg
stoneCircle swatch marked size =
    el
        [ width (Element.px size)
        , Element.height (Element.px size)
        , Background.color swatch
        , Border.color line
        , Border.width 1
        , Border.rounded 999
        ]
        (if marked then
            el
                [ Element.centerX
                , Element.centerY
                , width (Element.px (Basics.max 4 (size // 3)))
                , Element.height (Element.px (Basics.max 4 (size // 3)))
                , Background.color accent
                , Border.rounded 999
                ]
                Element.none

         else
            Element.none
        )


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


{-| On every scroll of the element, report whether it is now within `slack`
pixels of its bottom. Lets a scrollable region tell the app when the viewer has
left the bottom to read back, and when they have returned.
-}
onScrolledToBottom : Float -> (Bool -> msg) -> Attribute msg
onScrolledToBottom slack toMsg =
    Element.htmlAttribute
        (Html.Events.on "scroll"
            (Decode.map3
                (\scrollTop scrollHeight clientHeight ->
                    toMsg (scrollHeight - scrollTop - clientHeight <= slack)
                )
                (Decode.at [ "target", "scrollTop" ] Decode.float)
                (Decode.at [ "target", "scrollHeight" ] Decode.float)
                (Decode.at [ "target", "clientHeight" ] Decode.float)
            )
        )
