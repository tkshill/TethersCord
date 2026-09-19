module View.SessionAspects exposing (view)

{-| The session boons and banes card (roadmap 26.3): what the table has established
as true, that can be spent into the pool. They come from an accepted Overcome
pair, an accepted Add Detail, or the facilitator directly. Spending one marks it
**consumed** — shown struck through and tagged "used" — instead of removing it,
and a consumed one cannot be spent again.

Read-only for players (they spend a session boon from the Moves card, which
proposes it). The facilitator edits the text in place (saved when the field loses
focus, so a boon an Overcome created can be worded in their own time), uses one
directly (either kind, no approval), unconsumes one to correct a mistake, or
removes it, and plants a new one through the row at the bottom.
-}

import Action exposing (Action(..))
import Copy
import Dict exposing (Dict)
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Roll exposing (Stone(..))
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, glossaryTitle, inputAttrs)


type alias Props =
    { sessionAspectDraft : String
    , sessionAspectKind : Stone
    , edits : Dict String String
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.sessionAspects && not ctx.facilitator then
        none

    else
        Ui.card
            (glossaryTitle Copy.sessionAspectsTitle "Session boon"
                :: List.map (row ctx.facilitator ctx.inflight props.edits) gs.sessionAspects
                ++ Ui.onlyWhen ctx.facilitator
                    [ addSessionAspectRow ctx.inflight props.sessionAspectDraft props.sessionAspectKind ]
            )


row : Bool -> List Action -> Dict String String -> SessionAspect -> Element Msg
row facilitator inflight edits a =
    Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
        [ sessionAspectChip a
        , if facilitator then
            Input.text
                (inputAttrs ++ [ width fill, Ui.onBlur (SaveSessionAspectText a.id) ])
                { onChange = SessionAspectTextChanged a.id
                , text = Dict.get a.id edits |> Maybe.withDefault a.text
                , placeholder = Nothing
                , label = Input.labelHidden "Session boon or bane text"
                }

          else
            Element.paragraph
                (Font.size 12
                    :: (if a.consumed then
                            [ Font.strike, Font.color Ui.inkSoft ]

                        else
                            []
                       )
                )
                [ text a.text ]
        , if a.consumed then
            el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.sessionAspectConsumed)

          else
            none
        , if facilitator then
            Element.row [ spacing Ui.sm, Element.alignRight ]
                [ if a.consumed then
                    Ui.ghostButton
                        { onPress = Ui.press inflight (UnconsumingSessionAspect a.id) (UnconsumeSessionAspect a.id)
                        , label = Copy.sessionAspectUnconsume
                        }

                  else
                    Ui.ghostButton
                        { onPress = Ui.press inflight (UsingSessionAspect a.id) (UseSessionAspect a.id)
                        , label = Copy.sessionAspectUse
                        }
                , Ui.ghostButton
                    { onPress = Ui.press inflight (DeletingSessionAspect a.id) (DeleteSessionAspect a.id)
                    , label = Copy.sessionAspectRemove
                    }
                ]

          else
            none
        ]


{-| A session boon or bane's chip: coloured and captioned by `kind`, and faded
once it has been consumed.
-}
sessionAspectChip : SessionAspect -> Element msg
sessionAspectChip a =
    let
        chip =
            case a.kind of
                Boon ->
                    Ui.stoneChip Ui.boonFill Copy.boonStone

                Bane ->
                    Ui.stoneChip Ui.baneFill Copy.baneStone
    in
    if a.consumed then
        el [ Element.alpha 0.4 ] chip

    else
        chip


addSessionAspectRow : List Action -> String -> Stone -> Element Msg
addSessionAspectRow inflight draft draftKind =
    Element.wrappedRow [ spacing Ui.sm, width fill, Element.centerY ]
        [ Ui.tab (draftKind == Boon) Copy.boonStone (SessionAspectKindChanged Boon)
        , Ui.tab (draftKind == Bane) Copy.baneStone (SessionAspectKindChanged Bane)
        , Input.text
            (inputAttrs ++ [ width fill ])
            { onChange = SessionAspectDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addSessionAspectPlaceholder))
            , label = Input.labelHidden "New session boon or bane"
            }
        , Ui.ghostButton
            { onPress =
                if String.trim draft == "" then
                    Nothing

                else
                    Ui.press inflight AddingSessionAspect AddSessionAspect
            , label = Copy.addSessionAspect
            }
        ]
