module View.TopBar exposing (view)

{-| The persistent bar above the three columns (roadmap section 23.6): the
running session's goal and the shared stone pool, moved here from the old
Session / Stones cards without a new data source (`gs.session`,
`gs.stonePool`). Session start / end / goal-edit controls — facilitator-only —
sit behind a ▸/▾ expander (`ToggleSessionControls`) rather than full-width, so
the bar stays one line at rest.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, inputAttrs, stoneChip, tipAttrs)


type alias Props =
    { confirming : Maybe String
    , newSessionGoal : String
    , goalEdit : String
    , expanded : Bool
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    let
        committed =
            List.foldl (\c acc -> acc + c.count) 0 gs.committedBoons
    in
    Element.column [ spacing Ui.sm, width fill ]
        [ Element.row [ spacing Ui.md, Element.centerY, width fill ]
            [ goalSummary ctx.facilitator props.expanded gs.session
            , Element.row [ spacing Ui.xs, Element.centerY ]
                (List.map stoneChip gs.stonePool
                    ++ List.repeat committed (Ui.highlightedStoneChip Ui.boonFill Copy.highlightedChip)
                    ++ [ el [ Font.size 11, Font.color Ui.inkSoft ]
                            (text (Copy.bagOf (List.length gs.stonePool + committed)))
                       ]
                )
            ]
        , if ctx.facilitator && props.expanded then
            sessionControls props gs.session

          else
            none
        ]


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
