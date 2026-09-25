module View.Moves exposing (view)

{-| The Moves column (the middle of the three, above the session context), shown
once the viewer holds a sheet (roadmap 26.3): a real button for each player
move. Highlight, Complicate and Alter Fate share the first line; Add Detail and
its suggestion field the second; Use Session Boon, one row per unspent session
boon, follows. Each one queues a proposal for the facilitator; nothing lands
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
import Element exposing (Element, el, fill, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Kind
import Roll exposing (Stone(..))
import Types exposing (..)
import Ui
import View.Helpers
    exposing
        ( ViewContext
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
                [ Element.wrappedRow [ spacing Ui.sm, width fill ]
                    [ highlightMove ctx gs ch
                    , complicateMove ctx gs
                    , alterMove ctx gs ch
                    ]
                , addDetailRow ctx props gs ch
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


{-| Whether a move's button can be pressed. `Off (Just reason)` names why
beneath the button; `Off Nothing` is off without comment (Alter Fate outside an
Overcome, where the button's tooltip already says when it applies).
-}
type Availability
    = Available
    | Off (Maybe String)


{-| `Just msg` unless a control is off or the viewer is the facilitator
previewing someone else's Moves, read-only.
-}
movePress : ViewContext -> Availability -> Action -> Msg -> Maybe Msg
movePress ctx availability action msg =
    case availability of
        Off _ ->
            Nothing

        Available ->
            if ctx.facilitator then
                Nothing

            else
                Ui.press ctx.inflight action msg


moveButton : ViewContext -> Availability -> Action -> Msg -> String -> Element Msg
moveButton ctx availability action msg label =
    tip label
        (Ui.ghostButton
            { onPress = movePress ctx availability action msg
            , label = label
            }
        )


{-| What sits under a move's control: why it is off, if it is, and the
viewer's pending proposals of that kind with a withdraw link.
-}
moveNotes : ViewContext -> GameState -> Availability -> Kind.ProposalKind -> List (Element Msg)
moveNotes ctx gs availability kind =
    (case availability of
        Off (Just reason) ->
            [ Element.paragraph [ Font.size 11, Font.color Ui.inkSoft ] [ text reason ] ]

        _ ->
            []
    )
        ++ (case pendingFor ctx gs kind of
                [] ->
                    []

                pending ->
                    [ Element.row [ spacing Ui.sm ] pending ]
           )


{-| One of the first line's moves: its button over its notes.
-}
compactMove : ViewContext -> GameState -> Availability -> Action -> Msg -> String -> Kind.ProposalKind -> Element Msg
compactMove ctx gs availability action msg label kind =
    Element.column [ spacing Ui.xs, Element.alignTop ]
        (moveButton ctx availability action msg label :: moveNotes ctx gs availability kind)


pendingFor : ViewContext -> GameState -> Kind.ProposalKind -> List (Element Msg)
pendingFor ctx gs kind =
    pendingHint (countProposals ctx.myId kind gs.proposals) (latestProposalId ctx.myId kind gs.proposals)


affordable : Int -> String -> CharacterSheet -> Availability
affordable cost reason ch =
    if ch.fate < cost then
        Off (Just reason)

    else
        Available


highlightMove : ViewContext -> GameState -> CharacterSheet -> Element Msg
highlightMove ctx gs ch =
    compactMove ctx
        gs
        (affordable highlightCost Copy.needsABoon ch)
        (RaisingMove Kind.Highlight)
        ProposeHighlight
        Copy.highlightButton
        Kind.Highlight


{-| Free, and always for the proposer's own character.
-}
complicateMove : ViewContext -> GameState -> Element Msg
complicateMove ctx gs =
    compactMove ctx
        gs
        Available
        (RaisingMove Kind.Complicate)
        ProposeComplicate
        Copy.complicateButton
        Kind.Complicate


{-| Alter Fate is always shown but pressable only while an Overcome is pending.
It is also off for a player who cannot pay, who has already altered this
Overcome, or while another Alter Fate is waiting (one at a time).
-}
alterMove : ViewContext -> GameState -> CharacterSheet -> Element Msg
alterMove ctx gs ch =
    let
        availability =
            case gs.overcome of
                Nothing ->
                    Off Nothing

                Just overcome ->
                    if List.member ch.slot overcome.alteredSlots then
                        Off (Just Copy.alterAlreadyUsed)

                    else if List.any (\p -> p.kind == Kind.Alter) gs.proposals then
                        Off (Just Copy.alterAlreadyProposed)

                    else
                        affordable alterCost Copy.alterNeedsBoons ch
    in
    compactMove ctx gs availability (RaisingMove Kind.Alter) ProposeAlter Copy.alterButton Kind.Alter


{-| The button with the suggestion field beside it, filling the rest of the line.
-}
addDetailRow : ViewContext -> Props -> GameState -> CharacterSheet -> Element Msg
addDetailRow ctx props gs ch =
    let
        availability =
            affordable addDetailCost Copy.needsABoon ch
    in
    Element.column [ spacing Ui.xs, width fill ]
        (Element.row [ spacing Ui.sm, width fill, Element.centerY ]
            [ moveButton ctx availability (RaisingMove Kind.AddDetail) ProposeAddDetail Copy.addDetailButton
            , Input.text
                (inputAttrs ++ [ width fill, Ui.onEnter ProposeAddDetail ])
                { onChange = AddDetailDraftChanged
                , text = props.addDetailDraft
                , placeholder = Just (Input.placeholder [] (text Copy.addDetailPlaceholder))
                , label = Input.labelHidden "Suggested detail"
                }
            ]
            :: moveNotes ctx gs availability Kind.AddDetail
        )


{-| Each unspent session *boon*. Session banes are the facilitator's to use.
-}
useSessionBoonRow : ViewContext -> GameState -> Element Msg
useSessionBoonRow ctx gs =
    let
        spendable =
            gs.sessionAspects
                |> List.filter (\a -> a.kind == Boon && not a.consumed)
    in
    Element.column [ spacing Ui.xs, width fill ]
        [ if List.isEmpty spendable then
            el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.noSessionBoons)

          else
            Element.column [ spacing Ui.xs, width fill ]
                (List.map
                    (\a ->
                        Element.row [ spacing Ui.sm, Element.centerY, width fill ]
                            [ tip "Session boon"
                                (Ui.ghostButton
                                    { onPress = movePress ctx Available (RaisingMove Kind.UseSessionBoon) (ProposeUseSessionBoon a.id)
                                    , label = Copy.useSessionBoonButton
                                    }
                                )
                            , Element.paragraph [ Font.size 12 ] [ text a.text ]
                            ]
                    )
                    spendable
                )
        , Element.row [ spacing Ui.sm ] (pendingFor ctx gs Kind.UseSessionBoon)
        ]
