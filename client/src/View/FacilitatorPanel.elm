module View.FacilitatorPanel exposing (view)

{-| The facilitator-only panel in the left column: direct pool edits (23.2) and
the queue of player moves awaiting a decision. Renders nothing for a player; the
Characters card below it is the one they share. Collapsible as one of the left
panel's three accordion sections (24); its header carries a count of waiting
proposals, so collapsing it does not hide that one is waiting (roadmap 26.3).

The Overcome — roll, reroll, accept, reject — is not here: it is shared table
state, so it lives on the stage in `View.TopBar`.
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
import View.Helpers exposing (ViewContext, accordionHeaderWith, characterLabel, inputAttrs)


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
            (accordionHeaderWith props.open
                (Ui.sectionTitle Copy.facilitatorPanelTitle)
                (ToggleLeftSection FacilitatorSection)
                (waitingNote (List.length gs.proposals))
                :: (if props.open then
                        [ poolControls ctx.inflight
                        , proposalsPanel ctx.inflight props.drafts gs
                        ]

                    else
                        []
                   )
            )


waitingNote : Int -> Element msg
waitingNote n =
    if n <= 0 then
        none

    else
        el [ Font.size 11, Font.color Ui.accent ] (text (Copy.proposalsWaiting n))


{-| Direct hand-edit of the shared pool (23.2): add or remove one Boon or one
Bane at a time, independent of every other action.
-}
poolControls : List Action -> Element Msg
poolControls inflight =
    Element.wrappedRow [ spacing Ui.md, Element.centerY ] [ stoneControl inflight Boon, stoneControl inflight Bane ]


stoneControl : List Action -> Stone -> Element Msg
stoneControl inflight stone =
    Element.row [ spacing Ui.xs, Element.centerY ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text (stoneLabel stone))
        , Ui.ghostButton
            { onPress = Ui.press inflight (RemovingStone stone) (RemoveStone stone)
            , label = "−"
            }
        , Ui.ghostButton
            { onPress = Ui.press inflight (AddingStone stone) (AddStone stone)
            , label = "+"
            }
        ]


{-| The queue of player moves awaiting a decision. Hidden when empty. `drafts`
holds the wording the facilitator has typed for an Add Detail, keyed by proposal
id so the rows do not share one field.
-}
proposalsPanel : List Action -> Dict String String -> GameState -> Element Msg
proposalsPanel inflight drafts gs =
    if List.isEmpty gs.proposals then
        none

    else
        Element.column [ spacing Ui.sm, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.proposalsTitle)
                :: List.map (proposalRow inflight drafts gs) gs.proposals
            )


proposalRow : List Action -> Dict String String -> GameState -> Proposal -> Element Msg
proposalRow inflight drafts gs p =
    let
        isAddDetail =
            p.kind == Kind.AddDetail

        -- The field opens on the player's suggestion, if they gave one, and the
        -- facilitator edits it; blank falls back on the Worker's side.
        draft =
            Dict.get p.id drafts |> Maybe.withDefault (Maybe.withDefault "" p.text)

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
                        if busy then
                            Nothing

                        else
                            Just (AcceptProposal p.id)
                    , label = Copy.accept
                    }
                ]
    in
    Element.column [ width fill, spacing Ui.xs ]
        [ Element.wrappedRow [ width fill, spacing Ui.sm, Element.centerY ]
            [ Element.paragraph [ Font.size 12 ]
                [ text (proposerLabel gs p ++ " — " ++ describeProposal gs p) ]
            , controls
            ]
        , if isAddDetail then
            Input.text
                (inputAttrs ++ [ width fill ])
                { onChange = ProposalDraftChanged p.id
                , text = draft
                , placeholder = Just (Input.placeholder [] (text Copy.sessionAspectContextPlaceholder))
                , label = Input.labelHidden "Session boon wording"
                }

          else
            none
        ]


{-| The proposer's character name where they hold a sheet, else their Discord name.
-}
proposerLabel : GameState -> Proposal -> String
proposerLabel gs p =
    p.slot
        |> Maybe.andThen (\s -> characterAtSlot s gs.characters)
        |> Maybe.map characterLabel
        |> Maybe.withDefault p.proposerName


describeProposal : GameState -> Proposal -> String
describeProposal gs p =
    case p.kind of
        Kind.Highlight ->
            Copy.proposalHighlight

        Kind.Alter ->
            Copy.proposalAlter

        Kind.AddDetail ->
            Copy.proposalAddDetail

        Kind.Complicate ->
            Copy.proposalComplicateOn
                (p.targetSlot
                    |> Maybe.andThen (\s -> characterAtSlot s gs.characters)
                    |> Maybe.map characterLabel
                    |> Maybe.withDefault Copy.proposalComplicateFallback
                )

        Kind.UseSessionBoon ->
            p.sessionAspectId
                |> Maybe.andThen (\id -> gs.sessionAspects |> List.filter (\a -> a.id == id) |> List.head)
                |> Maybe.map .text
                |> Maybe.withDefault Copy.proposalUseSessionBoonGone
                |> Copy.proposalUseSessionBoon
