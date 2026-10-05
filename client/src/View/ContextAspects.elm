module View.ContextAspects exposing (createField, header, view)

{-| The context boons and banes (the middle column): what the table has
established as true. Each is a block in the shape the character aspects take
(roadmap 32.5, Table v2), and the whole block is a button — pressing it is the
Highlight Context move, open to anyone before the junction is rolled: a boon
steps the die up, a bane steps it down, and it is marked **consumed** (dashed
and struck through, no longer pressable) rather than removed. A Complicate's
bane arrives blank, naming the aspect it came from, for the facilitator to
word.

The facilitator's ✎ swaps a block's statement for its text field (saved, and
swapped back, when the field loses focus) and × removes it. `createField` is
the box at the foot of the list: Create for a player (a boon for a context
boon in their words), or, for the facilitator, a free context boon or bane
with a ☼ BOON / ☽ BANE choice.
-}

import Action exposing (Action(..))
import Aspect
import ContextAspect exposing (ContextAspect, Polarity(..))
import Copy
import Dict exposing (Dict)
import Die
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Attributes
import MoveRecord
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, characterLabel, contextAspectFieldId, placeholder)


type alias Props =
    { facilitatorDraft : String
    , facilitatorKind : Polarity
    , createDraft : String
    , edits : Dict String String
    }


{-| What a Create costs, in boons (RULES.md "Moves"); the Worker checks it too.
-}
createCost : Int
createCost =
    1


{-| The column's header: its title, and how many aspects are open and
consumed.
-}
header : GameState -> Element msg
header gs =
    let
        consumed =
            List.length (List.filter .consumed gs.contextAspects)
    in
    Element.row
        [ width fill
        , Element.height (Element.px 36)
        , Element.paddingXY 14 0
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        [ el [ Element.centerY ] (Ui.sectionTitle Copy.contextTabLabel)
        , el [ Element.alignRight, Element.centerY, Font.size 11, Font.color Ui.inkSoft ]
            (text (Copy.contextCount (List.length gs.contextAspects - consumed) consumed))
        ]


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.contextAspects then
        placeholder Copy.noContextAspects

    else
        Element.column [ spacing 7, width fill ] (List.map (block ctx props.edits gs) gs.contextAspects)


{-| One context aspect. Open, it is a solid block and its Highlight Context
button; consumed, a dashed one with its statement struck through. The
facilitator's ✎ and × sit in the corner, outside the button.
-}
block : ViewContext -> Dict String String -> GameState -> ContextAspect -> Element Msg
block ctx edits gs a =
    let
        draft =
            if ctx.facilitator then
                Dict.get a.id edits

            else
                Nothing

        ( tone, mark, kind ) =
            case a.polarity of
                Boon ->
                    ( Ui.accent, "☼", Copy.boonLabel )

                Bane ->
                    ( Ui.danger, "☽", Copy.baneLabel )

        metaTone =
            if a.consumed then
                Ui.inkSoft

            else
                tone

        right =
            if a.consumed then
                Copy.contextAspectConsumed

            else
                origin gs a

        controls =
            if not ctx.facilitator then
                Nothing

            else
                Just
                    (Element.row [ spacing 6, Font.size 12 ]
                        (Ui.onlyWhen (not a.consumed && draft == Nothing)
                            [ Ui.pencil { onPress = Just (EditContextAspect a.id), tip = Copy.editTip } ]
                            ++ [ Ui.withTip Copy.contextAspectRemove
                                    (Input.button
                                        [ Font.color Ui.inkSoft, Element.mouseOver [ Font.color Ui.danger ] ]
                                        { onPress = Ui.press ctx.inflight (DeletingContextAspect a.id) (DeleteContextAspect a.id)
                                        , label = text "×"
                                        }
                                    )
                               ]
                        )
                    )

        -- Room on the meta row for the corner's controls, which float above it.
        controlsRoom =
            case ( controls, a.consumed || draft /= Nothing ) of
                ( Nothing, _ ) ->
                    []

                ( Just _, True ) ->
                    [ el [ width (Element.px 12) ] none ]

                ( Just _, False ) ->
                    [ el [ width (Element.px 30) ] none ]

        meta =
            [ el [ width (Element.px 13), Ui.glyph, Font.size 13, Font.color metaTone ] (text mark)
            , el [ Font.size 10, Font.semiBold, Font.letterSpacing 0.7, Font.color metaTone ] (text (String.toUpper kind))
            , el
                [ Element.alignRight
                , Ui.fontSize 10.5
                , Font.color Ui.inkSoft
                , Element.htmlAttribute (Html.Attributes.style "white-space" "nowrap")
                ]
                (text right)
            ]
                ++ controlsRoom

        statement =
            case draft of
                Just d ->
                    Input.multiline
                        [ width fill
                        , Element.padding 0
                        , Border.width 0
                        , Background.color (Element.rgba255 0 0 0 0)
                        , Element.focused []
                        , Font.size 15
                        , Ui.onBlur (SaveContextAspectText a.id)
                        , Ui.onEnterSubmit (SaveContextAspectText a.id)
                        , Element.htmlAttribute (Html.Attributes.id (contextAspectFieldId a.id))
                        ]
                        { onChange = String.replace "\n" " " >> ContextAspectTextChanged a.id
                        , text = d
                        , placeholder = Just (Input.placeholder [] (text Copy.contextAspectWordingPlaceholder))
                        , label = Input.labelHidden "Context boon or bane text"
                        , spellcheck = True
                        }

                Nothing ->
                    if String.trim a.text == "" then
                        Ui.statement [ Font.italic, Font.color Ui.inkSoft ] (unworded gs a)

                    else if a.consumed then
                        Ui.statement [ Font.strike, Font.color Ui.inkSoft ] a.text

                    else
                        Ui.statement [] a.text
    in
    Ui.aspectBlock
        { meta = meta
        , statement = statement
        , corner = controls
        , press =
            case draft of
                Just _ ->
                    Nothing

                Nothing ->
                    Just (highlightContext ctx gs a)
        , dashed = a.consumed
        , split = Nothing
        }


{-| Where an aspect came from, at the right of its meta row: the character
and aspect a Complicate's bane was drawn from, otherwise who added it.
-}
origin : GameState -> ContextAspect -> String
origin gs a =
    case a.fromAspect of
        Just ( slot, _ ) ->
            case characterAtSlot slot gs.characters of
                Just ch ->
                    Copy.complicateOrigin (characterLabel ch)

                Nothing ->
                    a.createdByName

        Nothing ->
            a.createdByName


{-| The block's Highlight Context press: off once consumed, while a roll is
pending, or at the end of the ladder its polarity pushes toward; the tooltip
says which.
-}
highlightContext : ViewContext -> GameState -> ContextAspect -> { onPress : Maybe Msg, tip : String }
highlightContext ctx gs a =
    let
        direction =
            case a.polarity of
                Boon ->
                    Die.Up

                Bane ->
                    Die.Down
    in
    if a.consumed then
        { onPress = Nothing, tip = Copy.contextAspectConsumedTip }

    else if gs.junction /= Nothing then
        { onPress = Nothing, tip = Copy.movesLocked }

    else if Die.step direction gs.die == Nothing then
        { onPress = Nothing, tip = Copy.dieAtEnd }

    else
        { onPress = Ui.press ctx.inflight (MakingMove MoveRecord.HighlightContext) (MakeHighlightContext a.id)
        , tip = Copy.highlightContextTip a.polarity
        }


{-| A blank bane from a Complicate, named by the character and aspect it came
from until the facilitator words it.
-}
unworded : GameState -> ContextAspect -> String
unworded gs a =
    case a.fromAspect of
        Just ( slot, aspect ) ->
            Copy.unwordedFrom
                (characterAtSlot slot gs.characters |> Maybe.map characterLabel |> Maybe.withDefault "")
                (Aspect.label aspect)

        Nothing ->
            Copy.unworded


{-| The box pinned at the foot of the list, dashed like an aspect waiting to
be written. For a player it is Create: a boon for a context boon in their
words (blank is recorded as a detail from them). For the facilitator it adds
a context boon or bane directly, free. Enter submits; a line break never lands
in the text, since an aspect is one statement.
-}
createField : ViewContext -> Props -> GameState -> Element Msg
createField ctx props gs =
    Element.el
        [ width fill
        , Element.paddingEach { top = 10, right = 14, bottom = 12, left = 14 }
        , Border.widthEach { top = 1, right = 0, bottom = 0, left = 0 }
        , Border.color Ui.line
        ]
        (Element.column
            [ width fill
            , spacing Ui.xs
            , Element.paddingXY 11 8
            , Border.width 1
            , Border.dashed
            , Border.color Ui.edge
            , Border.rounded 7
            , Background.color Ui.panel
            ]
            (if ctx.facilitator then
                facilitatorAdd ctx.inflight props.facilitatorDraft props.facilitatorKind

             else
                playerCreate ctx props.createDraft gs
            )
        )


{-| The box's text area: three lines at statement size, no chrome.
-}
entryText : { draft : String, onChange : String -> Msg, submit : Maybe Msg, placeholder : String, label : String } -> Element Msg
entryText config =
    Input.multiline
        ([ width fill
         , Element.height (Element.px 60)
         , Element.padding 0
         , Border.width 0
         , Background.color (Element.rgba255 0 0 0 0)
         , Element.focused []
         , Font.size 15
         ]
            ++ (case config.submit of
                    Just msg ->
                        [ Ui.onEnterSubmit msg ]

                    Nothing ->
                        []
               )
        )
        { onChange = String.replace "\n" " " >> config.onChange
        , text = config.draft
        , placeholder = Just (Input.placeholder [ Font.color Ui.inkSoft ] (text config.placeholder))
        , label = Input.labelHidden config.label
        , spellcheck = True
        }


{-| A meta-row note at the right of the box ("costs ☼", "free").
-}
costNote : String -> Element msg
costNote note =
    el [ Element.alignRight, Element.centerY, Ui.fontSize 10.5, Font.color Ui.inkSoft, Ui.glyph ] (text note)


playerCreate : ViewContext -> String -> GameState -> List (Element Msg)
playerCreate ctx draft gs =
    let
        mine =
            gs.characters |> List.filter (\c -> c.ownerId /= Nothing && c.ownerId == ctx.myId) |> List.head

        reason =
            case mine of
                Nothing ->
                    Just Copy.claimASheetForMoves

                Just ch ->
                    if gs.junction /= Nothing then
                        Just Copy.movesLocked

                    else if ch.fate < createCost then
                        Just Copy.needsABoon

                    else
                        Nothing

        onPress =
            case reason of
                Nothing ->
                    Ui.press ctx.inflight (MakingMove MoveRecord.Create) MakeCreate

                Just _ ->
                    Nothing
    in
    [ Element.row [ width fill, spacing 5 ]
        [ el [ Ui.glyph, Font.size 13, Font.color Ui.accent ] (text "☼")
        , el [ Font.size 10, Font.semiBold, Font.letterSpacing 0.7, Font.color Ui.accent ] (text (String.toUpper Copy.createButton))
        , costNote Copy.createCostNote
        ]
    , entryText
        { draft = draft
        , onChange = CreateDraftChanged
        , submit = onPress
        , placeholder = Copy.createPlaceholder
        , label = Copy.createButton
        }
    , el
        ([ Element.alignRight ]
            ++ (if onPress == Nothing then
                    [ Element.alpha 0.4 ]

                else
                    []
               )
        )
        (Ui.withTip (Maybe.withDefault Copy.createTip reason)
            (Ui.primaryButton { onPress = onPress, label = Copy.createButton })
        )
    ]


facilitatorAdd : List Action -> String -> Polarity -> List (Element Msg)
facilitatorAdd inflight draft kind =
    let
        choice polarity tone mark label tip =
            Ui.pill
                { selected = kind == polarity
                , tone = tone
                , mark = mark
                , label = label
                , tip = tip
                , onPress = ContextAspectKindChanged polarity
                }

        addMsg =
            if String.trim draft /= "" then
                Ui.press inflight AddingContextAspect AddContextAspect

            else
                Nothing
    in
    [ Element.row [ width fill, spacing Ui.xs ]
        [ choice Boon Ui.accent "☼" Copy.boonLabel Copy.contextBoonToggleTip
        , choice Bane Ui.danger "☽" Copy.baneLabel Copy.contextBaneToggleTip
        , costNote Copy.addCostNote
        ]
    , entryText
        { draft = draft
        , onChange = ContextAspectDraftChanged
        , submit = addMsg
        , placeholder = Copy.addContextAspectPlaceholder
        , label = "New context boon or bane"
        }
    , el [ Element.alignRight ] (Ui.primaryButton { onPress = addMsg, label = Copy.addContextAspect })
    ]
