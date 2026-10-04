module View exposing (logDomId, view)

{-| The Activity view (roadmap section 27, mockup 2a): a one-line status strip
(`View.TopBar`) over three equal columns — a tool panel on the left (a row of
glyph tabs showing one tool at a time: Sheet, Facilitator (facilitator only),
Cast, Guide); the session context in the middle with the Moves pinned beneath;
and, on the right, the event log with the composer pinned beneath it, so neither
playing a move nor sending a message depends on which tool is open. Only the
session context and the log scroll, being the two that grow over play. Each
tool is handed a `ViewContext` computed once here.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
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
import View.ContextAspects
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
            , username = model.auth |> Maybe.map .username |> Maybe.withDefault ""
            }
    in
    case model.gameState of
        Nothing ->
            Ui.page
                { top = notes model
                , columns = [ el [ Element.padding 14 ] (placeholder Copy.loadingTable) ]
                }

        Just gs ->
            Ui.page
                { top =
                    notes model
                        ++ [ View.TopBar.view ctx
                                { confirming = model.confirming
                                , newSessionGoal = model.newSessionGoal
                                , goalEdit = model.goalEdit
                                , expanded = model.sessionControlsExpanded
                                }
                                gs
                           ]
                , columns =
                    [ toolPanel ctx model gs
                    , Ui.columnRule
                    , movesPanel ctx model gs
                    , Ui.columnRule
                    , logPanel ctx model gs
                    ]
                }


{-| The quiet lines above the strip: connection trouble, an error, and — only
while the table is still loading — the auth / connect status. Nothing at all
when all is well, so the strip is the top edge of the page.
-}
notes : Model -> List (Element Msg)
notes model =
    let
        lines =
            connectionNote model.connection
                ++ (if model.gameState == Nothing then
                        [ Ui.banner model.status ]

                    else
                        []
                   )
                ++ (case model.error of
                        Just _ ->
                            [ Ui.errorNote model.error ]

                        Nothing ->
                            []
                   )
    in
    if List.isEmpty lines then
        []

    else
        [ Element.column [ width fill, Element.paddingXY 10 4, spacing 2 ] lines ]


{-| The left panel: the glyph tab strip and the selected tool's body
(scrolling on its own).
-}
toolPanel : ViewContext -> Model -> GameState -> Element Msg
toolPanel ctx model gs =
    let
        selected =
            effectiveTool ctx model.toolTab
    in
    Element.column
        [ Element.height fill
        , width fill
        , Ui.shrinkable
        ]
        [ toolStrip ctx selected gs
        , Element.el
            [ Element.height fill
            , width fill
            , Ui.shrinkable
            , Element.paddingEach { top = 8, right = 10, bottom = 8, left = 10 }
            ]
            (Ui.scrollArea [ toolBody ctx model gs selected ])
        ]


{-| The tool actually shown: the selected one, unless this viewer has no such
tool (the Facilitator tab is the facilitator's only), in which case the Sheet.
-}
effectiveTool : ViewContext -> ToolTab -> ToolTab
effectiveTool ctx tab =
    case tab of
        FacilitatorTab ->
            if ctx.facilitator then
                FacilitatorTab

            else
                SheetTab

        _ ->
            tab


toolStrip : ViewContext -> ToolTab -> GameState -> Element Msg
toolStrip ctx selected gs =
    let
        tool tab glyph label tip =
            Ui.toolTab
                { glyph = glyph
                , label = label
                , tip = tip
                , selected = selected == tab
                , onPress = SelectTool tab
                }
    in
    Element.row
        [ width fill
        , Element.height (Element.px 28)
        , Element.paddingXY 6 0
        , spacing 2
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        (tool SheetTab "◆" Copy.sheetTabLabel Copy.sheetTabTip
            :: (if ctx.facilitator then
                    [ tool FacilitatorTab "⚑" Copy.facilitatorPanelTitle Copy.facilitatorTabTip ]

                else
                    []
               )
            ++ [ tool CastTab "☺" Copy.castTabLabel Copy.castTabTip
               , el [ Element.alignRight ] (tool GuideTab "?" Copy.guideTabLabel Copy.guideTabTip)
               ]
        )


toolBody : ViewContext -> Model -> GameState -> ToolTab -> Element Msg
toolBody ctx model gs tab =
    case tab of
        SheetTab ->
            View.Characters.view ctx
                { selectedSlot = model.selectedSlot
                , aspectExamplesOpen = model.aspectExamplesOpen
                }
                gs

        FacilitatorTab ->
            View.FacilitatorPanel.view ctx gs

        CastTab ->
            if not ctx.facilitator && List.isEmpty gs.npcs && List.isEmpty gs.locations then
                placeholder Copy.noCast

            else
                Ui.flat
                    [ View.Entities.view ctx Npc gs
                    , View.Entities.view ctx Location gs
                    ]

        GuideTab ->
            View.Guide.view


{-| The middle column: the session context (context boons and banes, past
sessions) filling it and scrolling on its own, then the Moves pinned beneath at
their natural height.
-}
movesPanel : ViewContext -> Model -> GameState -> Element Msg
movesPanel ctx model gs =
    Element.column
        [ Element.height fill
        , width fill
        , Ui.shrinkable
        , Element.paddingEach { top = 8, right = 10, bottom = 8, left = 10 }
        , spacing Ui.sm
        ]
        [ Ui.divider (String.toUpper Copy.contextTabLabel)
        , Ui.scrollArea
            [ View.ContextAspects.view ctx
                { contextAspectDraft = model.newContextAspectNote
                , contextAspectKind = model.newContextAspectKind
                , edits = model.contextAspectEdits
                }
                gs
            , View.Session.view ctx gs
            ]
        , Ui.divider (String.toUpper Copy.movesHeading)
        , View.Moves.view ctx { createDraft = model.createDraft, selectedSlot = model.selectedSlot } gs
        ]


{-| The right column: the event log filling it, the composer beneath.
-}
logPanel : ViewContext -> Model -> GameState -> Element Msg
logPanel ctx model gs =
    Element.column
        [ Element.height fill
        , width fill
        , Background.color Ui.panel
        , Ui.shrinkable
        ]
        [ View.Log.view ctx
            { confirming = model.confirming
            , loadingHistory = model.loadingHistory
            , noMoreHistory = model.noMoreHistory
            }
            gs
        , composer model
        ]


connectionNote : Connection -> List (Element msg)
connectionNote conn =
    let
        note color label =
            [ el [ Font.size 11, Font.color color ] (text label) ]
    in
    case conn of
        Connected ->
            []

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


{-| The message field, pinned under the log. Enter sends; there is no button.
-}
composer : Model -> Element Msg
composer model =
    Element.row
        [ width fill
        , Element.paddingXY 10 7
        , Background.color Ui.paper
        , Border.widthEach { top = 1, right = 0, bottom = 0, left = 0 }
        , Border.color Ui.line
        ]
        [ case model.auth of
            Nothing ->
                placeholder Copy.waitingForAuth

            Just _ ->
                Input.text
                    (inputAttrs ++ [ width fill, Ui.onEnter SendMessage ])
                    { onChange = NewMessageChanged
                    , text = model.newMessage
                    , placeholder = Just (Input.placeholder [] (text Copy.messagePlaceholder))
                    , label = Input.labelHidden "Message"
                    }
        ]
