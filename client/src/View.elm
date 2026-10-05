module View exposing (aspectFieldId, contextAspectFieldId, logDomId, view)

{-| The Activity view (roadmap 27, mockup 2a; moves placed by 31.5): a one-line
status strip (`View.TopBar`, the die ladder and the junction) over three
columns — a 316px tool panel on the left (one strip of tabs, a sheet per
character then World and Guide, showing one at a time); a 284px column of the context boons and banes in the middle with the
Create field pinned beneath; and, on the right, the event log with the composer
pinned beneath it. Every move is made where its subject is: Highlight and
Complicate on the Sheet's aspects, Highlight Context on the context list, Create
under it, Alter on the strip, and undo on the move's own log line. Only the
context list and the log scroll, being the two that grow over play. Each tool is
handed a `ViewContext` computed once here.
-}

import Aspect
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
import View.Guide
import View.Helpers exposing (ViewContext, characterLabel, inputAttrs, placeholder)
import View.Log
import View.Session
import View.ContextAspects
import View.TopBar


{-| The id of the scrollable message-log container. `Effect` uses it to keep the
log pinned to the bottom when new messages arrive; it is defined in `View.Log`.
-}
logDomId : String
logDomId =
    View.Log.logDomId


{-| The DOM ids `Main` focuses when ✎ swaps in a field.
-}
aspectFieldId : Int -> Aspect.Aspect -> String
aspectFieldId =
    View.Helpers.aspectFieldId


contextAspectFieldId : String -> String
contextAspectFieldId =
    View.Helpers.contextAspectFieldId


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
                    , contextPanel ctx model gs
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


{-| The left panel (316px): the tool strip and the selected tool's body
(scrolling on its own).
-}
toolPanel : ViewContext -> Model -> GameState -> Element Msg
toolPanel ctx model gs =
    let
        selected =
            shownTool model.toolTab gs
    in
    Element.column
        [ Element.height fill
        , width (Element.px 316)
        , Ui.shrinkable
        ]
        [ toolStrip ctx selected gs
        , Element.el
            [ Element.height fill
            , width fill
            , Ui.shrinkable
            , Element.paddingEach { top = 12, right = 14, bottom = 14, left = 14 }
            ]
            (Ui.scrollArea [ toolBody ctx model gs selected ])
        ]


{-| The tool actually on show. A sheet tab whose slot no longer holds a
character falls back to the first sheet, so the strip always marks what the
body shows.
-}
shownTool : ToolTab -> GameState -> ToolTab
shownTool tab gs =
    case tab of
        SheetTab slot ->
            if List.any (\c -> c.slot == slot) gs.characters then
                tab

            else
                gs.characters
                    |> List.head
                    |> Maybe.map (.slot >> SheetTab)
                    |> Maybe.withDefault tab

        _ ->
            tab


{-| One strip for everything the left panel can show (roadmap 32.2): a tab
per character sheet — the viewer's own marked "you" — then, past a rule at the
right, the World and the Guide.
-}
toolStrip : ViewContext -> ToolTab -> GameState -> Element Msg
toolStrip ctx selected gs =
    let
        tool tab label suffix tip =
            Ui.toolTab
                { label = label
                , suffix = suffix
                , tip = tip
                , selected = selected == tab
                , onPress = SelectTool tab
                }

        sheetTab ch =
            let
                name =
                    characterLabel ch

                mine =
                    not ctx.facilitator && ch.ownerId /= Nothing && ch.ownerId == ctx.myId
            in
            tool (SheetTab ch.slot)
                name
                (if mine then
                    Copy.youMarker

                 else
                    ""
                )
                (Copy.sheetTabTip name)

        -- 5px clear of World: the row's 2px spacing plus 3.
        separator =
            el [ Element.alignRight, Element.paddingEach { top = 0, right = 3, bottom = 0, left = 0 } ]
                (el [ width (Element.px 1), Element.height (Element.px 16), Background.color Ui.line ] none)
    in
    Element.row
        [ width fill
        , Element.height (Element.px 36)
        , Element.paddingXY 8 0
        , spacing 2
        , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
        , Border.color Ui.line
        ]
        (List.map sheetTab gs.characters
            ++ [ separator
               , el [ Element.alignRight ] (tool WorldTab Copy.castTabLabel "" Copy.castTabTip)
               , el [ Element.alignRight ] (tool GuideTab Copy.guideTabLabel "" Copy.guideTabTip)
               ]
        )


toolBody : ViewContext -> Model -> GameState -> ToolTab -> Element Msg
toolBody ctx model gs tab =
    case tab of
        SheetTab slot ->
            View.Characters.view ctx
                { selectedSlot = slot
                , aspectExamplesOpen = model.aspectExamplesOpen
                , aspectEditing = model.aspectEditing
                }
                gs

        WorldTab ->
            if not ctx.facilitator && List.isEmpty gs.npcs && List.isEmpty gs.locations then
                placeholder Copy.noCast

            else
                Ui.flat
                    [ View.Entities.view ctx Npc gs
                    , View.Entities.view ctx Location gs
                    ]

        GuideTab ->
            View.Guide.view


{-| The middle column (284px): the context boons and banes and the past sessions,
scrolling on their own, with the Create field pinned at the foot of the list.
-}
contextPanel : ViewContext -> Model -> GameState -> Element Msg
contextPanel ctx model gs =
    let
        props =
            { facilitatorDraft = model.newContextAspectNote
            , facilitatorKind = model.newContextAspectKind
            , createDraft = model.createDraft
            , edits = model.contextAspectEdits
            }
    in
    Element.column
        [ Element.height fill
        , width (Element.px 284)
        , Ui.shrinkable
        ]
        [ View.ContextAspects.header gs
        , el
            [ Element.height fill
            , width fill
            , Ui.shrinkable
            , Element.paddingXY 14 12
            ]
            (Ui.scrollArea
                [ View.ContextAspects.view ctx props gs
                , View.Session.view ctx gs
                ]
            )
        , View.ContextAspects.createField ctx props gs
        ]


{-| The right column, taking whatever width the two fixed columns leave: the
event log filling it, the composer beneath.
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
        , Element.paddingXY 12 8
        , Background.color Ui.paper
        , Border.widthEach { top = 1, right = 0, bottom = 0, left = 0 }
        , Border.color Ui.line
        ]
        [ case model.auth of
            Nothing ->
                placeholder Copy.waitingForAuth

            Just _ ->
                Input.text
                    [ width fill
                    , Element.paddingXY 10 7
                    , Border.width 1
                    , Border.color Ui.edge
                    , Border.rounded 6
                    , Background.color Ui.panel
                    , Font.size 13
                    , Ui.onEnter SendMessage
                    ]
                    { onChange = NewMessageChanged
                    , text = model.newMessage
                    , placeholder = Just (Input.placeholder [ Font.color Ui.inkSoft ] (text Copy.messagePlaceholder))
                    , label = Input.labelHidden "Message"
                    }
        ]
