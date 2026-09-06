module View.Session exposing (untetherBanner, view)

{-| The Session card — running goal or the start-session field, the session
pool, the carried-Bane note, End session — plus the past-sessions list and the
table-wide untether (reckoning) banner that sits just below it.
-}

import Copy
import Element exposing (Element, el, fill, none, padding, px, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Format
import Time
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, characterLabel, glossaryTitle, inputAttrs, placeholder, stoneChip, tip)


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
                    , Element.wrappedRow [ spacing Ui.xs, Element.centerY ]
                        (tip "Session pool"
                            (el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.sessionPool))
                            :: List.map stoneChip s.pool
                        )
                    , if s.carriedBanes > 0 then
                        el [ Font.size 11, Font.color Ui.inkSoft ]
                            (text (Copy.carryingBanes s.carriedBanes))

                      else
                        none
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


{-| The reckoning line (section 19). While a character is untethered it shows
above the roll panel for the whole table; the facilitator gets a confirm-gated
"Resolve untether" that closes it once the scene has played out.
-}
untetherBanner : ViewContext -> Maybe String -> GameState -> Element Msg
untetherBanner ctx confirming gs =
    case gs.untether of
        Nothing ->
            none

        Just u ->
            let
                who =
                    characterAtSlot u.slot gs.characters
                        |> Maybe.map characterLabel
                        |> Maybe.withDefault (Copy.characterFallback u.slot)
            in
            Element.column
                [ width fill
                , spacing Ui.sm
                , padding Ui.md
                , Border.color Ui.danger
                , Border.width 1
                , Border.rounded 6
                ]
                [ Element.paragraph [ Font.size 13 ]
                    [ el [ Font.semiBold, Font.color Ui.danger ] (text (Copy.untetheredHeadline who))
                    , text (Copy.untetheredExplanation (String.toLower (Types.aspectLabel u.aspect)))
                    ]
                , if ctx.facilitator then
                    Ui.confirmButton
                        { armed = confirming == Just "resolve-untether"
                        , idle = Copy.resolveUntether
                        , confirm = Copy.resolveUntether
                        , onArm = RequestConfirm "resolve-untether"
                        , onConfirm = ResolveUntether
                        , onCancel = CancelConfirm
                        }

                  else
                    none
                ]


{-| The table's completed sessions, newest first: each one's start date, goal,
and how it landed. Hidden until a session has ended.
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
            , width (px 76)
            ]
            (text (Format.date zone s.startedAt))
        , Element.paragraph [ Font.size 12, spacing 3 ]
            [ text s.goal
            , el [ Font.color (verdictColor s.outcomeKind), Font.semiBold ]
                (text ("  " ++ verdictWord s.outcomeKind))
            ]
        ]


{-| The one-word verdict for the history row. The Worker classifies the stored
outcome sentence into `outcomeKind`, so the view no longer parses prose.
-}
verdictWord : SessionOutcome -> String
verdictWord outcome =
    case outcome of
        OutcomeMet ->
            Copy.verdictMet

        OutcomeFailed ->
            Copy.verdictFailed

        OutcomePartial ->
            Copy.verdictPartial


verdictColor : SessionOutcome -> Element.Color
verdictColor outcome =
    case outcome of
        OutcomeMet ->
            Ui.speakerColor 2

        OutcomeFailed ->
            Ui.danger

        OutcomePartial ->
            Ui.inkSoft
