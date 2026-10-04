module View.TopBar exposing (view)

{-| The status strip across the top of the page (roadmap 27, mockup 2a; the
ladder from 31.5): one line holding the running session's goal, the die
ladder, the junction controls, and who the viewer is.

The ladder is the roll button: `d6 d8 [d10] d12 d16 d20`, the current die
marked, and that one cell pressable — any player, or the facilitator, rolls the
junction with it. While a roll is pending it stops being a button and the
result sits beside the ladder (`Flow · 7`); a player sees **Alter**, the
facilitator **Reroll / Reject / Accept**. The facilitator's `‹` `›` either side
of the ladder step the die directly, at any time.

Session start / end / goal-edit controls — facilitator-only — open as a row
beneath the strip when the facilitator clicks the goal (`ToggleSessionControls`),
so the strip stays one line at rest.
-}

import Action exposing (Action(..))
import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Die exposing (Die)
import Html.Attributes
import Junction exposing (Junction)
import MoveRecord
import Outcome exposing (Outcome(..))
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, inputAttrs)


type alias Props =
    { confirming : Maybe String
    , newSessionGoal : String
    , goalEdit : String
    , expanded : Bool
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    Element.column [ width fill ]
        [ strip ctx props gs
        , if ctx.facilitator && props.expanded then
            sessionControls props gs.session

          else
            none
        ]


strip : ViewContext -> Props -> GameState -> Element Msg
strip ctx props gs =
    Element.row
        [ width fill
        , Element.height (Element.px 34)
        , Element.paddingXY 10 0
        , spacing 10
        , Element.centerY
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        [ goalSummary ctx.facilitator gs.session
        , ladder ctx gs
        , result gs.junction
        , controls ctx gs
        , who ctx
        ]


{-| The ladder, the current die marked and — while no roll is pending — the
button that rolls the junction. The facilitator's `‹` `›` sit either side.
-}
ladder : ViewContext -> GameState -> Element Msg
ladder ctx gs =
    let
        rung die =
            if die == gs.die then
                currentRung ctx gs.junction die

            else
                el [ Font.size 11, Font.color Ui.inkSoft ] (text (Die.label die))

        arrow direction glyph tip =
            Ui.withTip tip
                (Ui.linkButton
                    { onPress =
                        Die.step direction gs.die
                            |> Maybe.andThen (\_ -> Ui.press ctx.inflight (SteppingDie direction) (StepDie direction))
                    , label = glyph
                    }
                )
    in
    Element.row [ spacing 6, Element.centerY ]
        (Ui.onlyWhen ctx.facilitator [ arrow Die.Down "‹" Copy.stepDownTip ]
            ++ List.map rung Die.ladder
            ++ Ui.onlyWhen ctx.facilitator [ arrow Die.Up "›" Copy.stepUpTip ]
        )


{-| The current die: the roll button, or — while a roll is pending — a marked
cell that presses nothing.
-}
currentRung : ViewContext -> Maybe Junction -> Die -> Element Msg
currentRung ctx junction die =
    case junction of
        Nothing ->
            Ui.withTip (Copy.rollTip (Die.label die))
                (Ui.primaryButton
                    { onPress = Ui.press ctx.inflight RollingJunction PressJunction
                    , label = Die.label die
                    }
                )

        Just _ ->
            el
                [ Font.size 12
                , Font.semiBold
                , Element.paddingXY 6 2
                , Border.width 1
                , Border.color Ui.line
                , Border.rounded 4
                , Element.htmlAttribute (Html.Attributes.title (Copy.dieTip (Die.label die)))
                ]
                (text (Die.label die))


{-| The pending roll beside the ladder: `Flow · 7`, frictions in the danger
tone, criticals bold. Who rolled, on which die and how many rerolls is its
tooltip.
-}
result : Maybe Junction -> Element Msg
result junction =
    case junction of
        Just j ->
            el
                [ Font.size 12
                , Font.color (outcomeTone j.outcome)
                , if j.outcome == CriticalFlow || j.outcome == CriticalFriction then
                    Font.bold

                  else
                    Font.regular
                , Element.htmlAttribute
                    (Html.Attributes.title
                        (Copy.junctionRolled j.rolledBy ++ " " ++ Die.label j.die ++ " · " ++ Copy.rerollsNote j.rerolls)
                    )
                ]
                (text (Copy.rollResult (Outcome.label j.outcome) j.face))

        Nothing ->
            none


outcomeTone : Outcome -> Element.Color
outcomeTone outcome =
    case outcome of
        CriticalFriction ->
            Ui.danger

        Friction ->
            Ui.danger

        Flow ->
            Ui.accent

        CriticalFlow ->
            Ui.accent


{-| While a roll is pending: the facilitator's Reroll / Reject / Accept, or a
player's Alter. Nothing otherwise — the ladder is the roll button.
-}
controls : ViewContext -> GameState -> Element Msg
controls ctx gs =
    case gs.junction of
        Nothing ->
            none

        Just junction ->
            if ctx.facilitator then
                Element.row [ spacing Ui.xs ]
                    [ Ui.ghostButton
                        { onPress = Ui.press ctx.inflight RerollingJunction RerollJunction
                        , label = Copy.rerollButton
                        }
                    , Ui.ghostButton
                        { onPress = Ui.press ctx.inflight RejectingJunction RejectJunction
                        , label = Copy.reject
                        }
                    , Ui.primaryButton
                        { onPress = Ui.press ctx.inflight AcceptingJunction AcceptJunction
                        , label = Copy.accept
                        }
                    ]

            else
                alter ctx gs junction


{-| A player's Alter: two boons to reroll on the same die, once per character
per junction. Greyed, with the reason as its tooltip, when they cannot.
-}
alter : ViewContext -> GameState -> Junction -> Element Msg
alter ctx gs junction =
    let
        mine =
            gs.characters |> List.filter (\c -> c.ownerId /= Nothing && c.ownerId == ctx.myId) |> List.head

        ( enabled, tip ) =
            case mine of
                Nothing ->
                    ( False, Copy.claimASheetForMoves )

                Just ch ->
                    if Junction.hasAltered ch.slot junction then
                        ( False, Copy.alterAlreadyUsed )

                    else if ch.fate < Copy.alterCost then
                        ( False, Copy.alterNeedsBoons )

                    else
                        ( True, Copy.alterTip )
    in
    Ui.withTip tip
        (Ui.ghostButton
            { onPress =
                if enabled then
                    Ui.press ctx.inflight (MakingMove MoveRecord.Alter) MakeAlter

                else
                    Nothing
            , label = Copy.alterButton
            }
        )


{-| The viewer's name, marked `◈` for the facilitator; the tooltip spells out the
role.
-}
who : ViewContext -> Element msg
who ctx =
    el
        [ Font.size 11
        , Font.color Ui.inkSoft
        , Element.htmlAttribute
            (Html.Attributes.title
                (ctx.username
                    ++ " — "
                    ++ (if ctx.facilitator then
                            "Facilitator"

                        else
                            "Player"
                       )
                )
            )
        ]
        (text
            (if ctx.facilitator then
                ctx.username ++ " ◈"

             else
                ctx.username
            )
        )


{-| The at-rest goal (or "No session running"), on a single line that ellipsises
rather than wrapping. It doubles as the facilitator's expander toggle; for a
player it is read-only text, since there is nothing behind it for them to open.
-}
goalSummary : Bool -> Maybe Session -> Element Msg
goalSummary facilitator session =
    let
        label =
            case session of
                Just s ->
                    s.goal

                Nothing ->
                    Copy.noSessionRunning

        line =
            Ui.oneLine [ Font.size 12 ] label
    in
    if facilitator then
        Input.button
            [ width fill
            , Element.htmlAttribute (Html.Attributes.style "min-width" "0")
            , Element.htmlAttribute (Html.Attributes.title Copy.goalTip)
            ]
            { onPress = Just ToggleSessionControls, label = line }

    else
        line


{-| The facilitator's expanded controls: the running goal's editor and End
session, or the start-session field when none is running.
-}
sessionControls : Props -> Maybe Session -> Element Msg
sessionControls props session =
    Element.el
        [ width fill
        , Element.paddingXY 10 6
        , Background.color Ui.tint
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        (case session of
            Just s ->
                Element.row [ spacing Ui.sm, Element.centerY, width fill ]
                    [ goalEditor props.confirming props.goalEdit s.goal
                    , Ui.confirmButton
                        { armed = props.confirming == Just "end-session"
                        , idle = Copy.endSession
                        , confirm = Copy.endSession
                        , onArm = RequestConfirm "end-session"
                        , onConfirm = EndSession
                        , onCancel = CancelConfirm
                        }
                    ]

            Nothing ->
                Element.row [ spacing Ui.sm, width fill ]
                    [ Input.text
                        (inputAttrs ++ [ width fill, Ui.onEnter StartSession ])
                        { onChange = SessionGoalChanged
                        , text = props.newSessionGoal
                        , placeholder = Just (Input.placeholder [] (text Copy.sessionGoalPlaceholder))
                        , label = Input.labelHidden "Session goal"
                        }
                    , Ui.primaryButton { onPress = Just StartSession, label = Copy.startSession }
                    ]
        )


{-| The mid-session goal field. Shows the running goal until it is edited; the
confirm-gated Save writes it back. An empty or unchanged field leaves the goal
alone.
-}
goalEditor : Maybe String -> String -> String -> Element Msg
goalEditor confirming goalEdit currentGoal =
    let
        shown =
            if String.trim goalEdit == "" then
                currentGoal

            else
                goalEdit

        changed =
            String.trim shown /= "" && shown /= currentGoal
    in
    Element.row [ spacing Ui.sm, width fill ]
        [ Input.text
            (inputAttrs ++ [ width fill ])
            { onChange = SessionGoalEditChanged
            , text = shown
            , placeholder = Nothing
            , label = Input.labelHidden "Edit session goal"
            }
        , if changed then
            Ui.confirmButton
                { armed = confirming == Just "edit-goal"
                , idle = Copy.saveGoal
                , confirm = Copy.saveGoal
                , onArm = RequestConfirm "edit-goal"
                , onConfirm = SaveSessionGoal
                , onCancel = CancelConfirm
                }

          else
            none
        ]
