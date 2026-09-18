module View exposing (logDomId, view)

{-| The Activity view: the page shell (header, connection note, status banner,
the top bar) over two independently-scrolling panels (roadmap section 24,
replacing 23.5's three-column shell) — left (facilitator panel, character
sheets, moves, unchanged from 23.5) and right, a single tabbed column
switching between the event log, NPCs & locations, session context (session
aspects and session history), and the guide — with the composer pinned under
the panels row instead of under any one column, since sending a message no
longer needs the log tab open. Each card still lives in its own `View.*`
module and is handed a `ViewContext` computed once here.
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
            Ui.page
                { top = top
                , columns = [ Ui.scrollColumn 1 [ placeholder Copy.loadingTable ] ]
                , bottom = []
                }

        Just gs ->
            Ui.page
                { top = top
                , columns =
                    [ Ui.scrollColumn 5
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
                    , rightPanel ctx model gs
                    ]
                , bottom = [ composer model ]
                }


{-| The right panel (roadmap section 24): a tab strip over a single scrolling
content area, in place of the old centre and right columns. `fillPortion 7`
against the left panel's `5` mirrors the mockup's 5/7 split.
-}
rightPanel : ViewContext -> Model -> GameState -> Element Msg
rightPanel ctx model gs =
    Element.column
        [ Element.height fill
        , width (Element.fillPortion 7)
        , spacing Ui.md
        , Ui.shrinkable
        ]
        [ rightPanelTabStrip model.rightPanelTab
        , rightPanelContent ctx model gs
        ]


rightPanelTabStrip : RightPanelTab -> Element Msg
rightPanelTabStrip selected =
    Element.wrappedRow [ spacing Ui.xs, width fill ]
        [ Ui.tab (selected == LogTab) Copy.logTitle (SelectRightPanelTab LogTab)
        , Ui.tab (selected == NpcsLocationsTab) Copy.npcsLocationsTabLabel (SelectRightPanelTab NpcsLocationsTab)
        , Ui.tab (selected == SessionTab) Copy.sessionContextTabLabel (SelectRightPanelTab SessionTab)
        , Ui.tab (selected == GuideTab) Copy.guideTabLabel (SelectRightPanelTab GuideTab)
        ]


{-| The selected tab's content. The Log tab keeps its own `cardFill` (it
already owns the scrolling region and DOM id the pin-to-bottom behaviour
needs); every other tab is a plain `Ui.scrollArea` stack of the cards that tab
combines.
-}
rightPanelContent : ViewContext -> Model -> GameState -> Element Msg
rightPanelContent ctx model gs =
    case model.rightPanelTab of
        LogTab ->
            View.Log.view ctx
                { confirming = model.confirming
                , loadingHistory = model.loadingHistory
                , noMoreHistory = model.noMoreHistory
                }
                gs

        NpcsLocationsTab ->
            Ui.scrollArea
                [ View.Entities.view ctx Npc gs
                , View.Entities.view ctx Location gs
                ]

        SessionTab ->
            Ui.scrollArea
                [ View.SessionAspects.view ctx
                    { inflight = model.inflight
                    , floatingBoonDraft = model.newFloatingBoonNote
                    , floatingBoonKind = model.newFloatingBoonKind
                    }
                    gs
                , View.Session.view ctx gs
                ]

        GuideTab ->
            Ui.scrollArea [ View.Guide.view ctx { expanded = model.guideExpanded } ]


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
