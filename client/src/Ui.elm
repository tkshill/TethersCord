module Ui exposing
    ( accent
    , baneMarks
    , banner
    , boonMarks
    , confirmButton
    , danger
    , divider
    , dragHandle
    , errorNote
    , facilitatorTint
    , flat
    , ghostButton
    , ink
    , inkSoft
    , line
    , linkButton
    , lg
    , md
    , mono
    , onBlur
    , onEnter
    , onScrolledToBottom
    , onlyWhen
    , oneLine
    , page
    , panel
    , paper
    , press
    , primaryButton
    , sans
    , scrollArea
    , sectionTitle
    , shrinkable
    , sm
    , speakerColor
    , tab
    , tint
    , toolTab
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


{-| `Just msg` unless `action` already has a request in flight (it is in
`inflight`), in which case `Nothing` — which renders a button disabled, so an
eager double-click is a no-op in the UI as well as in `update`.
-}
press : List a -> a -> msg -> Maybe msg
press inflight action msg =
    if List.member action inflight then
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


{-| A faint warm tint for a strip that sits apart from the paper — the proposal
strip, the session-controls row, a highlighted log line.
-}
tint : Color
tint =
    rgb255 246 244 240


{-| The chip behind the selected tool tab.
-}
selectedWash : Color
selectedWash =
    rgb255 235 232 226


facilitatorTint : Color
facilitatorTint =
    rgb255 122 74 44


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


{-| The outer frame (roadmap section 27, mockup 2a): `top` is a slim,
non-scrolling stack (the notes and the one-line status strip) sized to its
content; `columns` fills the rest of the viewport as a fixed-height row of two
panels and the drag handle between them, edge to edge with no outer padding.
Each panel owns its own scrolling regions. `html` / `body` need `height: 100%`
themselves (`client/index.html`) for `height fill` to have a viewport to fill
against.
-}
page : { top : List (Element msg), columns : List (Element msg) } -> Html msg
page sections =
    Element.layout
        [ Background.color paper
        , Font.color ink
        , Font.family sans
        , Font.size 13
        , height fill
        ]
        (Element.column [ height fill, width fill ]
            [ Element.column [ width fill ] sections.top
            , Element.row [ height fill, width fill, shrinkable ] sections.columns
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


{-| A vertical stack that fills its container and scrolls on its own once its
content overflows — a tool panel's body. `shrinkable` is what lets it clip
instead of growing.
-}
scrollArea : List (Element msg) -> Element msg
scrollArea children =
    Element.column
        [ height fill
        , width fill
        , spacing sm
        , Element.scrollbarY
        , shrinkable
        ]
        children


{-| A single line of text that ellipsises instead of wrapping when it is too long
for its slot — the strip's goal and the proposal strip's summary. It sits in a
`width fill` slot that may shrink below its content (`min-width: 0`); the text
itself is a plain block so `text-overflow` applies, which a wrapping paragraph
would not honour.
-}
oneLine : List (Attribute msg) -> String -> Element msg
oneLine attrs content =
    el
        (width fill
            :: Element.htmlAttribute (Html.Attributes.style "min-width" "0")
            :: attrs
        )
        (Element.html
            (Html.div
                [ Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "overflow" "hidden"
                , Html.Attributes.style "text-overflow" "ellipsis"
                ]
                [ Html.text content ]
            )
        )


{-| A tool's content: a plain stack with no surface of its own. The panel it
sits in supplies the background and the edges, so the tools stay flat.
-}
flat : List (Element msg) -> Element msg
flat children =
    Element.column [ spacing sm, width fill ] children


sectionTitle : String -> Element msg
sectionTitle label =
    el
        [ Font.size 10
        , Font.semiBold
        , Font.color inkSoft
        , Font.letterSpacing 0.5
        ]
        (text (String.toUpper label))


{-| The steady-state status line: auth progress, "Connected.", reconnection.
Always the quiet tone — failures are shown separately by `errorNote`.
-}
banner : String -> Element msg
banner status =
    el [ Font.size 11, Font.color inkSoft ] (text status)


{-| A transient failure note, shown in the danger tone beneath the status line.
Renders nothing when there is no error.
-}
errorNote : Maybe String -> Element msg
errorNote maybeError =
    case maybeError of
        Just message ->
            el [ Font.size 11, Font.color danger ] (text message)

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


{-| The draggable handle between two resizable panels (roadmap section 24, kept
by 27): a slim `cursor: col-resize` strip that reads as the hairline between the
panels.
`onStart` fires on mousedown; the caller tracks the mouse from there for as
long as its own "is this dragging" flag stays true (`Main.subscriptions`),
since a handle this size cannot itself receive the `mousemove` events once the
pointer leaves it.
-}
dragHandle : msg -> Element msg
dragHandle onStart =
    el
        [ width (Element.px 5)
        , height fill
        , Element.htmlAttribute (Html.Attributes.style "cursor" "col-resize")
        , Element.htmlAttribute (Html.Events.on "mousedown" (Decode.succeed onStart))
        ]
        (el
            [ Element.centerX
            , Element.centerY
            , width (Element.px 1)
            , height fill
            , Background.color line
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
        , Font.size 12
        , Font.semiBold
        , paddingXY_ 9 3
        , Border.rounded 4
        , Element.mouseOver [ Background.color ink ]
        ]
        { onPress = config.onPress, label = text config.label }


ghostButton : { onPress : Maybe msg, label : String } -> Element msg
ghostButton config =
    Input.button
        [ Background.color panel
        , Font.color ink
        , Font.size 12
        , paddingXY_ 8 2
        , Border.color line
        , Border.width 1
        , Border.rounded 4
        , Element.mouseOver [ Border.color accent, Font.color accent ]
        ]
        { onPress = config.onPress, label = text config.label }


{-| A quiet text action for a row's own controls (Use, Undo, withdraw): no
border, muted until hovered.
-}
linkButton : { onPress : Maybe msg, label : String } -> Element msg
linkButton config =
    Input.button
        [ Font.size 11
        , Font.color inkSoft
        , Element.mouseOver [ Font.color accent ]
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
                , Font.size 12
                , Font.semiBold
                , paddingXY_ 9 3
                , Border.rounded 4
                ]
                { onPress = Just config.onConfirm, label = text config.confirm }
            , ghostButton { onPress = Just config.onCancel, label = "Cancel" }
            ]

    else
        ghostButton { onPress = Just config.onArm, label = config.idle }


{-| One entry in a compact tab strip (the character slots on the Sheet): the
selected one reads as the accent button, the rest are quiet until hovered.
-}
tab : Bool -> String -> msg -> Element msg
tab selected label msg =
    Input.button
        ([ Font.size 12
         , paddingXY_ 7 2
         , Border.rounded 4
         , Font.color
            (if selected then
                accentText

             else
                inkSoft
            )
         , Background.color
            (if selected then
                accent

             else
                Element.rgba255 0 0 0 0
            )
         ]
            ++ (if selected then
                    [ Font.semiBold ]

                else
                    [ Element.mouseOver [ Font.color ink ] ]
               )
        )
        { onPress = Just msg, label = text label }


{-| One glyph tab in the tool strip (mockup 2a). The selected tool shows its
glyph and its name on a tinted chip; the others are a bare glyph, named by `tip`
(a native tooltip, which is also where a count such as "1 proposal waiting"
goes).
-}
toolTab : { glyph : String, label : String, tip : String, selected : Bool, onPress : msg } -> Element msg
toolTab config =
    Input.button
        ([ Element.htmlAttribute (Html.Attributes.title config.tip)
         , Border.rounded 4
         , Font.color
            (if config.selected then
                ink

             else
                inkSoft
            )
         ]
            ++ (if config.selected then
                    [ Background.color selectedWash, Font.size 12, Font.semiBold, paddingXY_ 8 3 ]

                else
                    [ width (Element.px 26)
                    , paddingXY_ 0 3
                    , Font.size 13
                    , Element.mouseOver [ Background.color tint, Font.color ink ]
                    ]
               )
        )
        { onPress = Just config.onPress
        , label =
            if config.selected then
                text (config.glyph ++ " " ++ config.label)

            else
                el [ Element.centerX ] (text config.glyph)
        }


{-| The run of `+` marks for `n` boons, the table's boon shorthand (bag, sheet).
-}
boonMarks : Int -> Element msg
boonMarks n =
    el [ Font.letterSpacing 2 ] (text (String.repeat (Basics.max 0 n) "+"))


{-| The run of `−` marks for `n` banes, in the danger tone.
-}
baneMarks : Int -> Element msg
baneMarks n =
    el [ Font.letterSpacing 2, Font.color danger ] (text (String.repeat (Basics.max 0 n) "−"))


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
