module View.Stones exposing (view)

{-| The Stones card: the bag, the facilitator's direct pool edits, the
session's floating boons (also facilitator-run, 23.2), the facilitator's
one-click draw, and the facilitator's proposal queue. A draw (23.1) is a
stateless read of the pool — its result shows up as a log line, not as
anything rendered here. "Add boon" is gone for players and facilitator alike
(23.2) — the facilitator hand-edits the pool directly instead.
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
            , floatingBoonsBlock ctx.facilitator ctx.myId props.inflight props.floatingBoonDraft gs
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


{-| The session's floating boons — context the facilitator has approved, or
(23.2) planted directly. Any player can ask to spend one on the roll (a
Highlight the facilitator then approves); the button is muted once that
request is queued. The facilitator can remove any of them outright, and add a
new one directly through the field at the bottom — shown even with no
floating boons yet, so there is always somewhere to add the first one.
-}
floatingBoonsBlock : Bool -> Maybe String -> Set String -> String -> GameState -> Element Msg
floatingBoonsBlock facilitator myId inflight draft gs =
    if List.isEmpty gs.floatingBoons && not facilitator then
        none

    else
        let
            iOwnASheet =
                List.any (\c -> c.ownerId /= Nothing && c.ownerId == myId) gs.characters

            row fb =
                let
                    queued =
                        List.any
                            (\p -> p.kind == Kind.UseFloating && p.floatingId == Just fb.id)
                            gs.proposals
                in
                Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
                    [ Ui.pledgedStoneChip Ui.boonFill Copy.floatingChip
                    , Element.paragraph [ Font.size 12 ] [ text fb.text ]
                    , if facilitator then
                        el [ Element.alignRight ]
                            (Ui.ghostButton
                                { onPress = Ui.press inflight ("stones:floating-delete:" ++ fb.id) (DeleteFloatingBoon fb.id)
                                , label = Copy.floatingBoonRemove
                                }
                            )

                      else if queued then
                        el [ Font.size 11, Font.color Ui.inkSoft, Element.alignRight ] (text Copy.floatingBoonRequested)

                      else if iOwnASheet then
                        el [ Element.alignRight ]
                            (Ui.ghostButton { onPress = Just (UseFloatingBoon fb.id), label = Copy.floatingBoonUse })

                      else
                        none
                    ]
        in
        Element.column [ spacing Ui.xs, width fill ]
            (tip "Floating boon"
                (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.floatingBoons))
                :: List.map row gs.floatingBoons
                ++ Ui.onlyWhen facilitator [ addFloatingBoonRow inflight draft ]
            )


addFloatingBoonRow : Set String -> String -> Element Msg
addFloatingBoonRow inflight draft =
    Element.wrappedRow [ spacing Ui.sm, width fill ]
        [ Input.text
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
