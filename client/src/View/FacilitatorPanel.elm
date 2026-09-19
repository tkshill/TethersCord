module View.FacilitatorPanel exposing (view)

{-| The facilitator-only panel in the left column (roadmap section 23.5/23.6):
the one-click draw (23.1), direct pool edits (23.2), and the queue of
player-initiated proposals awaiting a decision. Everything here is
independent of everything else — clicking one has no effect on what any of
the others can do next (23.2). Renders nothing for a player; the column's
Characters card above it is the one they share. Collapsible as one of the
left panel's three accordion sections (24, the 1c layout variant); its own
title doubles as the toggle, same as `View.Guide`'s always has.
-}

import Action exposing (Action(..), Decision(..))
import Copy
import Dict exposing (Dict)
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Kind
import Roll exposing (Stone(..), stoneLabel)
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, accordionHeader, characterLabel, inputAttrs)


type alias Props =
    { drafts : Dict String String
    , open : Bool
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if not ctx.facilitator then
        none

    else
        Ui.card
            (accordionHeader props.open (Ui.sectionTitle Copy.facilitatorPanelTitle) (ToggleLeftSection FacilitatorSection)
                :: (if props.open then
                        [ Ui.primaryButton
                            { onPress = Ui.press ctx.inflight DrawingStones DrawStones
                            , label = Copy.draw
                            }
                        , poolControls ctx.inflight
                        , proposalsPanel ctx.inflight props.drafts gs.characters gs.proposals
                        ]

                    else
                        []
                   )
            )


{-| Direct hand-edit of the shared pool (23.2): add or remove one Boon or one
Bane at a time, independent of a draw and of every other free-standing
resource action — nothing here tries to link to the other.
-}
poolControls : List Action -> Element Msg
poolControls inflight =
    Element.wrappedRow [ spacing Ui.md, Element.centerY ] [ stoneControl inflight Boon, stoneControl inflight Bane ]


stoneControl : List Action -> Stone -> Element Msg
stoneControl inflight stone =
    let
        label =
            stoneLabel stone
    in
    Element.row [ spacing Ui.xs, Element.centerY ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
        , Ui.ghostButton
            { onPress = Ui.press inflight (RemovingStone stone) (RemoveStone stone)
            , label = "−"
            }
        , Ui.ghostButton
            { onPress = Ui.press inflight (AddingStone stone) (AddStone stone)
            , label = "+"
            }
        ]


{-| The queue of player-initiated requests awaiting a decision. Hidden when
empty — with every proposal-posting control disconnected from the client
(23.4) alongside `highlight` and `add-boon` (23.2), that is its steady state for
now; the routes stay live for whichever one is re-wired first. `drafts` holds
the context note typed for each Add Detail / Gain Insight, keyed by
proposal id so the rows do not share one field.
-}
proposalsPanel : List Action -> Dict String String -> List CharacterSheet -> List Proposal -> Element Msg
proposalsPanel inflight drafts characters proposals =
    if List.isEmpty proposals then
        none

    else
        Element.column [ spacing Ui.sm, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.proposalsTitle)
                :: List.map (proposalRow inflight drafts characters) proposals
            )


proposalRow : List Action -> Dict String String -> List CharacterSheet -> Proposal -> Element Msg
proposalRow inflight drafts characters p =
    let
        needsContext =
            p.kind == Kind.AbilityProposal Kind.AddDetail || p.kind == Kind.AbilityProposal Kind.GainInsight

        draft =
            Dict.get p.id drafts |> Maybe.withDefault ""

        acceptEnabled =
            not needsContext || String.trim draft /= ""

        busy =
            Action.isPending (ResolvingProposal Accepting p.id) inflight
                || Action.isPending (ResolvingProposal Rejecting p.id) inflight

        controls =
            Element.row [ spacing Ui.sm, Element.centerY, Element.alignRight ]
                [ Ui.ghostButton
                    { onPress =
                        if busy then
                            Nothing

                        else
                            Just (RejectProposal p.id)
                    , label = Copy.reject
                    }
                , Ui.primaryButton
                    { onPress =
                        if acceptEnabled && not busy then
                            Just (AcceptProposal p.id)

                        else
                            Nothing
                    , label = Copy.accept
                    }
                ]
    in
    Element.column [ width fill, spacing Ui.xs ]
        [ Element.wrappedRow [ width fill, spacing Ui.sm, Element.centerY ]
            [ Element.paragraph [ Font.size 12 ]
                [ text (p.proposerName ++ " — " ++ describeProposal characters p) ]
            , controls
            ]
        , if needsContext then
            Input.text
                (inputAttrs ++ [ width fill ])
                { onChange = ProposalDraftChanged p.id
                , text = draft
                , placeholder = Just (Input.placeholder [] (text Copy.sessionAspectContextPlaceholder))
                , label = Input.labelHidden "Session boon context"
                }

          else
            none
        ]


describeProposal : List CharacterSheet -> Proposal -> String
describeProposal characters p =
    case p.kind of
        Kind.AddBoon ->
            Copy.proposalAddBoon

        Kind.Highlight ->
            if p.delta >= 0 then
                Copy.proposalHighlight

            else
                Copy.proposalHighlightWithdraw

        Kind.AbilityProposal Kind.Alter ->
            Copy.proposalAlter

        Kind.AbilityProposal Kind.AddDetail ->
            Copy.proposalAddDetail

        Kind.AbilityProposal Kind.GainInsight ->
            Copy.proposalGainInsight

        Kind.AbilityProposal Kind.Complicate ->
            Copy.proposalComplicateOn
                (p.targetSlot
                    |> Maybe.andThen (\s -> characterAtSlot s characters)
                    |> Maybe.map characterLabel
                    |> Maybe.withDefault Copy.proposalComplicateFallback
                )

        Kind.AcceptCompel ->
            Copy.proposalAcceptCompel

        Kind.UseSessionBoon ->
            Copy.proposalUseSessionBoon
