module View.Session exposing (untetherBanner, view)

{-| The Session card — running goal or the start-session field, the session
pool, the carried-Bane note, End session — plus the past-sessions list and the
table-wide untether (reckoning) banner that sits just below it.
-}

import Element exposing (Element, el, fill, none, padding, px, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Format
import Time
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, characterLabel, inputAttrs, placeholder, stoneChip)


type alias Props =
    { confirming : Maybe String
    , newSessionGoal : String
    , goalEdit : String
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    Ui.card
        [ Ui.sectionTitle "Session"
        , case gs.session of
            Just s ->
                Element.column [ spacing Ui.sm, width fill ]
                    [ if ctx.facilitator then
                        goalEditor props.confirming props.goalEdit s.goal

                      else
                        Element.paragraph [ Font.size 13 ]
                            [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Goal  ")
                            , text s.goal
                            ]
                    , Element.wrappedRow [ spacing Ui.xs, Element.centerY ]
                        (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Session pool")
                            :: List.map stoneChip s.pool
                        )
                    , if s.carriedBanes > 0 then
                        el [ Font.size 11, Font.color Ui.inkSoft ]
                            (text
                                ("Carrying "
                                    ++ String.fromInt s.carriedBanes
                                    ++ " "
                                    ++ Format.pluralize s.carriedBanes "Bane"
                                    ++ " in from the last session"
                                )
                            )

                      else
                        none
                    , if ctx.facilitator then
                        Ui.confirmButton
                            { armed = props.confirming == Just "end-session"
                            , idle = "End session"
                            , confirm = "End session"
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
                            , placeholder = Just (Input.placeholder [] (text "Session goal…"))
                            , label = Input.labelHidden "Session goal"
                            }
                        , Ui.primaryButton { onPress = Just StartSession, label = "Start session" }
                        ]

                else
                    placeholder "No session running."
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
                , idle = "Save goal"
                , confirm = "Save goal"
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
                        |> Maybe.withDefault ("Character " ++ String.fromInt (u.slot + 1))
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
                    [ el [ Font.semiBold, Font.color Ui.danger ] (text (who ++ " is untethered"))
                    , text
                        (" on their "
                            ++ String.toLower (Types.aspectLabel u.aspect)
                            ++ " — the reckoning resolves by the end of the following session, and afterward the aspect is rewritten or replaced."
                        )
                    ]
                , if ctx.facilitator then
                    Ui.confirmButton
                        { armed = confirming == Just "resolve-untether"
                        , idle = "Resolve untether"
                        , confirm = "Resolve untether"
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
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Past sessions")
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
            "met"

        OutcomeFailed ->
            "failed"

        OutcomePartial ->
            "partial"


verdictColor : SessionOutcome -> Element.Color
verdictColor outcome =
    case outcome of
        OutcomeMet ->
            Ui.speakerColor 2

        OutcomeFailed ->
            Ui.danger

        OutcomePartial ->
            Ui.inkSoft
