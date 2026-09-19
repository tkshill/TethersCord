module View.Moves exposing (view)

{-| The Moves tool (roadmap section 27, the ▲ tab), shown once the viewer holds a sheet (roadmap 26.3): a real
button for each player move — Highlight, Complicate, Add Detail, Alter Fate and
Use Session Boon. Each one queues a proposal for the facilitator; nothing lands
until they accept it, and the cost of a move is paid only then (`RULES.md`).

A move a player cannot afford is disabled here rather than refused after the
fact: the Worker checks the cost when the proposal is raised and again when it is
accepted, but the button says so first. Overcome is not one of these — it needs
no approval and lives on the status strip in `View.TopBar`.

The facilitator has no sheet of their own, so they get a read-only look at
whichever character's slot is selected on the Sheet tab (`props.selectedSlot`)
instead — every button here is inert for them, so they can see the same moves a
player sees without being able to raise one on a player's behalf.
-}

import Action exposing (Action(..))
import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Kind
import Roll exposing (Stone(..))
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
        , placeholder
        , tip
        )


type alias Props =
    { addDetailDraft : String
    , selectedSlot : Int
    }


{-| What each move costs the proposer, in boons, on approval.
-}
highlightCost : Int
highlightCost =
    1


addDetailCost : Int
addDetailCost =
    1


alterCost : Int
alterCost =
    2


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    let
        target =
            if ctx.facilitator then
                selectedCharacter props.selectedSlot gs

            else
                myOwnedSheet ctx.myId gs
    in
    case target of
        Nothing ->
            -- The facilitator sees this only when no sheets exist at all; a
            -- player who has not claimed one is told why it is empty.
            if ctx.facilitator then
                placeholder Copy.noCharacterSheets

            else
                el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.claimASheetForMoves)

        Just ch ->
            Ui.flat
                [ highlightRow ctx gs ch
                , complicateRow ctx gs ch
                , addDetailRow ctx props gs ch
                , alterRow ctx gs ch
                , useSessionBoonRow ctx gs
                ]


myOwnedSheet : Maybe String -> GameState -> Maybe CharacterSheet
myOwnedSheet myId gs =
    gs.characters
        |> List.filter (\c -> c.ownerId /= Nothing && c.ownerId == myId)
        |> List.head


{-| The facilitator's read-only stand-in for "my sheet": whichever character is
selected on the Sheet tab, falling back to the first one (same rule as
`View.Characters`, so flipping the Sheet tab's slot tabs also flips this view).
-}
selectedCharacter : Int -> GameState -> Maybe CharacterSheet
selectedCharacter slot gs =
    case List.filter (\c -> c.slot == slot) gs.characters of
        first :: _ ->
            Just first

        [] ->
            List.head gs.characters


{-| A move's block: its name (with the glossary tooltip) and a one-line blurb,
then whatever controls it has.
-}
moveBlock : String -> String -> List (Element Msg) -> Element Msg
moveBlock name blurb controls =
    Element.column
        [ spacing Ui.xs
        , width fill
        , Element.paddingEach { top = 0, right = 0, bottom = Ui.sm, left = 0 }
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        (Element.paragraph [ Font.size 12 ]
            [ tip name (el [ Font.semiBold ] (text name))
            , el [ Font.color Ui.inkSoft ] (text ("  " ++ blurb))
            ]
            :: controls
        )


{-| `Just msg` unless a control has a reason it is off (`whyNot`) or the viewer
is the facilitator previewing someone else's Moves tool, read-only.
-}
movePress : ViewContext -> Action -> Msg -> Maybe Msg
movePress ctx action msg =
    if ctx.facilitator then
        Nothing

    else
        Ui.press ctx.inflight action msg


{-| A button that names why it is off, beneath it, when it is.
-}
moveButton : ViewContext -> Action -> Msg -> String -> Maybe String -> Element Msg
moveButton ctx action msg label whyNot =
    Element.column [ spacing Ui.xs ]
        [ Ui.ghostButton
            { onPress =
                case whyNot of
                    Just _ ->
                        Nothing

                    Nothing ->
                        movePress ctx action msg
            , label = label
            }
        , case whyNot of
            Just reason ->
                el [ Font.size 11, Font.color Ui.inkSoft ] (text reason)

            Nothing ->
                none
        ]


pendingFor : ViewContext -> GameState -> Kind.ProposalKind -> List (Element Msg)
pendingFor ctx gs kind =
    pendingHint (countProposals ctx.myId kind gs.proposals) (latestProposalId ctx.myId kind gs.proposals)


highlightRow : ViewContext -> GameState -> CharacterSheet -> Element Msg
highlightRow ctx gs ch =
    moveBlock "Highlight"
        Copy.highlightBlurb
        [ Element.row [ spacing Ui.sm, Element.centerY ]
            (moveButton ctx
                (RaisingMove Kind.Highlight)
                ProposeHighlight
                Copy.highlightButton
                (if ch.fate < highlightCost then
                    Just Copy.needsABoon

                 else
                    Nothing
                )
                :: pendingFor ctx gs Kind.Highlight
            )
        ]


{-| One button per other claimed sheet: naming a target is what proposes it.
-}
complicateRow : ViewContext -> GameState -> CharacterSheet -> Element Msg
complicateRow ctx gs ch =
    let
        targets =
            gs.characters
                |> List.filter (\c -> c.slot /= ch.slot && c.ownerId /= Nothing)
    in
    moveBlock "Complicate"
        Copy.complicateBlurb
        [ if List.isEmpty targets then
            el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.noOtherPlayers)

          else
            Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                (List.map
                    (\c ->
                        Ui.ghostButton
                            { onPress = movePress ctx (RaisingMove Kind.Complicate) (ProposeComplicate c.slot)
                            , label = characterLabel c
                            }
                    )
                    targets
                    ++ pendingFor ctx gs Kind.Complicate
                )
        ]


addDetailRow : ViewContext -> Props -> GameState -> CharacterSheet -> Element Msg
addDetailRow ctx props gs ch =
    moveBlock "Add Detail"
        Copy.addDetailBlurb
        [ Input.text
            (inputAttrs ++ [ width fill, Ui.onEnter ProposeAddDetail ])
            { onChange = AddDetailDraftChanged
            , text = props.addDetailDraft
            , placeholder = Just (Input.placeholder [] (text Copy.addDetailPlaceholder))
            , label = Input.labelHidden "Suggested detail"
            }
        , Element.row [ spacing Ui.sm, Element.centerY ]
            (moveButton ctx
                (RaisingMove Kind.AddDetail)
                ProposeAddDetail
                Copy.addDetailButton
                (if ch.fate < addDetailCost then
                    Just Copy.needsABoon

                 else
                    Nothing
                )
                :: pendingFor ctx gs Kind.AddDetail
            )
        ]


{-| Alter Fate exists only while an Overcome is pending, so the block is absent
otherwise. It is off for a player who cannot pay, who has already altered this
Overcome, or while another Alter Fate is waiting (one at a time).
-}
alterRow : ViewContext -> GameState -> CharacterSheet -> Element Msg
alterRow ctx gs ch =
    case gs.overcome of
        Nothing ->
            none

        Just overcome ->
            let
                whyNot =
                    if List.member ch.slot overcome.alteredSlots then
                        Just Copy.alterAlreadyUsed

                    else if List.any (\p -> p.kind == Kind.Alter) gs.proposals then
                        Just Copy.alterAlreadyProposed

                    else if ch.fate < alterCost then
                        Just Copy.alterNeedsBoons

                    else
                        Nothing
            in
            moveBlock "Alter Fate"
                Copy.alterBlurb
                [ Element.row [ spacing Ui.sm, Element.centerY ]
                    (moveButton ctx
                        (RaisingMove Kind.Alter)
                        ProposeAlter
                        Copy.alterButton
                        whyNot
                        :: pendingFor ctx gs Kind.Alter
                    )
                ]


{-| Each unspent session *boon*. Session banes are the facilitator's to use.
-}
useSessionBoonRow : ViewContext -> GameState -> Element Msg
useSessionBoonRow ctx gs =
    let
        spendable =
            gs.sessionAspects
                |> List.filter (\a -> a.kind == Boon && not a.consumed)
    in
    moveBlock "Session boon"
        Copy.useSessionBoonBlurb
        [ if List.isEmpty spendable then
            el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.noSessionBoons)

          else
            Element.column [ spacing Ui.xs, width fill ]
                (List.map
                    (\a ->
                        Element.row [ spacing Ui.sm, Element.centerY, width fill ]
                            [ Ui.ghostButton
                                { onPress = movePress ctx (RaisingMove Kind.UseSessionBoon) (ProposeUseSessionBoon a.id)
                                , label = Copy.useButton
                                }
                            , Element.paragraph [ Font.size 12 ] [ text a.text ]
                            ]
                    )
                    spendable
                )
        , Element.row [ spacing Ui.sm ] (pendingFor ctx gs Kind.UseSessionBoon)
        ]
