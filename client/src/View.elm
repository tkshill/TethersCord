module View exposing (logDomId, view)

{-| The Activity view: the page shell (header, connection note, status banner,
composer) plus the ordered list of section cards, each of which lives in its own
`View.*` module and is handed a `ViewContext` computed once here.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Types exposing (..)
import Ui
import View.Characters
import View.Entities
import View.Guide
import View.Helpers exposing (ViewContext, inputAttrs, placeholder)
import View.Log
import View.Moves
import View.Session
import View.Stones


{-| The id of the scrollable message-log container. `Effect` uses it to keep the
log pinned to the bottom when new messages arrive; it is defined in `View.Log`.
-}
logDomId : String
logDomId =
    View.Log.logDomId


view : Model -> Html Msg
view model =
    let
        ctx : ViewContext
        ctx =
            { facilitator = isFacilitator model
            , myId = Maybe.map .userId model.auth
            , zone = model.timeZone
            }

        -- The shell — header, notes, composer — renders with or without game
        -- state; only the panels between them need a loaded board.
        shell middle =
            Ui.page
                (header model
                    :: connectionNote model.connection
                    :: Ui.banner model.status
                    :: Ui.errorNote model.error
                    :: middle
                    ++ [ composer model ]
                )
    in
    case model.gameState of
        Nothing ->
            shell [ placeholder Copy.loadingTable ]

        Just gs ->
            shell
                [ View.Session.view ctx
                    { confirming = model.confirming
                    , newSessionGoal = model.newSessionGoal
                    , goalEdit = model.goalEdit
                    }
                    gs
                , View.Stones.view ctx
                    { inflight = model.inflight
                    , drafts = model.proposalDrafts
                    , floatingBoonDraft = model.newFloatingBoonNote
                    , floatingBoonKind = model.newFloatingBoonKind
                    }
                    gs
                , View.Moves.view ctx gs
                , View.Characters.view ctx
                    { selectedSlot = model.selectedSlot
                    , aspectExamplesOpen = model.aspectExamplesOpen
                    }
                    gs
                , View.Entities.view ctx Npc gs
                , View.Entities.view ctx Location gs
                , View.Log.view ctx
                    { confirming = model.confirming
                    , loadingHistory = model.loadingHistory
                    , noMoreHistory = model.noMoreHistory
                    }
                    gs
                , View.Guide.view ctx { expanded = model.guideExpanded }
                ]


connectionNote : Connection -> Element msg
connectionNote conn =
    let
        note color label =
            el [ Font.size 11, Font.color color ] (text label)
    in
    case conn of
        Connected ->
            none

        Reconnecting ->
            note Ui.inkSoft Copy.reconnecting

        Offline ->
            note Ui.danger Copy.connectionLost

        Rejected ->
            note Ui.danger Copy.sessionRejected


isFacilitator : Model -> Bool
isFacilitator model =
    case model.auth of
        Just auth ->
            auth.role == Facilitator

        Nothing ->
            False


header : Model -> Element Msg
header model =
    Element.row [ width fill, spacing Ui.md ]
        [ el [ Font.size 20, Font.semiBold ] (text Copy.appTitle)
        , case model.auth of
            Just auth ->
                el
                    [ Font.size 12
                    , Font.color Ui.inkSoft
                    , Element.alignRight
                    ]
                    (text (auth.username ++ " · " ++ roleLabel auth.role))

            Nothing ->
                none
        ]


composer : Model -> Element Msg
composer model =
    case model.auth of
        Nothing ->
            placeholder Copy.waitingForAuth

        Just _ ->
            Element.row [ spacing Ui.sm, width fill ]
                [ Input.text
                    (inputAttrs ++ [ width fill, Ui.onEnter SendMessage ])
                    { onChange = NewMessageChanged
                    , text = model.newMessage
                    , placeholder = Just (Input.placeholder [] (text Copy.messagePlaceholder))
                    , label = Input.labelHidden "Message"
                    }
                , Ui.primaryButton { onPress = Just SendMessage, label = Copy.send }
                ]
