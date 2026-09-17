module View.Stones exposing (view)

{-| The Stones card: the bag, the facilitator's direct pool edits, the
session's floating boons — Boon or Bane, 23.3 — (also facilitator-run, 23.2),
the facilitator's one-click draw, and the facilitator's proposal queue. A draw
(23.1) is a stateless read of the pool — its result shows up as a log line,
not as anything rendered here. "Add boon" is gone for players and facilitator
alike (23.2) — the facilitator hand-edits the pool directly instead — and so
is "Use" on a floating boon (23.3): the facilitator plants and removes session
context directly, with no third "spend it" state in between.
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
import View.Helpers
    exposing
        ( ViewContext
        , characterLabel
        , glossaryTitle
        , inputAttrs
        , stoneChip
        , tip
        )


type alias Props =
    { inflight : Set String
    , drafts : Dict String String
    , floatingBoonDraft : String
    , floatingBoonKind : Stone
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    let
        committed =
            List.foldl (\c acc -> acc + c.count) 0 gs.committedBoons
    in
    Ui.card
        [ glossaryTitle Copy.stonesTitle "Stone"
        , Element.column [ spacing Ui.md, width fill ]
            [ Element.wrappedRow [ spacing Ui.xs ]
                (List.map stoneChip gs.stonePool
                    ++ List.repeat committed (Ui.pledgedStoneChip Ui.boonFill Copy.pledgedChip)
                )
            , el [ Font.size 12, Font.color Ui.inkSoft ]
                (text (Copy.bagOf (List.length gs.stonePool + committed)))
            , poolControls ctx.facilitator props.inflight
            , floatingBoonsBlock ctx.facilitator props.inflight props.floatingBoonDraft props.floatingBoonKind gs
            , Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                (Ui.onlyWhen ctx.facilitator
                    [ Ui.primaryButton
                        { onPress = Ui.press props.inflight "stones:draw" DrawStones
                        , label = Copy.draw
                        }
                    ]
                )
            , proposalsPanel ctx.facilitator props.inflight props.drafts gs.characters gs.proposals
            ]
        ]


{-| Facilitator-only hand-edit of the shared pool (23.2): add or remove one
Boon or one Bane at a time, independent of a draw and of every other
free-standing resource action — nothing here tries to link to the other.
-}
poolControls : Bool -> Set String -> Element Msg
poolControls facilitator inflight =
    if not facilitator then
        none

    else
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


{-| The session's floating boons — a Boon or (23.3) a Bane, context the
facilitator has planted directly or approved from an Add a Detail / Gain
Insight (always a Boon). Read-only for players; the facilitator can remove
any of them outright, and plant a new one — kind and note — through the
fields at the bottom, shown even with none yet so there is always somewhere
to add the first one.
-}
floatingBoonsBlock : Bool -> Set String -> String -> Stone -> GameState -> Element Msg
floatingBoonsBlock facilitator inflight draft draftKind gs =
    if List.isEmpty gs.floatingBoons && not facilitator then
        none

    else
        let
            row fb =
                Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
                    [ floatingBoonChip fb.kind
                    , Element.paragraph [ Font.size 12 ] [ text fb.text ]
                    , if facilitator then
                        el [ Element.alignRight ]
                            (Ui.ghostButton
                                { onPress = Ui.press inflight ("stones:floating-delete:" ++ fb.id) (DeleteFloatingBoon fb.id)
                                , label = Copy.floatingBoonRemove
                                }
                            )

                      else
                        none
                    ]
        in
        Element.column [ spacing Ui.xs, width fill ]
            (tip "Floating boon"
                (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.floatingBoons))
                :: List.map row gs.floatingBoons
                ++ Ui.onlyWhen facilitator [ addFloatingBoonRow inflight draft draftKind ]
            )


{-| A session-context chip: coloured and captioned by `kind`, marked with a
centre dot to set it apart from a plain bag stone.
-}
floatingBoonChip : Stone -> Element msg
floatingBoonChip kind =
    case kind of
        Boon ->
            Ui.pledgedStoneChip Ui.boonFill Copy.boonStone

        Bane ->
            Ui.pledgedStoneChip Ui.baneFill Copy.baneStone


addFloatingBoonRow : Set String -> String -> Stone -> Element Msg
addFloatingBoonRow inflight draft draftKind =
    Element.wrappedRow [ spacing Ui.sm, width fill, Element.centerY ]
        [ Ui.tab (draftKind == Boon) Copy.boonStone (FloatingBoonKindChanged Boon)
        , Ui.tab (draftKind == Bane) Copy.baneStone (FloatingBoonKindChanged Bane)
        , Input.text
            (inputAttrs ++ [ width fill ])
            { onChange = FloatingBoonDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addFloatingBoonPlaceholder))
            , label = Input.labelHidden "New floating boon"
            }
        , Ui.ghostButton
            { onPress =
                if String.trim draft == "" then
                    Nothing

                else
                    Ui.press inflight "stones:floating-add" AddFloatingBoon
            , label = Copy.addFloatingBoon
            }
        ]


{-| Facilitator's queue of player-initiated requests awaiting a decision. Hidden
for players and when empty. `drafts` holds the context note typed for each
Add a Detail / Gain Insight, keyed by proposal id so the rows do not share one
field.
-}
proposalsPanel : Bool -> Set String -> Dict String String -> List CharacterSheet -> List Proposal -> Element Msg
proposalsPanel facilitator inflight drafts characters proposals =
    if not facilitator || List.isEmpty proposals then
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
