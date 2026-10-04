module View.ContextAspects exposing (view)

{-| The context boons and banes (the middle column, above the moves): what the
table has established as true. They come from an accepted critical, a Create, a
Complicate (a blank bane for the facilitator to word) or the facilitator
directly. Highlighting one is the Highlight Context move, open to anyone before
the junction is rolled: a boon steps the die up, a bane steps it down, and it is
marked **consumed** — shown struck through and tagged — instead of removed.

The facilitator edits the text in place (saved when the field loses focus),
removes one, and adds a new one through the row at the bottom. Each row leads
with its polarity as a `+` (boon) or `−` (bane) mark.
-}

import Action exposing (Action(..))
import ContextAspect exposing (ContextAspect, Polarity(..))
import Copy
import Dict exposing (Dict)
import Die
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Attributes
import MoveRecord
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, inlineInputAttrs, placeholder)


type alias Props =
    { contextAspectDraft : String
    , contextAspectKind : Polarity
    , edits : Dict String String
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.contextAspects && not ctx.facilitator then
        placeholder Copy.noContextAspects

    else
        Ui.flat
            (List.map (row ctx props.edits gs) gs.contextAspects
                ++ Ui.onlyWhen ctx.facilitator
                    [ addContextAspectRow ctx.inflight props.contextAspectDraft props.contextAspectKind ]
            )


row : ViewContext -> Dict String String -> GameState -> ContextAspect -> Element Msg
row ctx edits gs a =
    let
        facilitator =
            ctx.facilitator

        inflight =
            ctx.inflight
    in
    Element.row
        [ spacing Ui.sm
        , width fill
        , Element.paddingXY 0 2
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        [ kindMark a
        , if facilitator then
            Input.text
                (inlineInputAttrs
                    ++ [ width fill
                       , Ui.onBlur (SaveContextAspectText a.id)
                       , Border.color Ui.tint
                       ]
                    ++ (if a.consumed then
                            [ Font.strike, Font.color Ui.inkSoft ]

                        else
                            []
                       )
                )
                { onChange = ContextAspectTextChanged a.id
                , text = Dict.get a.id edits |> Maybe.withDefault a.text
                , placeholder = Nothing
                , label = Input.labelHidden "Context boon or bane text"
                }

          else
            Element.paragraph
                (Font.size 13
                    :: width fill
                    :: (if a.consumed then
                            [ Font.strike, Font.color Ui.inkSoft ]

                        else
                            []
                       )
                )
                [ text a.text ]
        , if a.consumed then
            el [ Font.size 10, Font.color Ui.inkSoft ] (text Copy.contextAspectConsumed)

          else
            none
        , if a.consumed then
            none

          else
            Ui.linkButton
                { onPress =
                    if canHighlight gs a then
                        Ui.press inflight (MakingMove MoveRecord.HighlightContext) (MakeHighlightContext a.id)

                    else
                        Nothing
                , label = Copy.contextAspectUse
                }
        , if facilitator then
            el [ Element.htmlAttribute (Html.Attributes.title Copy.contextAspectRemove) ]
                (Ui.linkButton
                    { onPress = Ui.press inflight (DeletingContextAspect a.id) (DeleteContextAspect a.id)
                    , label = "×"
                    }
                )

          else
            none
        ]


{-| Highlight Context is a preparation move, refused at the end of the ladder
its polarity pushes toward.
-}
canHighlight : GameState -> ContextAspect -> Bool
canHighlight gs a =
    let
        direction =
            case a.polarity of
                Boon ->
                    Die.Up

                Bane ->
                    Die.Down
    in
    gs.junction == Nothing && Die.step direction gs.die /= Nothing


{-| A context boon or bane's kind as a mark, faded once it has been consumed.
-}
kindMark : ContextAspect -> Element msg
kindMark a =
    let
        mark =
            el [ Font.size 14, Font.bold, Element.width (Element.px 12) ]
                (case a.polarity of
                    Boon ->
                        text "+"

                    Bane ->
                        el [ Font.color Ui.danger ] (text "−")
                )
    in
    if a.consumed then
        el [ Element.alpha 0.4 ] mark

    else
        mark


addContextAspectRow : List Action -> String -> Polarity -> Element Msg
addContextAspectRow inflight draft draftKind =
    let
        canAdd =
            String.trim draft /= ""

        kindButton kind glyph tone =
            Input.button
                [ Font.size 14
                , Font.bold
                , Element.width (Element.px 16)
                , Font.color tone
                , Element.alpha
                    (if draftKind == kind then
                        1

                     else
                        0.35
                    )
                ]
                { onPress = Just (ContextAspectKindChanged kind)
                , label = el [ Element.centerX ] (text glyph)
                }

        addMsg =
            if canAdd then
                Ui.press inflight AddingContextAspect AddContextAspect

            else
                Nothing
    in
    Element.row [ spacing Ui.xs, width fill, Element.centerY, Element.paddingXY 0 4 ]
        [ kindButton Boon "+" Ui.accent
        , kindButton Bane "−" Ui.danger
        , Input.text
            (inlineInputAttrs ++ [ width fill, Ui.onEnter AddContextAspect ])
            { onChange = ContextAspectDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addContextAspectPlaceholder))
            , label = Input.labelHidden "New context boon or bane"
            }
        , Ui.ghostButton { onPress = addMsg, label = Copy.addContextAspect }
        ]
