module View exposing (logDomId, view)

{-| The Activity view: the page shell (header, connection note, status banner,
the top bar) over three independently-scrolling columns (roadmap section
23.5) — left (facilitator panel, character sheets, moves), centre (NPCs,
locations, session aspects, session history), right (the event log and the
composer, pinned beneath it) — each card living in its own `View.*` module and
handed a `ViewContext` computed once here.
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
import View.FacilitatorPanel
import View.Guide
import View.Helpers exposing (ViewContext, inputAttrs, placeholder)
import View.Log
import View.Moves
import View.Session
import View.SessionAspects
import View.TopBar


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

        top =
            header model
                :: connectionNote model.connection
                :: Ui.banner model.status
                :: Ui.errorNote model.error
                :: (case model.gameState of
                        Just gs ->
                            [ View.TopBar.view ctx
                                { confirming = model.confirming
                                , newSessionGoal = model.newSessionGoal
                                , goalEdit = model.goalEdit
                                , expanded = model.sessionControlsExpanded
                                }
                                gs
                            ]

                        Nothing ->
                            []
                   )
    in
    case model.gameState of
        Nothing ->
            Ui.page { top = top, columns = [ Ui.scrollColumn 1 [ placeholder Copy.loadingTable ] ] }

        Just gs ->
            Ui.page
                { top = top
                , columns =
                    [ Ui.scrollColumn 3
                        [ View.FacilitatorPanel.view ctx
                            { inflight = model.inflight
                            , drafts = model.proposalDrafts
                            }
                            gs
                        , View.Characters.view ctx
                            { selectedSlot = model.selectedSlot
                            , aspectExamplesOpen = model.aspectExamplesOpen
                            }
                            gs
                        , View.Moves.view ctx gs
                        ]
                    , Ui.scrollColumn 3
                        [ View.Entities.view ctx Npc gs
                        , View.Entities.view ctx Location gs
                        , View.SessionAspects.view ctx
                            { inflight = model.inflight
                            , floatingBoonDraft = model.newFloatingBoonNote
                            , floatingBoonKind = model.newFloatingBoonKind
                            }
                            gs
                        , View.Session.view ctx gs
                        , View.Guide.view ctx { expanded = model.guideExpanded }
                        ]
                    , Element.column [ Element.height fill, width (Element.fillPortion 4), spacing Ui.md ]
                        [ View.Log.view ctx
                            { confirming = model.confirming
                            , loadingHistory = model.loadingHistory
                            , noMoreHistory = model.noMoreHistory
                            }
                            gs
                        , composer model
                        ]
                    ]
                }


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
