module View.TopBar exposing (view)

{-| The persistent bar above the two panels: the running session's goal, and the
"stage" for the shared Overcome (roadmap 26.3; the "B" variant of a throwaway
prototype, kept on `proto/section-26-3-topbar`).

The stage shows the shared pool as a row of stones. Pressing **Overcome** (open
to any player) draws two of them: while that roll is pending they sit lifted out
of the pool beside it, with who rolled and how many rerolls. The facilitator's
Reroll / Reject / Accept are here too; a player sees that they are waiting.
Alter Fate is a player move, so it lives in the Moves card, and its proposal in
the facilitator's queue — not here.

Session start / end / goal-edit controls — facilitator-only — sit behind a ▸/▾
expander (`ToggleSessionControls`), so the bar stays compact at rest.
-}

import Action exposing (Action(..))
import Copy
import Element exposing (Element, centerX, el, fill, none, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Roll exposing (Stone(..))
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, inputAttrs, tipAttrs)


type alias Props =
    { confirming : Maybe String
    , newSessionGoal : String
    , goalEdit : String
    , expanded : Bool
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    Element.column
        [ width fill
        , spacing Ui.sm
        , Element.paddingXY Ui.lg Ui.md
        , Background.color Ui.wash
        , Border.rounded 10
        , Border.color Ui.line
        , Border.width 1
        ]
        [ Element.row [ spacing Ui.md, Element.centerY, width fill ]
            [ goalSummary ctx.facilitator props.expanded gs.session
            , el [ Font.size 11, Font.color Ui.inkSoft ] (text (Copy.bagOf (List.length gs.stonePool)))
            ]
        , if ctx.facilitator && props.expanded then
            sessionControls props gs.session

          else
            none
        , stage ctx gs
        ]


{-| The pool, the pending draw lifted out of it, and the controls for whichever
state the Overcome is in.
-}
stage : ViewContext -> GameState -> Element Msg
stage ctx gs =
    let
        drawn =
            gs.overcome |> Maybe.map .stones |> Maybe.withDefault []

        inPool =
            Roll.without drawn gs.stonePool
    in
    Element.column [ centerX, spacing Ui.sm ]
        [ Element.row [ centerX, spacing Ui.xl ]
            [ Element.column [ spacing Ui.xs ]
                [ el [ Font.size 11, Font.color Ui.inkSoft, centerX ] (text Copy.thePool)
                , Element.row [ spacing Ui.sm, centerX, Element.height (Element.px 44) ]
                    (List.map poolStone inPool)
                ]
            , case gs.overcome of
                Just o ->
                    Element.column [ spacing Ui.xs ]
                        [ el [ Font.size 11, Font.color Ui.inkSoft, centerX ]
                            (text (Copy.overcomeDrew o.rolledBy ++ "  ·  " ++ Copy.rerollsNote o.rerolls))
                        , Element.row [ spacing Ui.sm, centerX ]
                            (List.map (\stone -> Ui.liftedStone (stoneFill stone)) o.stones)
                        ]

                Nothing ->
                    none
            ]
        , el [ centerX ] (controls ctx gs.overcome)
        ]


controls : ViewContext -> Maybe Overcome -> Element Msg
controls ctx overcome =
    case overcome of
        Nothing ->
            Ui.primaryButton
                { onPress = Ui.press ctx.inflight RollingOvercome PressOvercome
                , label = Copy.overcome
                }

        Just _ ->
            if ctx.facilitator then
                Element.row [ spacing Ui.sm ]
                    [ Ui.ghostButton
                        { onPress = Ui.press ctx.inflight RerollingOvercome RerollOvercome
                        , label = Copy.rerollButton
                        }
                    , Ui.ghostButton
                        { onPress = Ui.press ctx.inflight RejectingOvercome RejectOvercome
                        , label = Copy.reject
                        }
                    , Ui.primaryButton
                        { onPress = Ui.press ctx.inflight AcceptingOvercome AcceptOvercome
                        , label = Copy.accept
                        }
                    ]

            else
                el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.waitingForFacilitator)


poolStone : Stone -> Element msg
poolStone stone =
    Ui.stoneCircle (stoneFill stone) False 30


stoneFill : Stone -> Element.Color
stoneFill stone =
    case stone of
        Boon ->
            Ui.boonFill

        Bane ->
            Ui.baneFill


{-| The at-rest line: the goal (or "No session running"), doubling as the
facilitator's expander toggle. Read-only text for a player — there is nothing
behind it for them to open.
-}
goalSummary : Bool -> Bool -> Maybe Session -> Element Msg
goalSummary facilitator expanded session =
    let
        label =
            case session of
                Just s ->
                    Copy.goalLabel ++ s.goal

                Nothing ->
                    Copy.noSessionRunning
    in
    if facilitator then
        Input.button (width fill :: tipAttrs "Session")
            { onPress = Just ToggleSessionControls
            , label =
                Element.row [ spacing Ui.sm, width fill ]
                    [ el [ Font.size 11, Font.color Ui.inkSoft ]
                        (text
                            (if expanded then
                                "▾"

                             else
                                "▸"
                            )
                        )
                    , Element.paragraph [ Font.size 13, width fill ] [ text label ]
                    ]
            }

    else
        Element.paragraph (Font.size 13 :: width fill :: tipAttrs "Session") [ text label ]


{-| The facilitator's expanded controls: the running goal's editor and End
session, or the start-session field when none is running.
-}
sessionControls : Props -> Maybe Session -> Element Msg
sessionControls props session =
    Element.el [ Element.paddingEach { top = Ui.xs, right = 0, bottom = 0, left = Ui.lg } ]
        (case session of
            Just s ->
                Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
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
