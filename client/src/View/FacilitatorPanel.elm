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

import Copy
import Dict exposing (Dict)
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Kind
import Roll exposing (Stone(..), stoneLabel)
import Set exposing (Set)
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, accordionHeader, characterLabel, inputAttrs)


type alias Props =
    { inflight : Set String
    , drafts : Dict String String
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
                            { onPress = Ui.press props.inflight "stones:draw" DrawStones
                            , label = Copy.draw
                            }
                        , poolControls props.inflight
                        , proposalsPanel props.inflight props.drafts gs.characters gs.proposals
                        ]

                    else
                        []
                   )
            )


{-| Direct hand-edit of the shared pool (23.2): add or remove one Boon or one
Bane at a time, independent of a draw and of every other free-standing
resource action — nothing here tries to link to the other.
-}
poolControls : Set String -> Element Msg
poolControls inflight =
    Element.wrappedRow [ spacing Ui.md, Element.centerY ] [ stoneControl inflight Boon, stoneControl inflight Bane ]


stoneControl : Set String -> Stone -> Element Msg
stoneControl inflight stone =
    let
        label =
            stoneLabel stone
    in
    Element.row [ spacing Ui.xs, Element.centerY ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
        , Ui.ghostButton
            { onPress = Ui.press inflight ("stones:remove-" ++ label) (RemoveStone stone)
            , label = "−"
            }
        , Ui.ghostButton
            { onPress = Ui.press inflight ("stones:add-" ++ label) (AddStone stone)
            , label = "+"
            }
        ]


{-| The queue of player-initiated requests awaiting a decision. Hidden when
empty — with every proposal-posting control disconnected from the client
(23.4) alongside `pledge` and `add-boon` (23.2), that is its steady state for
now; the routes stay live for whichever one is re-wired first. `drafts` holds
the context note typed for each Add a Detail / Gain Insight, keyed by
proposal id so the rows do not share one field.
-}
proposalsPanel : Set String -> Dict String String -> List CharacterSheet -> List Proposal -> Element Msg
proposalsPanel inflight drafts characters proposals =
    if List.isEmpty proposals then
        none

    else
        Element.column [ spacing Ui.sm, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.proposalsTitle)
                :: List.map (proposalRow inflight drafts characters) proposals
            )


proposalRow : Set String -> Dict String String -> List CharacterSheet -> Proposal -> Element Msg
proposalRow inflight drafts characters p =
    let
        needsContext =
            p.kind == Kind.AbilityProposal Kind.AddDetail || p.kind == Kind.AbilityProposal Kind.GainInsight

        draft =
            Dict.get p.id drafts |> Maybe.withDefault ""

        acceptEnabled =
            not needsContext || String.trim draft /= ""

        busy =
            Set.member ("proposal:accept:" ++ p.id) inflight
                || Set.member ("proposal:reject:" ++ p.id) inflight

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
                , placeholder = Just (Input.placeholder [] (text Copy.floatingBoonContextPlaceholder))
                , label = Input.labelHidden "Floating boon context"
                }

          else
            none
        ]


describeProposal : List CharacterSheet -> Proposal -> String
describeProposal characters p =
    case p.kind of
        Kind.AddBoon ->
            Copy.proposalAddBoon

        Kind.Pledge ->
            if p.delta >= 0 then
                Copy.proposalPledge

            else
                Copy.proposalPledgeWithdraw

        Kind.AbilityProposal Kind.HelpOut ->
            Copy.proposalHelpOut

        Kind.AbilityProposal Kind.AddDetail ->
            Copy.proposalAddDetail

        Kind.AbilityProposal Kind.GainInsight ->
            Copy.proposalGainInsight

        Kind.AbilityProposal Kind.SuggestCompel ->
            Copy.proposalSuggestCompelOn
                (p.targetSlot
                    |> Maybe.andThen (\s -> characterAtSlot s characters)
                    |> Maybe.map characterLabel
                    |> Maybe.withDefault Copy.proposalSuggestCompelFallback
                )

        Kind.AcceptCompel ->
            Copy.proposalAcceptCompel

        Kind.UseFloating ->
            Copy.proposalUseFloating
