module View.Characters exposing (view)

{-| The Sheet tool (roadmap section 27): a strip of character slots over the
selected sheet — owner row, boons (facilitator Grant only, for now — see
`boonsBlock`), and the fields, each a label and a hairline input. An aspect
shows the Banes it has accumulated as `−` marks at its end.
-}

import Copy
import Element exposing (Element, el, fill, height, px, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Format
import Html.Attributes
import Types exposing (..)
import Ui
import View.Helpers
    exposing
        ( ViewContext
        , characterLabel
        , inlineInputAttrs
        , inputAttrs
        , placeholder
        , tipAttrs
        )


type alias Props =
    { selectedSlot : Int
    , aspectExamplesOpen : Maybe ( Int, Aspect )
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
    Ui.flat
        [ tabStrip ctx.myId props.selectedSlot gs.characters
        , case selected of
            Just ch ->
                characterSheet ctx.facilitator ctx.myId props.aspectExamplesOpen ch

            Nothing ->
                placeholder Copy.noCharacterSheets
        ]


{-| One tab per sheet, labelled by character name (or a slot number until one is
set) with a "(you)" marker on the sheet the viewer holds.
-}
tabStrip : Maybe String -> Int -> List CharacterSheet -> Element Msg
tabStrip myId selectedSlot characters =
    Element.wrappedRow [ spacing Ui.xs, width fill ]
        (List.map
            (\c -> Ui.tab (c.slot == selectedSlot) (tabLabel myId c) (SelectSlot c.slot))
            characters
        )


tabLabel : Maybe String -> CharacterSheet -> String
tabLabel myId ch =
    if ch.ownerId /= Nothing && ch.ownerId == myId then
        characterLabel ch ++ Copy.youMarker

    else
        characterLabel ch


characterSheet : Bool -> Maybe String -> Maybe ( Int, Aspect ) -> CharacterSheet -> Element Msg
characterSheet facilitator myId aspectExamplesOpen ch =
    let
        mine =
            ch.ownerId /= Nothing && ch.ownerId == myId

        editable =
            facilitator || mine || ch.ownerId == Nothing
    in
    Element.column [ spacing Ui.xs, width fill ]
        [ ownerRow facilitator mine ch
        , boonsBlock facilitator ch
        , field editable ch NameField "" "Name" ch.name
        , field editable ch NotableFeaturesField "" Copy.notableFeaturesLabel ch.notableFeatures
        , aspectField editable aspectExamplesOpen ch Archetype ArchetypeField ch.archetype
        , aspectField editable aspectExamplesOpen ch Desire DesireField ch.desire
        , aspectField editable aspectExamplesOpen ch Quest QuestField ch.quest
        , field editable ch ConditionField "Condition" Copy.conditionLabel ch.condition
        , notesField editable ch
        ]


{-| An aspect field: the input, its accumulated Banes as `−` marks at the end
of the row, and — while the sheet is editable — a "see examples" toggle that
opens a short list of sample aspects from `ASPECTS.md` to write against.
-}
aspectField : Bool -> Maybe ( Int, Aspect ) -> CharacterSheet -> Aspect -> CharacterField -> String -> Element Msg
aspectField editable examplesOpen ch aspect fieldTag value =
    let
        count =
            aspectBaneCount aspect ch.aspectBanes

        banes =
            if count > 0 then
                [ el
                    [ Element.centerY
                    , Font.size 12
                    , Element.htmlAttribute
                        (Html.Attributes.title (String.fromInt count ++ " " ++ Format.pluralize count Copy.baneStone ++ " on this aspect"))
                    ]
                    (Ui.baneMarks count)
                ]

            else
                []
    in
    Element.column [ spacing Ui.xs, width fill ]
        (Element.row [ width fill, spacing Ui.xs ]
            (field editable ch fieldTag (aspectLabel aspect) (aspectLabel aspect) value :: banes)
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


{-| Who holds this sheet, and the claim / release control. Players claim an
unclaimed sheet; the owner (or facilitator) can release it.
-}
ownerRow : Bool -> Bool -> CharacterSheet -> Element Msg
ownerRow facilitator mine ch =
    let
        ( label, action ) =
            if mine then
                ( Copy.ownerMine
                , Just (Ui.ghostButton { onPress = Just (ReleaseSlot ch.slot), label = Copy.ownerRelease })
                )

            else if ch.ownerId == Nothing then
                ( Copy.ownerUnclaimed
                , if facilitator then
                    Nothing

                  else
                    Just (Ui.ghostButton { onPress = Just (ClaimSlot ch.slot), label = Copy.ownerClaim })
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
-}
field : Bool -> CharacterSheet -> CharacterField -> String -> String -> String -> Element Msg
field editable ch fieldTag tipKey label value =
    if editable then
        Input.text
            (inlineInputAttrs ++ tipAttrs tipKey ++ [ width fill, Ui.onBlur (CharacterFieldBlur ch.slot) ])
            { onChange = CharacterFieldInput ch.slot fieldTag
            , text = value
            , placeholder = Nothing
            , label = fieldLabel label
            }

    else
        readOnlyField tipKey label value


notesField : Bool -> CharacterSheet -> Element Msg
notesField editable ch =
    if editable then
        Input.multiline
            (inputAttrs ++ [ height (px 64), width fill, Ui.onBlur (CharacterFieldBlur ch.slot) ])
            { onChange = CharacterFieldInput ch.slot NotesField
            , text = ch.notes
            , placeholder = Nothing
            , label = fieldLabel "Notes"
            , spellcheck = False
            }

    else
        readOnlyField "" "Notes" ch.notes


readOnlyField : String -> String -> String -> Element msg
readOnlyField tipKey label value =
    Element.row (spacing Ui.xs :: width fill :: tipAttrs tipKey)
        [ el [ width (px labelWidth), Element.alignTop, Font.size 10, Font.color Ui.inkSoft, Font.letterSpacing 0.5 ]
            (text (String.toUpper label))
        , Element.paragraph
            [ Font.size 13, Element.paddingXY 4 2, Font.color Ui.inkSoft ]
            [ text
                (if String.trim value == "" then
                    "—"

                 else
                    value
                )
            ]
        ]


{-| A character's boons, at the top of the sheet where a player can see what
they can spend on a move, as a run of `+` marks. Only the facilitator gets a
control here (Grant `+` / `−`); a player moves their own boons through the moves
in the Moves tool.
-}
boonsBlock : Bool -> CharacterSheet -> Element Msg
boonsBlock facilitator ch =
    Element.row [ width fill, spacing Ui.xs, Element.centerY ]
        (el [ width (px labelWidth), Font.size 10, Font.color Ui.inkSoft, Font.letterSpacing 0.5 ]
            (text (String.toUpper Copy.boonsLabel))
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


fieldLabel : String -> Input.Label msg
fieldLabel label =
    Input.labelLeft [ width (px labelWidth), Element.centerY, Font.size 10, Font.color Ui.inkSoft, Font.letterSpacing 0.5 ]
        (text (String.toUpper label))
