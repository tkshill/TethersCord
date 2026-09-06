module View.Log exposing (logDomId, view)

{-| The Log card: the header with the facilitator's confirm-gated Clear log, the
"load earlier messages" affordance, and the scrolling body of day-divided,
speaker-coloured rows (folded behind `Element.Lazy`).
-}

import Dict exposing (Dict)
import Element exposing (Element, el, fill, height, maximum, none, px, spacing, text, width)
import Element.Font as Font
import Element.Lazy
import Format
import Html.Attributes
import Time
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, placeholder)


{-| The id of the scrollable message-log container. `Main` uses it (through
`View.logDomId`) to keep the log pinned to the bottom when new messages arrive.
-}
logDomId : String
logDomId =
    "message-log"


{-| Matches the Worker's `MESSAGE_WINDOW`: below this many rows loaded, there is
nothing earlier to ask for.
-}
logWindow : Int
logWindow =
    50


type alias Props =
    { confirming : Maybe String
    , loadingHistory : Bool
    , noMoreHistory : Bool
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    Ui.card
        [ logHeader ctx.facilitator props.confirming gs
        , if List.isEmpty gs.messages then
            placeholder "No messages yet."

          else
            Element.column
                [ width fill
                , height (fill |> maximum 360)
                , spacing Ui.sm
                , Element.scrollbarY
                , Element.htmlAttribute (Html.Attributes.id logDomId)
                , Ui.onScrolledToBottom 32 LogScrolled
                ]
                [ loadEarlierRow props.loadingHistory props.noMoreHistory gs.messages
                , Element.Lazy.lazy2 lazyLogBody ctx.zone gs.messages
                ]
        ]


{-| The expensive part of the log — the speaker-colour fold and the day-divided
rows — behind `Element.Lazy` so re-renders that do not touch `messages` (typing
in the composer, arming a confirm, switching a tab) skip refolding the whole
list. A socket broadcast still decodes a fresh list, so it does not help there.
-}
lazyLogBody : Time.Zone -> List Message -> Element Msg
lazyLogBody zone messages =
    Element.column [ width fill, spacing Ui.sm ]
        (logRows zone (speakerColors messages) messages)


{-| A "load earlier messages" affordance at the top of the log, shown only while
there may be more to fetch.
-}
loadEarlierRow : Bool -> Bool -> List Message -> Element Msg
loadEarlierRow loadingHistory noMoreHistory messages =
    if noMoreHistory || List.length messages < logWindow then
        none

    else
        el [ Element.centerX ]
            (if loadingHistory then
                el [ Font.size 11, Font.color Ui.inkSoft ] (text "Loading earlier messages…")

             else
                Ui.ghostButton { onPress = Just LoadEarlierMessages, label = "Load earlier messages" }
            )


logHeader : Bool -> Maybe String -> GameState -> Element Msg
logHeader facilitator confirming gs =
    let
        hasMessages =
            not (List.isEmpty gs.messages)
    in
    Element.row [ width fill, spacing Ui.md ]
        (Ui.sectionTitle "Log"
            :: (if facilitator && hasMessages then
                    [ el [ Element.alignRight ]
                        (Ui.confirmButton
                            { armed = confirming == Just "clear-log"
                            , idle = "Clear log"
                            , confirm = "Clear log"
                            , onArm = RequestConfirm "clear-log"
                            , onConfirm = ClearLog
                            , onCancel = CancelConfirm
                            }
                        )
                    ]

                else
                    []
               )
        )


{-| One stable colour per speaker: the facilitator, then each player in the
order they first speak.
-}
speakerColors : List Message -> Dict String Element.Color
speakerColors messages =
    List.foldl
        (\msg ( nextPlayer, dict ) ->
            if Dict.member msg.authorId dict then
                ( nextPlayer, dict )

            else
                case msg.role of
                    Facilitator ->
                        ( nextPlayer, Dict.insert msg.authorId (Ui.speakerColor 0) dict )

                    Player ->
                        ( nextPlayer + 1, Dict.insert msg.authorId (Ui.speakerColor nextPlayer) dict )
        )
        ( 1, Dict.empty )
        messages
        |> Tuple.second


{-| The message rows with a day divider inserted wherever the calendar date
changes.
-}
logRows : Time.Zone -> Dict String Element.Color -> List Message -> List (Element Msg)
logRows zone colors messages =
    List.foldl
        (\msg ( lastDay, acc ) ->
            let
                day =
                    Format.date zone msg.createdAt

                row =
                    messageRow zone colors msg
            in
            if day == lastDay then
                ( lastDay, row :: acc )

            else
                ( day, row :: Ui.divider day :: acc )
        )
        ( "", [] )
        messages
        |> Tuple.second
        |> List.reverse


messageRow : Time.Zone -> Dict String Element.Color -> Message -> Element msg
messageRow zone colors msg =
    let
        nameColor =
            Dict.get msg.authorId colors |> Maybe.withDefault Ui.ink
    in
    Element.row [ width fill, spacing Ui.md ]
        [ el
            [ Font.family Ui.mono
            , Font.size 11
            , Font.color Ui.inkSoft
            , Element.alignTop
            , width (px 44)
            ]
            (text (Format.clock zone msg.createdAt))
        , Element.paragraph [ spacing 3, Font.size 13 ]
            [ el [ Font.semiBold, Font.color nameColor ] (text (msg.authorName ++ ": "))
            , text msg.content
            ]
        ]
