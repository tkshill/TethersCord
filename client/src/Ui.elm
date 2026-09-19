module Ui exposing
    ( accent
    , baneDot
    , baneFill
    , banner
    , boonDot
    , confirmButton
    , errorNote
    , boonFill
    , card
    , cardFill
    , danger
    , divider
    , dragHandle
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
    , onlyWhen
    , page
    , highlightedStoneChip
    , press
    , primaryButton
    , sans
    , scrollArea
    , scrollColumn
    , sectionTitle
    , shrinkable
    , sm
    , speakerColor
    , stoneChip
    , tab
    , withTip
    , xl
    , xs
    )

{-| The visual system for the Activity: one warm-paper surface, one slate accent,
a small spacing and type scale, and the handful of building blocks the views
assemble. Deliberately spare — it should read like a printed play aid, not a
dashboard.
-}

import Element exposing (Attribute, Color, Element, el, fill, height, padding, rgb255, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Set exposing (Set)



-- CONTROL GATING


{-| `Just msg` unless `key` already has a request in flight (it is in
`inflight`), in which case `Nothing` — which renders a button disabled, so an
eager double-click is a no-op in the UI as well as in `update`.
-}
press : Set String -> String -> msg -> Maybe msg
press inflight key msg =
    if Set.member key inflight then
        Nothing

    else
        Just msg


{-| The given elements when `cond` holds, an empty list otherwise. Used to keep
role-gated controls out of a list without a stray `none`.
-}
onlyWhen : Bool -> List (Element msg) -> List (Element msg)
onlyWhen cond elements =
    if cond then
        elements

    else
        []


{-| Attach a native browser tooltip (the HTML `title` attribute) to an element,
so hovering a game term shows its short gloss. An empty string adds nothing, so a
missing glossary entry degrades to no tooltip. Hover-only — the "How to play"
card is the path for touch.

It shrink-wraps, so it is for an inline label or a button; a full-width form
field takes the `title` attribute directly instead, to leave its width alone.
-}
withTip : String -> Element msg -> Element msg
withTip tipText child =
    if tipText == "" then
        child

    else
        el [ Element.htmlAttribute (Html.Attributes.title tipText) ] child



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


{-| The outer frame (roadmap sections 23.5 / 24): `top` is a slim, non-scrolling
strip (header, connection/status notes, the top bar) sized to its content;
`columns` fills the rest of the viewport as a fixed-height row, each entry
expected to be one `scrollColumn` (or, for a panel that manages its own
scrolling region internally, an `Element.column [ height fill, width
(fillPortion n) ]` built by the caller); `bottom` is a second slim,
non-scrolling strip pinned under the row — the composer, since 24 moved it off
the log column onto the page (any tab can send a message, not just the Log
one). `html` / `body` need `height: 100%` themselves (`client/index.html`) for
`height fill` to have a viewport to fill against.
-}
page : { top : List (Element msg), columns : List (Element msg), bottom : List (Element msg) } -> Html msg
page sections =
    Element.layout
        [ Background.color paper
        , Font.color ink
        , Font.family sans
        , Font.size 14
        , height fill
        ]
        (Element.column [ height fill, width fill ]
            [ Element.column [ spacing lg, padding lg, width fill ] sections.top
            , Element.row
                [ height fill
                , width fill
                , spacing lg
                , Element.paddingEach { top = 0, right = lg, bottom = lg, left = lg }
                , shrinkable
                ]
                sections.columns
            , if List.isEmpty sections.bottom then
                Element.none

              else
                Element.column
                    [ spacing lg
                    , padding lg
                    , width fill
                    , Border.widthEach { top = 1, right = 0, bottom = 0, left = 0 }
                    , Border.color line
                    ]
                    sections.bottom
            ]
        )


{-| A flex child's `height fill` alone is not enough to make it — or anything
scrollable nested inside it — actually clip: CSS flex items default to
`min-height: auto`, which refuses to shrink a flex-grow item below its
content's natural size, so the item (and everything above it, up to `page`'s
outer column) just grows to fit instead of clipping and scrolling. This is
the fix, on every element along a scrolling region's flex-column ancestry
that is *itself* sized by `height fill` rather than by cross-axis stretch —
`page`'s columns row, `scrollColumn`, `cardFill`, and a scrolling region
inside one (`View.Log`'s message list).
-}
shrinkable : Attribute msg
shrinkable =
    Element.htmlAttribute (Html.Attributes.style "min-height" "0")


{-| One of the page's top-level independently-scrolling columns: a vertical
stack of cards, `fillPortion`-wide, that scrolls on its own once its content
overflows the viewport.
-}
scrollColumn : Int -> List (Element msg) -> Element msg
scrollColumn portion children =
    Element.column
        [ height fill
        , width (Element.fillPortion portion)
        , spacing lg
        , Element.scrollbarY
        , shrinkable
        ]
        children


{-| As `scrollColumn`, but `width fill` instead of a `fillPortion` of the page
row — for a scrolling stack of cards nested inside a panel that already owns
its width itself, such as one tab's content in the right panel (roadmap
section 24).
-}
scrollArea : List (Element msg) -> Element msg
scrollArea children =
    Element.column
        [ height fill
        , width fill
        , spacing lg
        , Element.scrollbarY
        , shrinkable
        ]
        children


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


{-| As `card`, but fills the height of its container instead of shrinking to
its content — for the log card, the one card that fills a whole column
(right, 23.5) rather than sitting in a scrolling stack of them.
-}
cardFill : List (Element msg) -> Element msg
cardFill children =
    Element.column
        [ Background.color panel
        , Border.color line
        , Border.width 1
        , Border.rounded 8
        , padding lg
        , spacing md
        , width fill
        , height fill
        , shrinkable
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


{-| The draggable handle between two resizable panels (roadmap section 24, the
1c layout variant): a slim `cursor: col-resize` strip with a small grip mark.
`onStart` fires on mousedown; the caller tracks the mouse from there for as
long as its own "is this dragging" flag stays true (`Main.subscriptions`),
since a handle this size cannot itself receive the `mousemove` events once the
pointer leaves it.
-}
dragHandle : msg -> Element msg
dragHandle onStart =
    el
        [ width (Element.px 9)
        , height fill
        , Element.htmlAttribute (Html.Attributes.style "cursor" "col-resize")
        , Element.htmlAttribute (Html.Events.on "mousedown" (Decode.succeed onStart))
        ]
        (el
            [ Element.centerX
            , Element.centerY
            , width (Element.px 3)
            , Element.height (Element.px 28)
            , Background.color line
            , Border.rounded 3
            ]
            Element.none
        )


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
been highlighted into the current roll sitting in the bag.
-}
highlightedStoneChip : Color -> String -> Element msg
highlightedStoneChip swatch label =
    labeledStone swatch True label


labeledStone : Color -> Bool -> String -> Element msg
labeledStone swatch marked label =
    Element.column
        [ spacing xs, Font.size 10, Font.color inkSoft ]
        [ el [ Element.centerX ] (stoneCircle swatch marked 22)
        , el [ Element.centerX ] (text label)
        ]


{-| A small boon circle with no caption, for the row of boons on a character
sheet. Marked with a centre dot when the boon is highlighted into the current roll.
-}
boonDot : Bool -> Element msg
boonDot marked =
    stoneCircle boonFill marked 16


{-| A small bane circle with no caption, for the Banes an aspect carries
(section 19).
-}
baneDot : Element msg
baneDot =
    stoneCircle baneFill False 12


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
