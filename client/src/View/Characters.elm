module View.Characters exposing (view)

{-| A character's sheet, picked from the tool strip (roadmap 32.4, Table v2):
the name with the character's boons beside it (and the facilitator's − / +),
the notable features under it, the owner line, then the three aspects as
blocks and the notes.

On the viewer's own sheet, before a roll, each written aspect is a split
button (31.5): the left half Complicates, the right half Highlights, each
greyed with its reason when it cannot be made. The ✎ in a block's corner swaps
in the text field; leaving the field saves it and swaps the block back. An
empty aspect on an editable sheet is its field straight away, with "see
examples" beneath. An aspect shows the Banes it accumulated before 23.1 as ☽
marks on its label row.
-}

import Action exposing (Action(..))
import Aspect exposing (Aspect(..))
import Copy
import Die
import Element exposing (Element, el, fill, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Format
import Html.Attributes
import MoveRecord
import Types exposing (..)
import Ui
import View.Helpers
    exposing
        ( ViewContext
        , aspectFieldId
        , characterLabel
        , placeholder
        , tipAttrs
        )


type alias Props =
    { selectedSlot : Int
    , aspectExamplesOpen : Maybe ( Int, Aspect )
    , aspectEditing : Maybe ( Int, Aspect )
    }


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
        mine =
            ch.ownerId /= Nothing && ch.ownerId == ctx.myId

        editable =
            ctx.facilitator || mine || ch.ownerId == Nothing
    in
    Element.column [ spacing 10, width fill ]
        ([ Element.column [ spacing 2, width fill ]
            [ header ctx.facilitator editable ch
            , ownerLine ctx mine gs ch
            , notableFeatures editable ch
            ]
         ]
            ++ Ui.onlyWhen (mine && gs.junction /= Nothing) [ lockedNote ]
            ++ List.map
                (\( aspect, fieldTag, value ) -> aspectBlock ctx props gs { mine = mine, editable = editable } ch aspect fieldTag value)
                [ ( Archetype, ArchetypeField, ch.archetype )
                , ( Desire, DesireField, ch.desire )
                , ( Quest, QuestField, ch.quest )
                ]
            ++ [ notesField editable ch ]
        )


{-| The name at display size, the boons beside it as ☼ marks, and the
facilitator's − / + after them. On an editable sheet the name is a field with
no chrome, so it reads as the heading it is until clicked.
-}
header : Bool -> Bool -> CharacterSheet -> Element Msg
header facilitator editable ch =
    let
        name =
            if editable then
                Input.text
                    (bareInputAttrs
                        ++ [ width fill
                           , Font.size 22
                           , Font.medium
                           , Ui.onBlur (CharacterFieldBlur ch.slot)
                           ]
                    )
                    { onChange = CharacterFieldInput ch.slot NameField
                    , text = ch.name
                    , placeholder = Just (Input.placeholder [] (text Copy.namePlaceholder))
                    , label = Input.labelHidden "Name"
                    }

            else
                Element.paragraph [ width fill, Font.size 22, Font.medium, Ui.wrapAnywhere ] [ text (characterLabel ch) ]

        boons =
            if ch.fate <= 0 then
                el [ Font.size 12, Font.color Ui.inkSoft, Element.centerY ] (text Copy.boonsNone)

            else
                el
                    [ Font.size 17
                    , Element.centerY
                    , Element.htmlAttribute (Html.Attributes.title (Copy.boonsTip ch.fate))
                    ]
                    (Ui.boonMarks ch.fate)

        boonButton msg label tip =
            Ui.squareButton
                { onPress = Just msg
                , label = label
                , tip = tip
                , width = 22
                , height = 22
                , radius = 4
                , size = 13
                }
    in
    Element.row [ width fill, spacing Ui.sm ]
        (el [ width fill, Ui.shrinkableWidth ] name
            :: boons
            :: Ui.onlyWhen facilitator
                [ Element.row [ spacing Ui.xs, Element.centerY ]
                    [ boonButton (FateDecrement ch.slot) "−" Copy.removeBoonTip
                    , boonButton (FateIncrement ch.slot) "+" Copy.grantBoonTip
                    ]
                ]
        )


{-| Who holds the sheet, with Claim or Release at the right. Shown to the
facilitator, on an unclaimed sheet, and on the viewer's own (where Release
lives); a player looking at someone else's claimed sheet sees nothing here.
The holder's name is the Discord name on their latest message in the log, or
"Claimed" when they have not spoken in it.
-}
ownerLine : ViewContext -> Bool -> GameState -> CharacterSheet -> Element Msg
ownerLine ctx mine gs ch =
    let
        line label action =
            Element.row [ width fill, spacing Ui.sm ]
                (el [ Ui.fontSize 11, Font.color Ui.inkSoft ] (text label)
                    :: (case action of
                            Just ( msg, actionLabel ) ->
                                [ el [ Element.alignRight ] (Ui.linkButton { onPress = Just msg, label = actionLabel }) ]

                            Nothing ->
                                []
                       )
                )
    in
    if mine then
        line Copy.ownerMine (Just ( ReleaseSlot ch.slot, Copy.ownerRelease ))

    else
        case ch.ownerId of
            Nothing ->
                line Copy.ownerUnclaimed (Just ( ClaimSlot ch.slot, Copy.ownerClaim ))

            Just ownerId ->
                if ctx.facilitator then
                    line
                        (ownerName ownerId gs
                            |> Maybe.map Copy.ownerPlayedBy
                            |> Maybe.withDefault Copy.ownerClaimed
                        )
                        Nothing

                else
                    Element.none


ownerName : String -> GameState -> Maybe String
ownerName ownerId gs =
    gs.messages
        |> List.filter (\m -> m.authorId == ownerId)
        |> List.reverse
        |> List.head
        |> Maybe.map .authorName


{-| The one-line description under the name: italic and quiet, a field with
no chrome on an editable sheet.
-}
notableFeatures : Bool -> CharacterSheet -> Element Msg
notableFeatures editable ch =
    let
        style =
            [ Ui.fontSize 13.5, Font.italic, Font.color Ui.inkSoft ]
    in
    if editable then
        Input.multiline
            (bareInputAttrs
                ++ style
                ++ [ width fill
                   , Element.htmlAttribute (Html.Attributes.title Copy.notableFeaturesLabel)
                   , Ui.onBlur (CharacterFieldBlur ch.slot)
                   ]
            )
            { onChange = String.replace "\n" " " >> CharacterFieldInput ch.slot NotableFeaturesField
            , text = ch.notableFeatures
            , placeholder = Just (Input.placeholder [] (text Copy.notableFeaturesPlaceholder))
            , label = Input.labelHidden Copy.notableFeaturesLabel
            , spellcheck = True
            }

    else if String.trim ch.notableFeatures == "" then
        Element.none

    else
        Element.paragraph (width fill :: Ui.wrapAnywhere :: style) [ text ch.notableFeatures ]


{-| On the viewer's own sheet while a roll is pending: why the aspects have
stopped being buttons.
-}
lockedNote : Element msg
lockedNote =
    el
        [ width fill
        , Ui.fontSize 11.5
        , Font.color Ui.inkSoft
        , Element.paddingXY 8 5
        , Background.color Ui.tint
        , Border.rounded 5
        ]
        (Element.paragraph [] [ text Copy.movesLocked ])


{-| One aspect as a block. A written aspect shows its statement, with the
split button on the viewer's own sheet before a roll and a ✎ wherever it can
be edited; an empty one on an editable sheet, or one whose ✎ was pressed, is
its field instead, with "see examples" beneath.
-}
aspectBlock :
    ViewContext
    -> Props
    -> GameState
    -> { mine : Bool, editable : Bool }
    -> CharacterSheet
    -> Aspect
    -> CharacterField
    -> String
    -> Element Msg
aspectBlock ctx props gs who ch aspect fieldTag value =
    let
        written =
            String.trim value /= ""

        editing =
            who.editable && (not written || props.aspectEditing == Just ( ch.slot, aspect ))

        count =
            aspectBaneCount aspect ch.aspectBanes

        meta =
            Ui.sectionTitle (Aspect.label aspect)
                :: Ui.onlyWhen (count > 0)
                    [ el
                        [ Font.size 12
                        , Element.htmlAttribute
                            (Html.Attributes.title (String.fromInt count ++ " " ++ Format.pluralize count Copy.baneLabel ++ " on this aspect"))
                        ]
                        (Ui.baneMarks count)
                    ]

        statement =
            if editing then
                aspectInput ch aspect fieldTag value

            else
                Ui.statement [] value

        block =
            Ui.aspectBlock
                { meta = meta
                , statement = statement
                , corner =
                    if who.editable && not editing then
                        Just (Ui.pencil { onPress = Just (EditAspect ch.slot aspect), tip = Copy.editTip })

                    else
                        Nothing
                , press = Nothing
                , dashed = False
                , split =
                    if who.mine && not editing && gs.junction == Nothing then
                        Just (aspectMoves ctx gs ch aspect)

                    else
                        Nothing
                }
    in
    if editing then
        Element.column [ width fill, spacing Ui.xs ]
            (block :: aspectExamplesBlock props.aspectExamplesOpen ch.slot aspect)

    else
        Element.el (width fill :: tipAttrs (Aspect.label aspect)) block


{-| The two halves of a written aspect on the viewer's own sheet: Complicate
on the left, Highlight on the right, each with its reason when it cannot be
made.
-}
aspectMoves :
    ViewContext
    -> GameState
    -> CharacterSheet
    -> Aspect
    ->
        { left : { onPress : Maybe Msg, label : String, tip : String }
        , right : { onPress : Maybe Msg, label : String, tip : String }
        }
aspectMoves ctx gs ch aspect =
    let
        highlight =
            if ch.fate < highlightCost then
                Err Copy.needsABoon

            else if Die.stepUp gs.die == Nothing then
                Err Copy.dieAtTop

            else
                Ok (MakeHighlight aspect)

        half label okTip kind outcome =
            case outcome of
                Ok msg ->
                    { onPress = Ui.press ctx.inflight (MakingMove kind) msg, label = label, tip = okTip }

                Err reason ->
                    { onPress = Nothing, label = label, tip = reason }
    in
    { left = half Copy.complicateHalf Copy.complicateTip MoveRecord.Complicate (Ok (MakeComplicate aspect))
    , right = half Copy.highlightHalf Copy.highlightTip MoveRecord.Highlight highlight
    }


{-| What a Highlight costs, in boons (RULES.md "Moves"); the Worker checks it too.
-}
highlightCost : Int
highlightCost =
    1


{-| An aspect's field inside its block: statement-sized, no chrome. A line
break (Enter, or a paste) becomes a space, so the aspect stays one statement.
-}
aspectInput : CharacterSheet -> Aspect -> CharacterField -> String -> Element Msg
aspectInput ch aspect fieldTag value =
    Input.multiline
        (bareInputAttrs
            ++ [ width fill
               , Font.size 15
               , Ui.onBlur (CharacterFieldBlur ch.slot)
               , Element.htmlAttribute (Html.Attributes.id (aspectFieldId ch.slot aspect))
               ]
        )
        { onChange = String.replace "\n" " " >> CharacterFieldInput ch.slot fieldTag
        , text = value
        , placeholder = Nothing
        , label = Input.labelHidden (Aspect.label aspect)
        , spellcheck = True
        }


{-| The "see examples" toggle under an aspect being written, expanding a short
list of sample aspects from `ASPECTS.md` when it is the open one.
-}
aspectExamplesBlock : Maybe ( Int, Aspect ) -> Int -> Aspect -> List (Element Msg)
aspectExamplesBlock examplesOpen slot aspect =
    let
        open =
            examplesOpen == Just ( slot, aspect )
    in
    Ui.linkButton
        { onPress = Just (ToggleAspectExamples slot aspect)
        , label =
            if open then
                Copy.aspectExamplesHideLabel

            else
                Copy.aspectExamplesLabel
        }
        :: Ui.onlyWhen open
            [ Element.column [ spacing Ui.xs, Element.paddingEach { top = 0, right = 0, bottom = Ui.xs, left = Ui.sm } ]
                (List.map exampleRow (Copy.aspectExamples aspect))
            ]


exampleRow : String -> Element Msg
exampleRow example =
    Element.paragraph [ Font.size 12, Font.color Ui.inkSoft, spacing 2 ]
        [ text ("· " ++ example) ]


{-| The notes: a label over a two-line field with only a hairline beneath it.
-}
notesField : Bool -> CharacterSheet -> Element Msg
notesField editable ch =
    Element.column [ width fill, spacing Ui.xs ]
        [ Ui.sectionTitle Copy.notesLabel
        , if editable then
            Input.multiline
                (bareInputAttrs
                    ++ [ width fill
                       , Element.height (Element.px 44)
                       , Font.size 13
                       , Element.paddingEach { top = 0, right = 0, bottom = 4, left = 0 }
                       , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
                       , Border.color Ui.line
                       , Element.focused [ Border.color Ui.accent ]
                       , Ui.onBlur (CharacterFieldBlur ch.slot)
                       ]
                )
                { onChange = CharacterFieldInput ch.slot NotesField
                , text = ch.notes
                , placeholder = Just (Input.placeholder [] (text Copy.notesPlaceholder))
                , label = Input.labelHidden Copy.notesLabel
                , spellcheck = False
                }

          else
            Element.paragraph [ width fill, Ui.wrapAnywhere, Font.size 13, Font.color Ui.inkSoft ]
                [ text
                    (if String.trim ch.notes == "" then
                        "—"

                     else
                        ch.notes
                    )
                ]
        ]


{-| A field with no border, padding or background, so it reads as the text
around it; the sheet's name, notable features and aspect fields.
-}
bareInputAttrs : List (Element.Attribute msg)
bareInputAttrs =
    [ Element.padding 0
    , Border.width 0
    , Border.rounded 0
    , Background.color (Element.rgba255 0 0 0 0)
    , Element.focused []
    ]
