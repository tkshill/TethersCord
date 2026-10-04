module View.ContextAspects exposing (createField, view)

{-| The context boons and banes (the middle column): what the table has
established as true. Each is a button — pressing it is the Highlight Context
move, open to anyone before the junction is rolled: a boon steps the die up, a
bane steps it down, and it is marked **consumed** (struck through, tagged, and
no longer pressable) rather than removed. A Complicate's bane arrives blank,
naming the aspect it came from, for the facilitator to word.

The facilitator's ✎ swaps a row's button for its text field (saved, and
swapped back, when the field loses focus) and × removes it. `createField` is
the field at the foot of the list: Create for a player (a boon for a context
boon in their words), or, for the facilitator, a free context boon or bane with
a ☼ / ☽ toggle.
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
import View.Helpers exposing (ViewContext, characterLabel, contextAspectFieldId, inlineInputAttrs, placeholder)


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


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.contextAspects then
        placeholder Copy.noContextAspects

    else
        Ui.flat (List.map (row ctx props.edits gs) gs.contextAspects)


row : ViewContext -> Dict String String -> GameState -> ContextAspect -> Element Msg
row ctx edits gs a =
    Element.row
        [ spacing Ui.sm
        , width fill
        , Element.paddingXY 0 2
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        [ polarityMark a
        , case ( ctx.facilitator, Dict.get a.id edits ) of
            ( True, Just draft ) ->
                Input.text
                    (inlineInputAttrs
                        ++ [ width fill
                           , Ui.onBlur (SaveContextAspectText a.id)
                           , Ui.onEnter (SaveContextAspectText a.id)
                           , Element.htmlAttribute (Html.Attributes.id (contextAspectFieldId a.id))
                           ]
                    )
                    { onChange = ContextAspectTextChanged a.id
                    , text = draft
                    , placeholder = Just (Input.placeholder [] (text Copy.contextAspectWordingPlaceholder))
                    , label = Input.labelHidden "Context boon or bane text"
                    }

            _ ->
                aspectButton ctx gs a
        , if a.consumed then
            el [ Font.size 10, Font.color Ui.inkSoft ] (text Copy.contextAspectConsumed)

          else
            none
        , if ctx.facilitator then
            Element.row [ spacing Ui.sm, Element.centerY ]
                [ Ui.pencil { onPress = Just (EditContextAspect a.id), tip = Copy.editTip }
                , Ui.withTip Copy.contextAspectRemove
                    (Ui.linkButton
                        { onPress = Ui.press ctx.inflight (DeletingContextAspect a.id) (DeleteContextAspect a.id)
                        , label = "×"
                        }
                    )
                ]

          else
            none
        ]


{-| The aspect as its Highlight Context button: its text, or — for a
Complicate's bane not yet worded — where it came from. Off once consumed,
while a roll is pending, or at the end of the ladder its polarity pushes
toward; the tooltip says which.
-}
aspectButton : ViewContext -> GameState -> ContextAspect -> Element Msg
aspectButton ctx gs a =
    let
        direction =
            case a.polarity of
                Boon ->
                    Die.Up

                Bane ->
                    Die.Down

        ( enabled, tip ) =
            if a.consumed then
                ( False, Copy.contextAspectConsumedTip )

            else if gs.junction /= Nothing then
                ( False, Copy.movesLocked )

            else if Die.step direction gs.die == Nothing then
                ( False, Copy.dieAtEnd )

            else
                ( True, Copy.highlightContextTip a.polarity )

        label =
            if String.trim a.text == "" then
                el [ Font.italic, Font.color Ui.inkSoft ] (text (unworded gs a))

            else
                text a.text
    in
    Input.button
        ([ width fill
         , Element.paddingXY 4 3
         , Border.rounded 4
         , Element.htmlAttribute (Html.Attributes.title tip)
         ]
            ++ (if enabled then
                    [ Element.mouseOver [ Background.color Ui.tint ] ]

                else
                    []
               )
            ++ (if a.consumed then
                    [ Font.strike, Font.color Ui.inkSoft ]

                else
                    []
               )
        )
        { onPress =
            if enabled then
                Ui.press ctx.inflight (MakingMove MoveRecord.HighlightContext) (MakeHighlightContext a.id)

            else
                Nothing
        , label = Element.paragraph [ Font.size 13 ] [ label ]
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


{-| A context boon or bane's polarity as ☼ or ☽, faded once it is consumed.
-}
polarityMark : ContextAspect -> Element msg
polarityMark a =
    let
        mark =
            el [ Font.size 13, Element.width (Element.px 14), Element.alignTop, Element.paddingXY 0 3 ]
                (case a.polarity of
                    Boon ->
                        Ui.boonMarks 1

                    Bane ->
                        Ui.baneMarks 1
                )
    in
    if a.consumed then
        el [ Element.alpha 0.4, Element.alignTop ] mark

    else
        mark


{-| The field at the foot of the list. For a player it is Create: a boon for a
context boon in their words (blank is recorded as a detail from them). For the
facilitator it adds a context boon or bane directly, free, with a ☼ / ☽ toggle.
-}
createField : ViewContext -> Props -> GameState -> Element Msg
createField ctx props gs =
    Element.el
        [ width fill
        , Element.paddingEach { top = 6, right = 0, bottom = 0, left = 0 }
        , Border.widthEach { top = 1, right = 0, bottom = 0, left = 0 }
        , Border.color Ui.line
        ]
        (if ctx.facilitator then
            facilitatorAdd ctx.inflight props.facilitatorDraft props.facilitatorKind

         else
            playerCreate ctx props.createDraft gs
        )


playerCreate : ViewContext -> String -> GameState -> Element Msg
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
    Element.row [ spacing Ui.xs, width fill, Element.centerY ]
        [ Input.text
            (inlineInputAttrs
                ++ [ width fill ]
                ++ (case onPress of
                        Just msg ->
                            [ Ui.onEnter msg ]

                        Nothing ->
                            []
                   )
            )
            { onChange = CreateDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.createPlaceholder))
            , label = Input.labelHidden "Create"
            }
        , Ui.withTip (Maybe.withDefault Copy.createTip reason)
            (Ui.ghostButton { onPress = onPress, label = Copy.createButton })
        ]


facilitatorAdd : List Action -> String -> Polarity -> Element Msg
facilitatorAdd inflight draft kind =
    let
        toggle polarity mark tip =
            Input.button
                (Element.width (Element.px 16)
                    :: Element.alpha
                        (if kind == polarity then
                            1

                         else
                            0.35
                        )
                    :: [ Element.htmlAttribute (Html.Attributes.title tip) ]
                )
                { onPress = Just (ContextAspectKindChanged polarity)
                , label = el [ Element.centerX, Font.size 13 ] mark
                }

        addMsg =
            if String.trim draft /= "" then
                Ui.press inflight AddingContextAspect AddContextAspect

            else
                Nothing
    in
    Element.row [ spacing Ui.xs, width fill, Element.centerY ]
        [ toggle Boon (Ui.boonMarks 1) Copy.contextBoonToggleTip
        , toggle Bane (Ui.baneMarks 1) Copy.contextBaneToggleTip
        , Input.text
            (inlineInputAttrs ++ [ width fill, Ui.onEnter AddContextAspect ])
            { onChange = ContextAspectDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addContextAspectPlaceholder))
            , label = Input.labelHidden "New context boon or bane"
            }
        , Ui.ghostButton { onPress = addMsg, label = Copy.addContextAspect }
        ]
