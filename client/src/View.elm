module View exposing (logDomId, view)

{-| The Activity view: the page shell (header, connection note, status banner,
the top bar) over two panels (roadmap section 24, replacing 23.5's
three-column shell; this is the "1c" layout variant) — a resizable left panel
of accordion sections (Facilitator panel, Characters, Moves, unchanged in
content from 23.5) and a right panel splitting its height between a tab strip
switching between NPCs & locations, session context (session aspects and
session history), and the guide, and the event log pinned always-visible
beneath it — with the composer pinned under the panels row rather than under
any one column, since sending a message doesn't depend on which tab is
showing. Each card still lives in its own `View.*` module and is handed a
`ViewContext` computed once here.
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
            , inflight = model.inflight
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
                    [ leftPanel ctx model gs
                    , Ui.dragHandle DividerDragStarted
                    , rightPanel ctx model gs
                    ]
                , bottom = [ composer model ]
                }


{-| The left panel (roadmap section 24, the 1c layout variant): the same three
cards 23.5 put here, now each its own collapsible accordion section, at a
mouse-draggable pixel width (`Model.leftPanelWidth`) instead of a fixed
`fillPortion` of the row.
-}
leftPanel : ViewContext -> Model -> GameState -> Element Msg
leftPanel ctx model gs =
    Element.el
        [ Element.height fill
        , width (Element.px (round model.leftPanelWidth))
        , Ui.shrinkable
        ]
        (Ui.scrollArea
            [ View.FacilitatorPanel.view ctx
                { drafts = model.proposalDrafts
                , open = model.openLeftSections.facilitator
                }
                gs
            , View.Characters.view ctx
                { selectedSlot = model.selectedSlot
                , aspectExamplesOpen = model.aspectExamplesOpen
                , open = model.openLeftSections.characters
                }
                gs
            , View.Moves.view ctx { open = model.openLeftSections.moves } gs
            ]
        )


{-| The right panel (roadmap section 24, the 1c layout variant): a tab strip
and its content take the top share of the panel's height; the event log is
pinned beneath, always visible regardless of which tab is selected, at
roughly the mockup's 56/44 split (`fillPortion 5` / `4`).
-}
rightPanel : ViewContext -> Model -> GameState -> Element Msg
rightPanel ctx model gs =
    Element.column
        [ Element.height fill
        , width fill
        , spacing Ui.md
        , Ui.shrinkable
        ]
        [ rightPanelTabStrip model.rightPanelTab
        , Element.el [ Element.height (Element.fillPortion 5), width fill, Ui.shrinkable ]
            (rightPanelTabContent ctx model gs)
        , Element.el [ Element.height (Element.fillPortion 4), width fill, Ui.shrinkable ]
            (View.Log.view ctx
                { confirming = model.confirming
                , loadingHistory = model.loadingHistory
                , noMoreHistory = model.noMoreHistory
                }
                gs
            )
        ]


rightPanelTabStrip : RightPanelTab -> Element Msg
rightPanelTabStrip selected =
    Element.wrappedRow [ spacing Ui.xs, width fill ]
        [ Ui.tab (selected == NpcsLocationsTab) Copy.npcsLocationsTabLabel (SelectRightPanelTab NpcsLocationsTab)
        , Ui.tab (selected == SessionTab) Copy.sessionContextTabLabel (SelectRightPanelTab SessionTab)
        , Ui.tab (selected == GuideTab) Copy.guideTabLabel (SelectRightPanelTab GuideTab)
        ]


{-| The selected tab's content, a plain `Ui.scrollArea` stack of the cards that
tab combines. The event log is not one of these tabs — see `rightPanel`.
-}
rightPanelTabContent : ViewContext -> Model -> GameState -> Element Msg
rightPanelTabContent ctx model gs =
    case model.rightPanelTab of
        NpcsLocationsTab ->
            Ui.scrollArea
                [ View.Entities.view ctx Npc gs
                , View.Entities.view ctx Location gs
                ]

        SessionTab ->
            Ui.scrollArea
                [ View.SessionAspects.view ctx
                    { sessionAspectDraft = model.newSessionAspectNote
                    , sessionAspectKind = model.newSessionAspectKind
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
