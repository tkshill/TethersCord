module View.SessionAspects exposing (view)

{-| The session boons and banes tool (roadmap 27, the ◇ "Context" tab; formerly
the 26.3 card): what the table has established as true, that can be spent into
the pool. They come from an accepted Overcome pair, an accepted Add Detail, or
the facilitator directly. Spending one marks it **consumed** — shown struck
through and tagged "used" — instead of removing it, and a consumed one cannot be
spent again.

Read-only for players (they spend a session boon from the Moves tool, which
proposes it). The facilitator edits the text in place (saved when the field loses
focus, so a boon an Overcome created can be worded in their own time), uses one
directly (either kind, no approval), unconsumes one to correct a mistake, or
removes it, and plants a new one through the row at the bottom. Each row leads
with the kind as a `+` (Boon) or `−` (Bane) mark.
-}

import Action exposing (Action(..))
import Copy
import Dict exposing (Dict)
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Attributes
import Roll exposing (Stone(..))
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, inlineInputAttrs, placeholder)


type alias Props =
    { sessionAspectDraft : String
    , sessionAspectKind : Stone
    , edits : Dict String String
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.sessionAspects && not ctx.facilitator then
        placeholder Copy.noSessionAspects

    else
        Ui.flat
            (List.map (row ctx.facilitator ctx.inflight props.edits) gs.sessionAspects
                ++ Ui.onlyWhen ctx.facilitator
                    [ addSessionAspectRow ctx.inflight props.sessionAspectDraft props.sessionAspectKind ]
            )


row : Bool -> List Action -> Dict String String -> SessionAspect -> Element Msg
row facilitator inflight edits a =
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
                       , Ui.onBlur (SaveSessionAspectText a.id)
                       , Border.color Ui.tint
                       ]
                    ++ (if a.consumed then
                            [ Font.strike, Font.color Ui.inkSoft ]

                        else
                            []
                       )
                )
                { onChange = SessionAspectTextChanged a.id
                , text = Dict.get a.id edits |> Maybe.withDefault a.text
                , placeholder = Nothing
                , label = Input.labelHidden "Session boon or bane text"
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
            el [ Font.size 10, Font.color Ui.inkSoft ] (text Copy.sessionAspectConsumed)

          else
            none
        , if facilitator then
            Element.row [ spacing Ui.sm, Element.centerY ]
                [ if a.consumed then
                    Ui.linkButton
                        { onPress = Ui.press inflight (UnconsumingSessionAspect a.id) (UnconsumeSessionAspect a.id)
                        , label = Copy.sessionAspectUnconsume
                        }

                  else
                    Ui.linkButton
                        { onPress = Ui.press inflight (UsingSessionAspect a.id) (UseSessionAspect a.id)
                        , label = Copy.sessionAspectUse
                        }
                , el [ Element.htmlAttribute (Html.Attributes.title Copy.sessionAspectRemove) ]
                    (Ui.linkButton
                        { onPress = Ui.press inflight (DeletingSessionAspect a.id) (DeleteSessionAspect a.id)
                        , label = "×"
                        }
                    )
                ]

          else
            none
        ]


{-| A session boon or bane's kind as a mark, faded once it has been consumed.
-}
kindMark : SessionAspect -> Element msg
kindMark a =
    let
        mark =
            el [ Font.size 14, Font.bold, Element.width (Element.px 12) ]
                (case a.kind of
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


addSessionAspectRow : List Action -> String -> Stone -> Element Msg
addSessionAspectRow inflight draft draftKind =
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
                { onPress = Just (SessionAspectKindChanged kind)
                , label = el [ Element.centerX ] (text glyph)
                }

        addMsg =
            if canAdd then
                Ui.press inflight AddingSessionAspect AddSessionAspect

            else
                Nothing
    in
    Element.row [ spacing Ui.xs, width fill, Element.centerY, Element.paddingXY 0 4 ]
        [ kindButton Boon "+" Ui.accent
        , kindButton Bane "−" Ui.danger
        , Input.text
            (inlineInputAttrs ++ [ width fill, Ui.onEnter AddSessionAspect ])
            { onChange = SessionAspectDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addSessionAspectPlaceholder))
            , label = Input.labelHidden "New session boon or bane"
            }
        , Ui.ghostButton { onPress = addMsg, label = Copy.addSessionAspect }
        ]
