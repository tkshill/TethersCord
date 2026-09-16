module View.Session exposing (view)

{-| The Session card — running goal or the start-session field, End session —
plus the past-sessions list. The stone pool now lives entirely on the Stones
card (`View.Stones`); a session's goal is free text with no roll or verdict
tied to ending it.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Format
import Time
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, glossaryTitle, inputAttrs, placeholder)


type alias Props =
    { confirming : Maybe String
    , newSessionGoal : String
    , goalEdit : String
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    Ui.card
        [ glossaryTitle Copy.sessionTitle "Session"
        , case gs.session of
            Just s ->
                Element.column [ spacing Ui.sm, width fill ]
                    [ if ctx.facilitator then
                        goalEditor props.confirming props.goalEdit s.goal

                      else
                        Element.paragraph [ Font.size 13 ]
                            [ el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.goalLabel)
                            , text s.goal
                            ]
                    , if ctx.facilitator then
                        Ui.confirmButton
                            { armed = props.confirming == Just "end-session"
                            , idle = Copy.endSession
                            , confirm = Copy.endSession
                            , onArm = RequestConfirm "end-session"
                            , onConfirm = EndSession
                            , onCancel = CancelConfirm
                            }

                      else
                        none
                    ]

            Nothing ->
                if ctx.facilitator then
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

                else
                    placeholder Copy.noSessionRunning
        , sessionHistoryView ctx.zone gs.sessionHistory
        ]


{-| The facilitator's mid-session goal field. Shows the running goal until it is
edited; the confirm-gated Save writes it back. An empty or unchanged field
leaves the goal alone.
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


{-| The table's completed sessions, newest first: each one's start date and
goal. Hidden until a session has ended.
-}
sessionHistoryView : Time.Zone -> List SessionSummary -> Element msg
sessionHistoryView zone history =
    if List.isEmpty history then
        none

    else
        Element.column [ spacing Ui.xs, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.pastSessions)
                :: List.map (pastSessionRow zone) history
            )


pastSessionRow : Time.Zone -> SessionSummary -> Element msg
pastSessionRow zone s =
    Element.row [ width fill, spacing Ui.sm ]
        [ el
            [ Font.family Ui.mono
            , Font.size 11
            , Font.color Ui.inkSoft
            , Element.alignTop
            , Element.width (Element.px 76)
            ]
            (text (Format.date zone s.startedAt))
        , Element.paragraph [ Font.size 12 ] [ text s.goal ]
        ]
