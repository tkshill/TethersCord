module View.TopBar exposing (view)

{-| The status strip across the top of the page (roadmap section 27, mockup 2a):
one line holding the running session's goal, the shared pool as a run of `+` /
`−` marks, the Overcome control, and who the viewer is.

The pool marks show what is left in the pool. Pressing **Overcome** (open to any
player) draws two stones: while that roll is pending they sit in a ringed chip
beside the pool marks (who drew and how many rerolls is its tooltip), and the
facilitator's Reroll / Reject / Accept replace the Overcome button; a player sees
that they are waiting. Alter Fate is a player move, so it lives in the Moves
tool, and its proposal in the facilitator's queue — not here.

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
import Html.Attributes
import Roll exposing (Stone(..))
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
        , pool gs
        , controls ctx gs.overcome
        , who ctx
        ]


{-| The pool as marks, less whatever a pending Overcome has drawn out of it,
then the draw itself in a ringed chip.
-}
pool : GameState -> Element Msg
pool gs =
    let
        drawn =
            gs.overcome |> Maybe.map .stones |> Maybe.withDefault []

        inPool =
            Roll.without drawn gs.stonePool

        count stone stones =
            List.length (List.filter ((==) stone) stones)
    in
    Element.row [ spacing 10, Element.centerY ]
        [ Element.row
            [ Font.size 14
            , Element.htmlAttribute (Html.Attributes.title (Copy.bagTip (count Boon inPool) (count Bane inPool)))
            ]
            [ Ui.boonMarks (count Boon inPool), Ui.baneMarks (count Bane inPool) ]
        , case gs.overcome of
            Just o ->
                Element.row
                    [ Font.size 14
                    , Element.paddingXY 6 1
                    , Border.width 1
                    , Border.color Ui.accent
                    , Border.rounded 4
                    , Element.htmlAttribute
                        (Html.Attributes.title (Copy.overcomeDrew o.rolledBy ++ " · " ++ Copy.rerollsNote o.rerolls))
                    ]
                    (List.map stoneMark o.stones)

            Nothing ->
                none
        ]


stoneMark : Stone -> Element msg
stoneMark stone =
    case stone of
        Boon ->
            Ui.boonMarks 1

        Bane ->
            Ui.baneMarks 1


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
                Element.row [ spacing Ui.xs ]
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
                el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.waitingForFacilitator)


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
