module View.Characters exposing (view)

{-| The Characters card: a tab strip over the three sheets and the selected
sheet itself — owner row, boons (grant / highlight), the text fields, and the
three aspects with their accumulated Banes or an untethered flag.
-}

import Copy
import Element exposing (Element, el, fill, height, none, padding, px, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Format
import Kind
import Types exposing (..)
import Ui
import View.Helpers
    exposing
        ( ViewContext
        , characterLabel
        , countProposals
        , inputAttrs
        , latestProposalId
        , pendingHint
        , placeholder
        )


type alias Props =
    { selectedSlot : Int }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    Ui.card
        [ Ui.sectionTitle Copy.charactersTitle
        , let
            selected =
                case List.filter (\c -> c.slot == props.selectedSlot) gs.characters of
                    first :: _ ->
                        Just first

                    [] ->
                        List.head gs.characters
          in
          Element.column [ spacing Ui.md, width fill ]
            [ tabStrip ctx.myId props.selectedSlot gs.characters
            , case selected of
                Just ch ->
                    characterSheet ctx.facilitator ctx.myId gs ch

                Nothing ->
                    placeholder Copy.noCharacterSheets
            ]
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


characterSheet : Bool -> Maybe String -> GameState -> CharacterSheet -> Element Msg
characterSheet facilitator myId gs ch =
    let
        mine =
            ch.ownerId /= Nothing && ch.ownerId == myId

        editable =
            facilitator || mine || ch.ownerId == Nothing

        pendingPledges =
            if mine then
                countProposals myId Kind.Pledge gs.proposals

            else
                0

        pendingPledgeId =
            if mine then
                latestProposalId myId Kind.Pledge gs.proposals

            else
                Nothing
    in
    Element.column
        [ spacing Ui.sm
        , padding Ui.md
        , width fill
        , Border.color Ui.line
        , Border.width 1
        , Border.rounded 6
        ]
        [ ownerRow facilitator mine ch
        , boonsBlock facilitator mine ch (committedBoonsForSlot ch.slot gs.committedBoons) pendingPledges pendingPledgeId
        , field editable ch NameField "Name" ch.name
        , field editable ch NotableFeaturesField Copy.notableFeaturesLabel ch.notableFeatures
        , aspectField editable ch gs.untether Archetype ArchetypeField ch.archetype
        , aspectField editable ch gs.untether Desire DesireField ch.desire
        , aspectField editable ch gs.untether Quest QuestField ch.quest
        , field editable ch ConditionField Copy.conditionLabel ch.condition
        , notesField editable ch
        ]


{-| An aspect field with its accumulated Banes shown as dots beneath it, or an
"untethered" flag when this is the aspect a failed session goal broke
(section 19).
-}
aspectField : Bool -> CharacterSheet -> Maybe Untether -> Aspect -> CharacterField -> String -> Element Msg
aspectField editable ch untether aspect fieldTag value =
    let
        count =
            aspectBaneCount aspect ch.aspectBanes

        broken =
            case untether of
                Just u ->
                    u.slot == ch.slot && u.aspect == aspect

                Nothing ->
                    False

        extras =
            if broken then
                [ el [ Font.size 10, Font.color Ui.danger, Font.semiBold ]
                    (text Copy.untetheredAspectFlag)
                ]

            else if count > 0 then
                [ Element.row [ spacing Ui.xs, Element.centerY ]
                    (List.repeat count Ui.baneDot
                        ++ [ el [ Font.size 10, Font.color Ui.inkSoft ]
                                (text (String.fromInt count ++ " " ++ Format.pluralize count Copy.baneStone))
                           ]
                    )
                ]

            else
                []
    in
    Element.column [ spacing Ui.xs, width fill ]
        (field editable ch fieldTag (aspectLabel aspect) value :: extras)


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


field : Bool -> CharacterSheet -> CharacterField -> String -> String -> Element Msg
field editable ch fieldTag label value =
    if editable then
        Input.text
            (inputAttrs ++ [ Ui.onBlur (CharacterFieldBlur ch.slot) ])
            { onChange = CharacterFieldInput ch.slot fieldTag
            , text = value
            , placeholder = Nothing
            , label = fieldLabel label
            }

    else
        readOnlyField label value


notesField : Bool -> CharacterSheet -> Element Msg
notesField editable ch =
    if editable then
        Input.multiline
            (inputAttrs ++ [ height (px 72), Ui.onBlur (CharacterFieldBlur ch.slot) ])
            { onChange = CharacterFieldInput ch.slot NotesField
            , text = ch.notes
            , placeholder = Nothing
            , label = fieldLabel "Notes"
            , spellcheck = False
            }

    else
        readOnlyField "Notes" ch.notes


readOnlyField : String -> String -> Element msg
readOnlyField label value =
    Element.column [ spacing Ui.xs, width fill ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
        , Element.paragraph
            (inputAttrs ++ [ Font.color Ui.inkSoft ])
            [ text
                (if String.trim value == "" then
                    "—"

                 else
                    value
                )
            ]
        ]


{-| A character's boons, at the top of the sheet where a player can see their
spendable stones alongside the current roll. The boons show as circles; the ones
pledged into the next roll carry a centre dot rather than a separate count. The
facilitator gets a Grant `+` / `−`; the sheet's owner gets a Pledge `+` / `−`
and a note of any unresolved pledge proposals.
-}
boonsBlock : Bool -> Bool -> CharacterSheet -> Int -> Int -> Maybe String -> Element Msg
boonsBlock facilitator mine ch pledged pending pendingId =
    Element.column [ spacing Ui.xs, width fill ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.boonsLabel)
        , boonCircles ch.fate pledged
        , Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
            (grantControls facilitator ch ++ pledgeControls mine pending pendingId)
        ]


{-| `total` boon circles, the first `pledged` of them marked as pledged into the
next roll.
-}
boonCircles : Int -> Int -> Element msg
boonCircles total pledged =
    if total <= 0 then
        el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.boonsNone)

    else
        Element.wrappedRow [ spacing Ui.xs ]
            (List.range 1 total
                |> List.map (\i -> Ui.boonDot (i <= pledged))
            )


grantControls : Bool -> CharacterSheet -> List (Element Msg)
grantControls facilitator ch =
    if facilitator then
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.grant)
        , Ui.ghostButton { onPress = Just (FateDecrement ch.slot), label = "−" }
        , Ui.ghostButton { onPress = Just (FateIncrement ch.slot), label = "+" }
        ]

    else
        []


pledgeControls : Bool -> Int -> Maybe String -> List (Element Msg)
pledgeControls mine pending pendingId =
    if mine then
        -- "Highlight" is the player-facing name for pledging a boon to the roll.
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.highlight)
        , Ui.ghostButton { onPress = Just CommitBoonDecrement, label = "−" }
        , Ui.ghostButton { onPress = Just CommitBoonIncrement, label = "+" }
        ]
            ++ pendingHint pending pendingId

    else
        []


fieldLabel : String -> Input.Label msg
fieldLabel label =
    Input.labelAbove [ Font.size 11, Font.color Ui.inkSoft ] (text label)
