module Ui exposing
    ( accent
    , aspectBlock
    , baneMarks
    , banner
    , chip
    , boonMarks
    , class
    , confirmButton
    , accentSoft
    , danger
    , dangerGhostButton
    , dangerSoft
    , divider
    , edge
    , columnRule
    , errorNote
    , facilitatorTint
    , flat
    , fontSize
    , glyph
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
    , onEnterSubmit
    , onScrolledToBottom
    , onlyWhen
    , oneLine
    , page
    , panel
    , paper
    , pencil
    , pill
    , press
    , primaryButton
    , rollButton
    , sans
    , scrollArea
    , sectionTitle
    , shrinkable
    , shrinkableWidth
    , clipX
    , sm
    , squareButton
    , statement
    , speakerColor
    , tint
    , toolTab
    , withTip
    , wrapAnywhere
    , xl
    , xs
    )

{-| The visual system for the Activity (roadmap 32, Table v2 High contrast):
white surfaces, black ink, one deep-blue accent, a small spacing and type scale,
and the handful of building blocks the views assemble. Deliberately spare — it
should read like a printed play aid, not a dashboard.
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
    rgb255 255 255 255


panel : Color
panel =
    rgb255 255 255 255


ink : Color
ink =
    rgb255 0 0 0


{-| Labels, meta, timestamps, placeholders (12.6:1 on white).
-}
inkSoft : Color
inkSoft =
    rgb255 51 51 51


{-| Hairlines: column rules, row dividers, strip borders.
-}
line : Color
line =
    rgb255 140 140 140


{-| The 1px border on aspect blocks, buttons, inputs and chips — darker than
`line`, so a control reads as one against the white.
-}
edge : Color
edge =
    rgb255 26 26 26


accent : Color
accent =
    rgb255 10 58 140


accentText : Color
accentText =
    rgb255 255 255 255


{-| The Flow segment in the Guide's odds bars.
-}
accentSoft : Color
accentSoft =
    rgb255 134 160 212


{-| A pale blue wash: the selected tab, a hovered row, the roll row in the log,
the locked note.
-}
tint : Color
tint =
    rgb255 230 236 251


{-| The chip behind the selected tool tab.
-}
selectedWash : Color
selectedWash =
    tint


facilitatorTint : Color
facilitatorTint =
    rgb255 122 51 0


danger : Color
danger =
    rgb255 158 0 0


{-| The Friction segment in the Guide's odds bars.
-}
dangerSoft : Color
dangerSoft =
    rgb255 220 143 143


{-| The Highlight half of an aspect's split button — the one green, kept for
the move that steps the die up.
-}
success : Color
success =
    rgb255 0 102 43


{-| A stable colour per speaker at the table. `0` is the facilitator; players
take `1`, `2`, `3` in the order they first appear in the log. Wraps defensively.
-}
speakerColor : Int -> Color
speakerColor index =
    case modBy 4 index of
        1 ->
            rgb255 10 58 140

        2 ->
            rgb255 0 102 43

        3 ->
            rgb255 107 31 107

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


{-| Every face here is self-hosted (`client/index.html`); the rest of each list
is the fallback if a file fails to load.
-}
sans : List Font.Font
sans =
    [ Font.typeface "Atkinson Hyperlegible"
    , Font.typeface "-apple-system"
    , Font.typeface "Segoe UI"
    , Font.typeface "Roboto"
    , Font.sansSerif
    ]


{-| Timestamps, die chips, odds labels.
-}
mono : List Font.Font
mono =
    [ Font.typeface "IBM Plex Mono"
    , Font.typeface "SF Mono"
    , Font.typeface "Menlo"
    , Font.typeface "Consolas"
    , Font.monospace
    ]


{-| The marks (☼ ☽ ↑ ↓). The Noto faces come first because Apple Symbols draws
☼ as a thin ring that reads as "empty". Each covers only the marks it is
declared for in `client/index.html`, and Atkinson Hyperlegible has none of
them, so the stack is safe on a label that mixes words and marks ("Alter ☼☼"):
the words fall through to Atkinson, and a mark whose Noto file failed to load
still finds Segoe UI Symbol or DejaVu Sans before the system fallback.
-}
glyph : Attribute msg
glyph =
    Font.family
        [ Font.typeface "Noto Sans Symbols 2"
        , Font.typeface "Noto Sans Symbols"
        , Font.typeface "Atkinson Hyperlegible"
        , Font.typeface "Segoe UI Symbol"
        , Font.typeface "DejaVu Sans"
        , Font.sansSerif
        ]


{-| A font size in pixels that need not be whole (12.5px tabs, 10.5px meta);
`Font.size` takes only an `Int`.
-}
fontSize : Float -> Attribute msg
fontSize px =
    Element.htmlAttribute (Html.Attributes.style "font-size" (String.fromFloat px ++ "px"))



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


{-| The width counterpart of `shrinkable` (`min-width: 0`): a `width fill` item
in a row may shrink below its content's natural width, so text inside it wraps
to the space it gets instead of pushing the row wider.
-}
shrinkableWidth : Attribute msg
shrinkableWidth =
    Element.htmlAttribute (Html.Attributes.style "min-width" "0")


{-| Hide horizontal overflow on a vertical scroll region. `Element.scrollbarY`
sets only `overflow-y: auto`, and CSS then computes `overflow-x` to `auto` as
well, so any sideways spill gets a permanent horizontal scrollbar. A spaced
`Element.wrappedRow` always spills: it lays out with negative margins that
reach half its spacing past the right edge (the Sheet's slot tabs, for one).
-}
clipX : Attribute msg
clipX =
    Element.htmlAttribute (Html.Attributes.style "overflow-x" "hidden")


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
        , clipX
        , shrinkable
        ]
        children


{-| A single line of text that ellipsises instead of wrapping when it is too long
for its slot — the strip's goal. It sits in a
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


{-| Let text break inside a long unbroken word (a URL, a run with no spaces), so
a value wraps inside its column rather than pushing past the edge.
-}
wrapAnywhere : Attribute msg
wrapAnywhere =
    Element.htmlAttribute (Html.Attributes.style "overflow-wrap" "anywhere")


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
        , Font.letterSpacing 0.7
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
        , el [ Font.size 10, Font.color inkSoft, Font.letterSpacing 0.6 ] (text (String.toUpper label))
        , rule
        ]


{-| The hairline between two of `page`'s columns.
-}
columnRule : Element msg
columnRule =
    el [ width (Element.px 1), height fill, Background.color line ] Element.none


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
        , paddingXY_ 12 4
        , Border.rounded 5
        , Element.mouseOver [ Background.color ink ]
        ]
        { onPress = config.onPress, label = text config.label }


{-| The status strip's roll button: the primary style a size up.
-}
rollButton : { onPress : Maybe msg, label : String } -> Element msg
rollButton config =
    Input.button
        [ Background.color accent
        , Font.color accentText
        , fontSize 12.5
        , Font.semiBold
        , paddingXY_ 12 5
        , Border.rounded 5
        , Element.mouseOver [ Background.color ink ]
        ]
        { onPress = config.onPress, label = text config.label }


{-| A small bordered square holding one glyph — the strip's `‹` `›`, the
Sheet's boon − / +. With no `onPress` it is muted and does not light up.
-}
squareButton :
    { onPress : Maybe msg
    , label : String
    , tip : String
    , width : Int
    , height : Int
    , radius : Int
    , size : Int
    }
    -> Element msg
squareButton config =
    Input.button
        ([ width (Element.px config.width)
         , height (Element.px config.height)
         , Background.color panel
         , Border.width 1
         , Border.color edge
         , Border.rounded config.radius
         , Font.size config.size
         , Element.htmlAttribute (Html.Attributes.title config.tip)
         ]
            ++ (case config.onPress of
                    Just _ ->
                        [ Font.color ink
                        , Element.mouseOver [ Border.color accent, Font.color accent ]
                        ]

                    Nothing ->
                        [ Font.color inkSoft ]
               )
        )
        { onPress = config.onPress
        , label = el [ Element.centerX, Element.centerY ] (text config.label)
        }


{-| A small toggle in a row of choices — the facilitator's ☼ BOON / ☽ BANE.
A mark and a word in `tone`; the selected one is filled with `tone`, the rest
are outlined and pick up `tone` on their border when hovered.
-}
pill : { selected : Bool, tone : Color, mark : String, label : String, tip : String, onPress : msg } -> Element msg
pill config =
    Input.button
        ([ Element.paddingXY 7 2
         , Border.rounded 4
         , Border.width 1
         , Font.size 10
         , Font.semiBold
         , Font.letterSpacing 0.7
         , Element.htmlAttribute (Html.Attributes.title config.tip)
         ]
            ++ (if config.selected then
                    [ Background.color config.tone, Border.color config.tone, Font.color accentText ]

                else
                    [ Border.color edge
                    , Font.color config.tone
                    , Element.mouseOver [ Border.color config.tone ]
                    ]
               )
        )
        { onPress = Just config.onPress
        , label =
            Element.row [ spacing 5 ]
                [ el [ glyph, Font.size 12 ] (text config.mark)
                , text (String.toUpper config.label)
                ]
        }


{-| An outlined label that presses nothing — the die while a roll is pending.
-}
chip : String -> String -> Element msg
chip tip label =
    el
        [ fontSize 12.5
        , Font.semiBold
        , Element.paddingXY 10 4
        , Border.width 1
        , Border.color edge
        , Border.rounded 5
        , Element.htmlAttribute (Html.Attributes.title tip)
        ]
        (text label)


{-| A bordered secondary button. With no `onPress` it is drawn muted and does
not light up on hover, so an unavailable control reads as one.
-}
ghostButton : { onPress : Maybe msg, label : String } -> Element msg
ghostButton =
    ghostButtonHovering accent


{-| A ghost button for a discarding action (Reject): it lights up in the
danger tone instead of the accent.
-}
dangerGhostButton : { onPress : Maybe msg, label : String } -> Element msg
dangerGhostButton =
    ghostButtonHovering danger


ghostButtonHovering : Color -> { onPress : Maybe msg, label : String } -> Element msg
ghostButtonHovering hover config =
    Input.button
        ([ Background.color panel
         , Font.size 12
         , paddingXY_ 10 4
         , Border.color edge
         , Border.width 1
         , Border.rounded 5
         ]
            ++ (case config.onPress of
                    Just _ ->
                        [ Font.color ink
                        , Element.mouseOver [ Border.color hover, Font.color hover ]
                        ]

                    Nothing ->
                        [ Font.color inkSoft ]
               )
        )
        { onPress = config.onPress, label = text config.label }


{-| A quiet text action for a row's own controls (undo, ×, ✎): no
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


{-| One tab in the tool strip: a character's sheet, the World or the Guide.
The selected one sits on the tint in a heavier weight; the rest are quiet until
hovered. `suffix` is a small trailing word inside the tab ("you" on the
viewer's own sheet), or `""` for none. `tip` (a native tooltip) says what the
tab holds.
-}
toolTab : { label : String, suffix : String, tip : String, selected : Bool, onPress : msg } -> Element msg
toolTab config =
    Input.button
        ([ Element.htmlAttribute (Html.Attributes.title config.tip)
         , Border.rounded 5
         , fontSize 12.5
         , paddingXY_ 9 4
         ]
            ++ (if config.selected then
                    [ Background.color selectedWash, Font.color ink, Font.semiBold ]

                else
                    [ Font.color inkSoft
                    , Element.mouseOver [ Background.color tint, Font.color ink ]
                    ]
               )
        )
        { onPress = Just config.onPress
        , label =
            if config.suffix == "" then
                text config.label

            else
                Element.row [ spacing xs ]
                    [ text config.label
                    , el [ fontSize 10.5, Font.regular ] (text config.suffix)
                    ]
        }


{-| The run of ☼ marks for `n` boons — a character's boons, a context boon —
in the accent.
-}
boonMarks : Int -> Element msg
boonMarks n =
    el [ glyph, Font.letterSpacing 2, Font.color accent ] (text (String.repeat (Basics.max 0 n) "☼"))


{-| The run of ☽ marks for `n` banes, in the danger tone so a boon and a bane
differ by more than shape.
-}
baneMarks : Int -> Element msg
baneMarks n =
    el [ glyph, Font.letterSpacing 2, Font.color danger ] (text (String.repeat (Basics.max 0 n) "☽"))


{-| A CSS class from `client/index.html`, for the few effects elm-ui cannot
express (the split button's gradients and hover labels).
-}
class : String -> Attribute msg
class name =
    Element.htmlAttribute (Html.Attributes.class name)


{-| The small ✎ that swaps a button for its text field.
-}
pencil : { onPress : Maybe msg, tip : String } -> Element msg
pencil config =
    withTip config.tip (linkButton { onPress = config.onPress, label = "✎" })


{-| One aspect, in the shape character aspects and context aspects share
(roadmap 32, Table v2): a bordered block with a small uppercase label (and
anything else on its meta row) over the statement.

`split`, when given, lays two halves over the whole block — the left
Complicates, the right Highlights on a character's aspect. Each half washes in
its colour from its outer edge on hover or press and shows its label at the
bottom (`client/index.html`, `.split-*`), so the pair reads by word as well as
by red / green; on touch, with no hover, both halves keep a faint resting tint.
A half with no `onPress` is off: no wash, no label, and `tip` says why. The
block's foot grows to make room for the labels.

`corner` (the ✎, or a context aspect's ✎ ×) sits in the top-right corner
above everything else. `press`, when given, makes the whole block one button
(Highlight Context on a context aspect), tinted on hover while it has an
`onPress`; the corner stays outside it, so its controls are not nested in
another button. `dashed` draws the border dashed (a consumed context aspect).
-}
aspectBlock :
    { meta : List (Element msg)
    , statement : Element msg
    , corner : Maybe (Element msg)
    , press : Maybe { onPress : Maybe msg, tip : String }
    , dashed : Bool
    , split :
        Maybe
            { left : { onPress : Maybe msg, label : String, tip : String }
            , right : { onPress : Maybe msg, label : String, tip : String }
            }
    }
    -> Element msg
aspectBlock config =
    let
        half side tone half_ =
            Input.button
                [ width fill
                , height fill
                , shrinkableWidth
                , Element.clip
                , class
                    ("split-half split-"
                        ++ side
                        ++ (case half_.onPress of
                                Just _ ->
                                    ""

                                Nothing ->
                                    " is-off"
                           )
                    )
                , Element.htmlAttribute (Html.Attributes.title half_.tip)
                ]
                { onPress = half_.onPress
                , label =
                    el
                        [ Element.alignBottom
                        , if side == "left" then
                            Element.alignLeft

                          else
                            Element.alignRight
                        , fontSize 10.5
                        , Font.semiBold
                        , Font.color tone
                        , glyph
                        , Element.paddingEach { top = 0, right = 10, bottom = 5, left = 10 }
                        , class "split-label"
                        ]
                        (text half_.label)
                }

        halves =
            case config.split of
                Just split ->
                    [ Element.inFront
                        (Element.row [ width fill, height fill ]
                            [ half "left" danger split.left, half "right" success split.right ]
                        )
                    ]

                Nothing ->
                    []

        corner =
            case config.corner of
                Just c ->
                    [ Element.inFront
                        (el [ Element.alignRight, Element.alignTop, Element.paddingEach { top = 5, right = 6, bottom = 0, left = 0 } ] c)
                    ]

                Nothing ->
                    []
        body =
            Element.column
                [ width fill
                , spacing 3
                , Element.paddingEach
                    { top = 8
                    , right = 11
                    , bottom =
                        if config.split == Nothing then
                            9

                        else
                            22
                    , left = 11
                    }
                ]
                [ Element.row [ width fill, spacing 5 ] config.meta
                , config.statement
                ]
    in
    el
        ([ width fill
         , Border.width 1
         , Border.color edge
         , Border.rounded 7
         , Element.clip
         ]
            ++ (if config.dashed then
                    [ Border.dashed ]

                else
                    [ Background.color panel ]
               )
            ++ halves
            ++ corner
        )
        (case config.press of
            Just button ->
                Input.button
                    ([ width fill
                     , Element.htmlAttribute (Html.Attributes.title button.tip)
                     ]
                        ++ (case button.onPress of
                                Just _ ->
                                    [ Element.mouseOver [ Background.color tint ] ]

                                Nothing ->
                                    [ Element.htmlAttribute (Html.Attributes.style "cursor" "default") ]
                           )
                    )
                    { onPress = button.onPress, label = body }

            Nothing ->
                body
        )


{-| An aspect or context statement: 15px, wrapping, at a reading line height.
-}
statement : List (Attribute msg) -> String -> Element msg
statement attrs content =
    Element.paragraph
        ([ width fill
         , Font.size 15
         , Element.htmlAttribute (Html.Attributes.style "line-height" "1.35")
         , wrapAnywhere
         ]
            ++ attrs
        )
        [ text content ]


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


{-| `onEnter` for a multiline field holding one statement: Enter (without
Shift) fires `msg` and is swallowed, so it neither inserts a line break nor
leaves one behind to land in the field after the submit cleared it.
-}
onEnterSubmit : msg -> Attribute msg
onEnterSubmit msg =
    Element.htmlAttribute
        (Html.Events.preventDefaultOn "keydown"
            (Decode.map2 Tuple.pair
                (Decode.field "key" Decode.string)
                (Decode.field "shiftKey" Decode.bool)
                |> Decode.andThen
                    (\( key, shift ) ->
                        if key == "Enter" && not shift then
                            Decode.succeed ( msg, True )

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
