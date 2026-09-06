module View.Stones exposing (view)

{-| The Stones card: the open overcome line, the bag, the session's floating
boons, the roll / reroll / accept lifecycle, and the facilitator's proposal
queue.
-}

import Copy
import Dict exposing (Dict)
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Kind
import Set exposing (Set)
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
        , stoneChip
        )


type alias Props =
    { inflight : Set String
    , drafts : Dict String String
    }


{-| Boons the overcome target spends to Reroll. Mirrors the worker's
`REROLL_COST`.
-}
overcomeRerollCost : Int
overcomeRerollCost =
    2


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    let
        committed =
            List.foldl (\c acc -> acc + c.count) 0 gs.committedBoons

        myAddBoons =
            countProposals ctx.myId Kind.AddBoon gs.proposals

        target =
            gs.overcome
                |> Maybe.andThen (\oc -> characterAtSlot oc.targetSlot gs.characters)

        amTarget =
            case target of
                Just t ->
                    t.ownerId /= Nothing && t.ownerId == ctx.myId

                Nothing ->
                    False

        -- The facilitator can always roll; during an overcome the target
        -- player can too.
        canRoll =
            ctx.facilitator || amTarget

        -- A reroll during an overcome is bought with the target's boons, so it
        -- needs at least that many.
        rerollAffordable =
            case target of
                Just t ->
                    t.fate >= overcomeRerollCost

                Nothing ->
                    True

        costSuffix =
            Copy.boonsCostSuffix overcomeRerollCost

        rerollLabel =
            if gs.overcome == Nothing then
                Copy.reroll

            else if amTarget then
                -- Press Fate: the target buying their own reroll.
                Copy.pressFate ++ costSuffix

            else
                Copy.reroll ++ costSuffix
    in
    Ui.card
        [ Ui.sectionTitle Copy.stonesTitle
        , Element.column [ spacing Ui.md, width fill ]
            [ overcomeBlock ctx.facilitator target gs.characters
            , Element.wrappedRow [ spacing Ui.xs ]
                (List.map stoneChip gs.stonePool
                    ++ List.repeat committed (Ui.pledgedStoneChip Ui.boonFill Copy.pledgedChip)
                )
            , el [ Font.size 12, Font.color Ui.inkSoft ]
                (text (Copy.bagOf (List.length gs.stonePool + committed)))
            , floatingBoonsBlock ctx.facilitator ctx.myId gs
            , case gs.pendingRoll of
                Nothing ->
                    Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                        (Ui.ghostButton
                            { onPress = Ui.press props.inflight "stones:add-boon" AddBoon
                            , label = Copy.addBoon
                            }
                            :: pendingHint myAddBoons (latestProposalId ctx.myId Kind.AddBoon gs.proposals)
                            ++ Ui.onlyWhen canRoll
                                [ Ui.primaryButton
                                    { onPress = Ui.press props.inflight "stones:roll" RollStones
                                    , label = Copy.roll
                                    }
                                ]
                        )

                Just pending ->
                    Element.column [ spacing Ui.sm, width fill ]
                        [ Element.wrappedRow [ spacing Ui.xs ]
                            (el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.rolled)
                                :: List.map stoneChip pending.chosen
                            )
                        , Element.wrappedRow [ spacing Ui.sm ]
                            (Ui.onlyWhen canRoll
                                [ Ui.ghostButton
                                    { onPress =
                                        if rerollAffordable then
                                            Ui.press props.inflight "stones:reroll" RerollStones

                                        else
                                            Nothing
                                    , label = rerollLabel
                                    }
                                ]
                                ++ Ui.onlyWhen ctx.facilitator
                                    [ Ui.primaryButton
                                        { onPress = Ui.press props.inflight "stones:accept" AcceptRoll
                                        , label = Copy.accept
                                        }
                                    ]
                            )
                        ]
            , proposalsPanel ctx.facilitator props.inflight props.drafts gs.characters gs.proposals
            ]
        ]


{-| The session's floating boons — context the facilitator has approved that
belongs to no one. Any player can ask to spend one on the roll (a Highlight the
facilitator then approves); the button is muted once that request is queued.
-}
floatingBoonsBlock : Bool -> Maybe String -> GameState -> Element Msg
floatingBoonsBlock facilitator myId gs =
    if List.isEmpty gs.floatingBoons then
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
                    , if queued then
                        el [ Font.size 11, Font.color Ui.inkSoft, Element.alignRight ] (text Copy.floatingBoonRequested)

                      else if iOwnASheet && not facilitator then
                        el [ Element.alignRight ]
                            (Ui.ghostButton { onPress = Just (UseFloatingBoon fb.id), label = Copy.floatingBoonUse })

                      else
                        none
                    ]
        in
        Element.column [ spacing Ui.xs, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.floatingBoons)
                :: List.map row gs.floatingBoons
            )


{-| The overcome line. When one is open it names the target and, for the
facilitator, offers "Call off"; otherwise the facilitator gets a button per
character to open one. Nothing shows for a player with no overcome running.
-}
overcomeBlock : Bool -> Maybe CharacterSheet -> List CharacterSheet -> Element Msg
overcomeBlock facilitator target characters =
    case target of
        Just t ->
            Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                (el [ Font.size 12, Font.semiBold ]
                    (text (Copy.overcomeWith (characterLabel t)))
                    :: Ui.onlyWhen facilitator
                        [ Ui.ghostButton { onPress = Just CancelOvercome, label = Copy.callOffOvercome } ]
                )

        Nothing ->
            if facilitator then
                Element.wrappedRow [ spacing Ui.xs, Element.centerY ]
                    (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.startOvercome)
                        :: List.map
                            (\c ->
                                Ui.ghostButton
                                    { onPress = Just (StartOvercome c.slot)
                                    , label = characterLabel c
                                    }
                            )
                            characters
                    )

            else
                none


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
