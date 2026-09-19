module View.Session exposing (view)

{-| The Session history, under the Context tool — the table's completed sessions, newest first.
All that is left of the old Session card once its running goal and start /
end / edit controls moved to the top bar (`View.TopBar`, roadmap section
23.6); a session's goal is free text with no roll or verdict tied to ending
it. Hidden entirely until a session has ended.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Format
import Time
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext)


view : ViewContext -> GameState -> Element Msg
view ctx gs =
    if List.isEmpty gs.sessionHistory then
        none

    else
        Ui.flat
            (Ui.sectionTitle Copy.sessionHistoryTitle
                :: List.map (pastSessionRow ctx.zone) gs.sessionHistory
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
