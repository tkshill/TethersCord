module View.Characters exposing (view)

{-| A character's sheet, picked from the tool strip (roadmap 32.2) — owner row, boons (as ☼ marks; the facilitator's Grant beside
them), and the fields, each a label and a hairline input.

On the viewer's own sheet each written aspect is a split button (31.5): the
left half Complicates, the right half Highlights, each greyed with its reason
when it cannot be made. A small ✎ beside it swaps in the text field; leaving
the field saves it and swaps the button back. On any other sheet an aspect is a
field like the rest. An aspect shows the Banes it accumulated before 23.1 as ☽
marks at its end.
-}

import Action exposing (Action(..))
import Aspect exposing (Aspect(..))
import Copy
import Element exposing (Element, el, fill, height, px, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Format
import Die
import Html.Attributes
import MoveRecord
import Types exposing (..)
import Ui
import View.Helpers
    exposing
        ( ViewContext
        , aspectFieldId
        , characterLabel
        , inlineInputAttrs
        , inputAttrs
        , placeholder
        , tipAttrs
        )


type alias Props =
    { selectedSlot : Int
    , aspectExamplesOpen : Maybe ( Int, Aspect )
    , aspectEditing : Maybe ( Int, Aspect )
    }


{-| Width of the label column, so every field's value starts at the same x.
-}
labelWidth : Int
labelWidth =
    104


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    let
        selected =
            case List.filter (\c -> c.slot == props.selectedSlot) gs.characters of
                first :: _ ->
                    Just first

                [] ->
                    List.head gs.characters
    in
    case selected of
        Just ch ->
            characterSheet ctx props gs ch

        Nothing ->
            placeholder Copy.noCharacterSheets


characterSheet : ViewContext -> Props -> GameState -> CharacterSheet -> Element Msg
characterSheet ctx props gs ch =
    let
        facilitator =
            ctx.facilitator

        mine =
            ch.ownerId /= Nothing && ch.ownerId == ctx.myId

        editable =
            facilitator || mine || ch.ownerId == Nothing

        aspectField aspect fieldTag value =
            if mine && props.aspectEditing /= Just ( ch.slot, aspect ) && String.trim value /= "" then
                aspectMoves ctx gs ch aspect value

            else
                aspectInput editable props.aspectExamplesOpen ch aspect fieldTag value
    in
    Element.column [ spacing Ui.md, width fill ]
        [ ownerRow mine ch
        , boonsBlock facilitator ch
        , field editable ch NameField "" "Name" ch.name
        , field editable ch NotableFeaturesField "" Copy.notableFeaturesLabel ch.notableFeatures
        , aspectField Archetype ArchetypeField ch.archetype
        , aspectField Desire DesireField ch.desire
        , aspectField Quest QuestField ch.quest
        , field editable ch ConditionField "Condition" Copy.conditionLabel ch.condition
        , notesField editable ch
        ]


{-| A written aspect on the viewer's own sheet: the split button (Complicate on
the left, Highlight on the right) and its ✎, under the aspect's label.
-}
aspectMoves : ViewContext -> GameState -> CharacterSheet -> Aspect -> String -> Element Msg
aspectMoves ctx gs ch aspect value =
    let
        lockedOr ok =
            if gs.junction /= Nothing then
                Err Copy.movesLocked

            else
                ok

        highlight =
            lockedOr
                (if ch.fate < highlightCost then
                    Err Copy.needsABoon

                 else if Die.stepUp gs.die == Nothing then
                    Err Copy.dieAtTop

                 else
                    Ok (MakeHighlight aspect)
                )

        complicate =
            lockedOr (Ok (MakeComplicate aspect))

        half label okTip kind outcome =
            case outcome of
                Ok msg ->
                    { onPress = Ui.press ctx.inflight (MakingMove kind) msg, label = label, tip = okTip }

                Err reason ->
                    { onPress = Nothing, label = label, tip = reason }
    in
    labelled (Aspect.label aspect)
        (Element.row [ width fill, Ui.shrinkableWidth, spacing Ui.xs ]
            [ Ui.splitButton
                { content = value
                , left = half Copy.complicateHalf Copy.complicateTip MoveRecord.Complicate complicate
                , right = half Copy.highlightHalf Copy.highlightTip MoveRecord.Highlight highlight
                }
            , el [ Element.alignTop ] (Ui.pencil { onPress = Just (EditAspect ch.slot aspect), tip = Copy.editTip })
            ]
        )


{-| What a Highlight costs, in boons (RULES.md "Moves"); the Worker checks it too.
-}
highlightCost : Int
highlightCost =
    1


{-| An aspect field: the input, its accumulated Banes as ☽ marks at the end
of the row, and — while the sheet is editable — a "see examples" toggle that
opens a short list of sample aspects from `ASPECTS.md` to write against.
-}
aspectInput : Bool -> Maybe ( Int, Aspect ) -> CharacterSheet -> Aspect -> CharacterField -> String -> Element Msg
aspectInput editable examplesOpen ch aspect fieldTag value =
    let
        count =
            aspectBaneCount aspect ch.aspectBanes

        banes =
            if count > 0 then
                [ el
                    [ Element.centerY
                    , Font.size 12
                    , Element.htmlAttribute
                        (Html.Attributes.title (String.fromInt count ++ " " ++ Format.pluralize count Copy.baneLabel ++ " on this aspect"))
                    ]
                    (Ui.baneMarks count)
                ]

            else
                []
    in
    Element.column [ spacing Ui.xs, width fill ]
        (Element.row [ width fill, spacing Ui.xs ]
            (fieldWithId (Just (aspectFieldId ch.slot aspect)) editable ch fieldTag (Aspect.label aspect) (Aspect.label aspect) value :: banes)
            :: aspectExamplesBlock editable examplesOpen ch.slot aspect
        )


{-| The "see examples" affordance under an aspect field. Nothing on a read-only
sheet; a toggle link otherwise, expanding an indented bulleted list when this is
the open one.
-}
aspectExamplesBlock : Bool -> Maybe ( Int, Aspect ) -> Int -> Aspect -> List (Element Msg)
aspectExamplesBlock editable examplesOpen slot aspect =
    if not editable then
        []

    else
        let
            open =
                examplesOpen == Just ( slot, aspect )
        in
        el [ Element.paddingEach { top = 0, right = 0, bottom = 0, left = labelWidth + 4 } ]
            (Ui.linkButton
                { onPress = Just (ToggleAspectExamples slot aspect)
                , label =
                    if open then
                        Copy.aspectExamplesHideLabel

                    else
                        Copy.aspectExamplesLabel
                }
            )
            :: (if open then
                    [ Element.column
                        [ spacing Ui.xs
                        , Element.paddingEach { top = Ui.xs, right = 0, bottom = Ui.xs, left = labelWidth + 4 + Ui.sm }
                        ]
                        (List.map exampleRow (Copy.aspectExamples aspect))
                    ]

                else
                    []
               )


exampleRow : String -> Element Msg
exampleRow example =
    Element.paragraph [ Font.size 12, Font.color Ui.inkSoft, spacing 2 ]
        [ text ("· " ++ example) ]


{-| Who holds this sheet, and the claim / release control. Anyone, the
facilitator included, can claim an unclaimed sheet; the owner can release it.
-}
ownerRow : Bool -> CharacterSheet -> Element Msg
ownerRow mine ch =
    let
        ( label, action ) =
            if mine then
                ( Copy.ownerMine
                , Just (Ui.ghostButton { onPress = Just (ReleaseSlot ch.slot), label = Copy.ownerRelease })
                )

            else if ch.ownerId == Nothing then
                ( Copy.ownerUnclaimed
                , Just (Ui.ghostButton { onPress = Just (ClaimSlot ch.slot), label = Copy.ownerClaim })
                )

            else
                ( Copy.ownerClaimed, Nothing )
    in
    Element.row [ width fill, spacing Ui.sm, Element.centerY ]
        (el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
            :: (case action of
                    Just btn ->
                        [ el [ Element.alignRight ] btn ]

                    Nothing ->
                        []
               )
        )


{-| A labelled sheet field. `tipKey` names the glossary term whose gloss shows as
a native tooltip over the field; `""` for a field that is not game vocabulary
("Name", "Notes").

It is a one-line value, but drawn as a multiline input so a long entry wraps and
the field grows to show it instead of running past the column's edge. A line
break (Enter, or a paste) becomes a space, so the value stays one line.
-}
field : Bool -> CharacterSheet -> CharacterField -> String -> String -> String -> Element Msg
field =
    fieldWithId Nothing


{-| `field`, with a DOM id on the input so ✎ can focus it.
-}
fieldWithId : Maybe String -> Bool -> CharacterSheet -> CharacterField -> String -> String -> String -> Element Msg
fieldWithId domId editable ch fieldTag tipKey label value =
    if editable then
        labelled label
            (Input.multiline
                (inlineInputAttrs
                    ++ tipAttrs tipKey
                    ++ [ width fill, Ui.onBlur (CharacterFieldBlur ch.slot) ]
                    ++ (case domId of
                            Just id ->
                                [ Element.htmlAttribute (Html.Attributes.id id) ]

                            Nothing ->
                                []
                       )
                )
                { onChange = String.replace "\n" " " >> CharacterFieldInput ch.slot fieldTag
                , text = value
                , placeholder = Nothing
                , label = Input.labelHidden label
                , spellcheck = True
                }
            )

    else
        readOnlyField tipKey label value


notesField : Bool -> CharacterSheet -> Element Msg
notesField editable ch =
    if editable then
        labelled "Notes"
            (Input.multiline
                (inputAttrs ++ [ height (px 64), width fill, Ui.onBlur (CharacterFieldBlur ch.slot) ])
                { onChange = CharacterFieldInput ch.slot NotesField
                , text = ch.notes
                , placeholder = Nothing
                , label = Input.labelHidden "Notes"
                , spellcheck = False
                }
            )

    else
        readOnlyField "" "Notes" ch.notes


{-| The label column beside an editable field. Not `Input.labelLeft`: that puts
the input in a flex row where elm-ui's multiline wrapper takes `flex-basis:
auto`, so it sizes to its text on one line and pushes past the column instead
of wrapping. Here the input sits in a slot that may shrink to the space left.
-}
labelled : String -> Element Msg -> Element Msg
labelled label input =
    Element.row [ width fill, Ui.shrinkableWidth, spacing Ui.xs ]
        [ el (Element.alignTop :: Element.paddingXY 0 4 :: labelStyle) (text (String.toUpper label))
        , el [ width fill, Ui.shrinkableWidth ] input
        ]


labelStyle : List (Element.Attribute msg)
labelStyle =
    [ width (px labelWidth), Font.size 10, Font.color Ui.inkSoft, Font.letterSpacing 0.5 ]


readOnlyField : String -> String -> String -> Element msg
readOnlyField tipKey label value =
    Element.row (spacing Ui.xs :: width fill :: Ui.shrinkableWidth :: tipAttrs tipKey)
        [ el (Element.alignTop :: labelStyle) (text (String.toUpper label))
        , Element.paragraph
            [ width fill, Ui.wrapAnywhere, Font.size 13, Element.paddingXY 4 2, Font.color Ui.inkSoft ]
            [ text
                (if String.trim value == "" then
                    "—"

                 else
                    value
                )
            ]
        ]


{-| A character's boons, at the top of the sheet where a player can see what
they can spend on a move, as a run of ☼ marks. Only the facilitator gets a
control here (Grant `+` / `−`); a player spends and earns boons through the
moves on their aspects.
-}
boonsBlock : Bool -> CharacterSheet -> Element Msg
boonsBlock facilitator ch =
    Element.row [ width fill, spacing Ui.xs, Element.centerY ]
        (el labelStyle (text (String.toUpper Copy.boonsLabel))
            :: (if ch.fate <= 0 then
                    el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.boonsNone)

                else
                    el [ Font.size 14 ] (Ui.boonMarks ch.fate)
               )
            :: grantControls facilitator ch
        )


grantControls : Bool -> CharacterSheet -> List (Element Msg)
grantControls facilitator ch =
    if facilitator then
        [ Element.row [ Element.alignRight, spacing Ui.xs ]
            [ el [ Font.size 10, Font.color Ui.inkSoft ] (text Copy.grant)
            , Ui.ghostButton { onPress = Just (FateDecrement ch.slot), label = "−" }
            , Ui.ghostButton { onPress = Just (FateIncrement ch.slot), label = "+" }
            ]
        ]

    else
        []
