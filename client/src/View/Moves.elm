module View.Moves exposing (view)

{-| The Moves column (the middle of the three, above the session context), shown
once the viewer holds a sheet. Moves act at once (ADR 0002): Highlight and
Complicate name one of the character's aspects, Create carries the player's
words, Alter rerolls a pending junction. Highlight Context is made from the
context list itself (`View.ContextAspects`), open to anyone.

A move a player cannot make — unaffordable, at the top of the ladder, or locked
because the junction has been rolled — is disabled here, with the reason
beneath; the Worker refuses it too. Beside each move, the viewer's latest one
still open to undo carries an "undo" link.

Interim (roadmap 31.4): 31.5 replaces this column with split buttons on the
Sheet's aspects, the Create field under the context list, and undo links in the
log.

The facilitator has no sheet of their own, so they get a read-only look at
whichever character's slot is selected on the Sheet tab (`props.selectedSlot`).
-}

import Action exposing (Action(..))
import Aspect exposing (Aspect)
import Copy
import Die
import Element exposing (Element, el, fill, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Junction
import MoveRecord
import Types exposing (..)
import Ui
import View.Helpers
    exposing
        ( ViewContext
        , inputAttrs
        , myOpenMove
        , placeholder
        , tip
        , undoLink
        )


type alias Props =
    { createDraft : String
    , selectedSlot : Int
    }


{-| What each move costs, in boons (RULES.md "Moves").
-}
highlightCost : Int
highlightCost =
    1


createCost : Int
createCost =
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
            if ctx.facilitator then
                placeholder Copy.noCharacterSheets

            else
                el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.claimASheetForMoves)

        Just ch ->
            Ui.flat
                [ aspectMoveRow ctx gs ch MoveRecord.Highlight Copy.highlightButton MakeHighlight (highlightAvailability gs ch)
                , aspectMoveRow ctx gs ch MoveRecord.Complicate Copy.complicateButton MakeComplicate (preparation gs Available)
                , createRow ctx props gs ch
                , alterRow ctx gs ch
                , Element.row [ spacing Ui.sm ] [ undoLabelled ctx gs MoveRecord.HighlightContext ]
                ]


myOwnedSheet : Maybe String -> GameState -> Maybe CharacterSheet
myOwnedSheet myId gs =
    gs.characters
        |> List.filter (\c -> c.ownerId /= Nothing && c.ownerId == myId)
        |> List.head


{-| The facilitator's read-only stand-in for "my sheet": whichever character is
selected on the Sheet tab, falling back to the first one.
-}
selectedCharacter : Int -> GameState -> Maybe CharacterSheet
selectedCharacter slot gs =
    case List.filter (\c -> c.slot == slot) gs.characters of
        first :: _ ->
            Just first

        [] ->
            List.head gs.characters


{-| Whether a move's button can be pressed. `Off (Just reason)` names why
beneath the button; `Off Nothing` is off without comment.
-}
type Availability
    = Available
    | Off (Maybe String)


{-| Every move but Alter is made before the junction is rolled.
-}
preparation : GameState -> Availability -> Availability
preparation gs availability =
    case gs.junction of
        Just _ ->
            Off (Just Copy.movesLocked)

        Nothing ->
            availability


affordable : Int -> String -> CharacterSheet -> Availability
affordable cost reason ch =
    if ch.fate < cost then
        Off (Just reason)

    else
        Available


highlightAvailability : GameState -> CharacterSheet -> Availability
highlightAvailability gs ch =
    preparation gs
        (case ( affordable highlightCost Copy.needsABoon ch, Die.stepUp gs.die ) of
            ( Available, Nothing ) ->
                Off (Just Copy.dieAtTop)

            ( availability, _ ) ->
                availability
        )


{-| `Just msg` unless a control is off or the viewer is the facilitator
previewing someone else's moves, read-only.
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


reasonFor : Availability -> List (Element msg)
reasonFor availability =
    case availability of
        Off (Just reason) ->
            [ Element.paragraph [ Font.size 11, Font.color Ui.inkSoft ] [ text reason ] ]

        _ ->
            []


{-| The viewer's latest open move of `kind`, named, with its undo link.
-}
undoLabelled : ViewContext -> GameState -> MoveRecord.Kind -> Element Msg
undoLabelled ctx gs kind =
    case myOpenMove ctx kind gs of
        Just move ->
            Element.row [ spacing Ui.xs ]
                [ el [ Font.size 11, Font.color Ui.inkSoft ] (text (MoveRecord.kindLabel kind))
                , undoLink (Just move)
                ]

        Nothing ->
            Element.none


{-| A move made on one of the character's aspects: its name, then a button per
written aspect, then the undo link and why it is off.
-}
aspectMoveRow : ViewContext -> GameState -> CharacterSheet -> MoveRecord.Kind -> String -> (Aspect -> Msg) -> Availability -> Element Msg
aspectMoveRow ctx gs ch kind label toMsg availability =
    let
        written =
            List.filter (\a -> String.trim (aspectText a ch) /= "") Aspect.all
    in
    Element.column [ spacing Ui.xs, width fill ]
        (Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
            (tip label (el [ Font.size 12, Font.semiBold ] (text label))
                :: List.map
                    (\aspect ->
                        Ui.ghostButton
                            { onPress = movePress ctx availability (MakingMove kind) (toMsg aspect)
                            , label = Aspect.label aspect
                            }
                    )
                    written
                ++ [ undoLink (myOpenMove ctx kind gs) ]
            )
            :: reasonFor availability
        )


aspectText : Aspect -> CharacterSheet -> String
aspectText aspect ch =
    case aspect of
        Aspect.Archetype ->
            ch.archetype

        Aspect.Desire ->
            ch.desire

        Aspect.Quest ->
            ch.quest


{-| The button with the wording field beside it, filling the rest of the line.
-}
createRow : ViewContext -> Props -> GameState -> CharacterSheet -> Element Msg
createRow ctx props gs ch =
    let
        availability =
            preparation gs (affordable createCost Copy.needsABoon ch)
    in
    Element.column [ spacing Ui.xs, width fill ]
        (Element.row [ spacing Ui.sm, width fill, Element.centerY ]
            [ tip Copy.createButton
                (Ui.ghostButton
                    { onPress = movePress ctx availability (MakingMove MoveRecord.Create) MakeCreate
                    , label = Copy.createButton
                    }
                )
            , Input.text
                (inputAttrs ++ [ width fill, Ui.onEnter MakeCreate ])
                { onChange = CreateDraftChanged
                , text = props.createDraft
                , placeholder = Just (Input.placeholder [] (text Copy.createPlaceholder))
                , label = Input.labelHidden "Create"
                }
            , undoLink (myOpenMove ctx MoveRecord.Create gs)
            ]
            :: reasonFor availability
        )


{-| Alter is shown always but pressable only while a junction is pending, once
per character per junction.
-}
alterRow : ViewContext -> GameState -> CharacterSheet -> Element Msg
alterRow ctx gs ch =
    let
        availability =
            case gs.junction of
                Nothing ->
                    Off Nothing

                Just junction ->
                    if Junction.hasAltered ch.slot junction then
                        Off (Just Copy.alterAlreadyUsed)

                    else
                        affordable alterCost Copy.alterNeedsBoons ch
    in
    Element.column [ spacing Ui.xs ]
        (Element.row [ spacing Ui.sm, Element.centerY ]
            [ tip Copy.alterButton
                (Ui.ghostButton
                    { onPress = movePress ctx availability (MakingMove MoveRecord.Alter) MakeAlter
                    , label = Copy.alterButton
                    }
                )
            , undoLink (myOpenMove ctx MoveRecord.Alter gs)
            ]
            :: reasonFor availability
        )
