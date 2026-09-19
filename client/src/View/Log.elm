module View.Log exposing (logDomId, view)

{-| The event log (roadmap section 27, mockup 2a): the right panel's body — day
dividers and one line per message, `time name text`, the name in the speaker's
colour — with the "load earlier messages" affordance at the top and, for the
facilitator, a confirm-gated Clear log. Flat, not a card: the panel is the
surface. The composer is pinned beneath it by `View`.
-}

import Copy
import Dict exposing (Dict)
import Element exposing (Element, el, fill, height, none, px, spacing, text, width)
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
    Element.column [ width fill, height fill, Ui.shrinkable ]
        [ if ctx.facilitator && not (List.isEmpty gs.messages) then
            clearLogRow props.confirming

          else
            none
        , if List.isEmpty gs.messages then
            el [ Element.padding 14 ] (placeholder Copy.noMessages)

          else
            Element.column
                [ width fill
                , height fill
                , spacing 7
                , Element.paddingXY 14 10
                , Element.scrollbarY
                , Ui.shrinkable
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
    Element.column [ width fill, spacing 7 ]
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
                el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.loadingEarlierMessages)

             else
                Ui.ghostButton { onPress = Just LoadEarlierMessages, label = Copy.loadEarlierMessages }
            )


clearLogRow : Maybe String -> Element Msg
clearLogRow confirming =
    el [ Element.alignRight, Element.paddingXY 10 4 ]
        (Ui.confirmButton
            { armed = confirming == Just "clear-log"
            , idle = Copy.clearLog
            , confirm = Copy.clearLog
            , onArm = RequestConfirm "clear-log"
            , onConfirm = ClearLog
            , onCancel = CancelConfirm
            }
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
    Element.row [ width fill, spacing 10 ]
        [ el
            [ Font.family Ui.mono
            , Font.size 11
            , Font.color Ui.inkSoft
            , Element.alignTop
            , Element.paddingEach { top = 1, right = 0, bottom = 0, left = 0 }
            , width (px 38)
            ]
            (text (Format.clock zone msg.createdAt))
        , Element.paragraph [ spacing 4, Font.size 13 ]
            [ el [ Font.semiBold, Font.color nameColor ] (text (msg.authorName ++ " "))
            , text msg.content
            ]
        ]
