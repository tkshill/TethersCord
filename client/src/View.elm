module View exposing (logDomId, view)

{-| The whole Activity view, built with `elm-ui` on top of the `Ui` system.
-}

import Element
    exposing
        ( Element
        , el
        , fill
        , height
        , maximum
        , minimum
        , none
        , padding
        , px
        , rgb255
        , spacing
        , text
        , width
        )
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Format
import Html exposing (Html)
import Html.Attributes
import Roll exposing (Stone(..))
import Time
import Types exposing (..)
import Ui


{-| The id of the scrollable message-log container. `Main` uses it to keep the
log pinned to the bottom when new messages arrive.
-}
logDomId : String
logDomId =
    "message-log"


view : Model -> Html Msg
view model =
    Ui.page
        [ header model
        , Ui.banner model.status
        , rollPanel model.gameState
        , characterSheets model.gameState
        , messageLog model.timeZone model.gameState
        , composer model
        ]



-- HEADER


header : Model -> Element Msg
header model =
    Element.row [ width fill, spacing Ui.md ]
        [ el [ Font.size 20, Font.semiBold ] (text "Shared Table")
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



-- STONES


rollPanel : Maybe GameState -> Element Msg
rollPanel maybeGs =
    Ui.card
        [ Ui.sectionTitle "Stones"
        , case maybeGs of
            Nothing ->
                placeholder "Loading stone pool…"

            Just gs ->
                let
                    committed =
                        List.foldl (\c acc -> acc + c.count) 0 gs.committedBoons
                in
                Element.column [ spacing Ui.md, width fill ]
                    [ Element.wrappedRow [ spacing Ui.xs ] (List.map stoneChip gs.stonePool)
                    , el [ Font.size 12, Font.color Ui.inkSoft ]
                        (text (poolSummary (List.length gs.stonePool) committed))
                    , case gs.pendingRoll of
                        Nothing ->
                            Element.wrappedRow [ spacing Ui.sm ]
                                [ Ui.ghostButton { onPress = Just AddBoon, label = "Add boon" }
                                , Ui.primaryButton { onPress = Just RollStones, label = "Roll" }
                                ]

                        Just pending ->
                            Element.column [ spacing Ui.sm, width fill ]
                                [ Element.wrappedRow [ spacing Ui.xs ]
                                    (el [ Font.size 12, Font.color Ui.inkSoft ] (text "Rolled")
                                        :: List.map stoneChip pending.chosen
                                    )
                                , Element.wrappedRow [ spacing Ui.sm ]
                                    [ Ui.ghostButton { onPress = Just RerollStones, label = "Reroll" }
                                    , Ui.primaryButton { onPress = Just AcceptRoll, label = "Accept" }
                                    ]
                                ]
                    ]
        ]


poolSummary : Int -> Int -> String
poolSummary poolCount committed =
    let
        base =
            "Bag of " ++ String.fromInt (poolCount + committed)
    in
    if committed > 0 then
        base ++ " (" ++ String.fromInt committed ++ " boon pledged)"

    else
        base


stoneChip : Stone -> Element msg
stoneChip stone =
    case stone of
        Boon ->
            Ui.stoneChip (rgb255 249 248 246) "Boon"

        Bane ->
            Ui.stoneChip (rgb255 42 42 46) "Bane"



-- CHARACTERS


characterSheets : Maybe GameState -> Element Msg
characterSheets maybeGs =
    Ui.card
        [ Ui.sectionTitle "Characters"
        , case maybeGs of
            Nothing ->
                placeholder "Loading character sheets…"

            Just gs ->
                Element.wrappedRow [ spacing Ui.md, width fill ]
                    (List.map (characterSheet gs.committedBoons) gs.characters)
        ]


characterSheet : List CommittedBoon -> CharacterSheet -> Element Msg
characterSheet committedBoons ch =
    Element.column
        [ spacing Ui.sm
        , padding Ui.md
        , width (fill |> minimum 240)
        , Border.color Ui.line
        , Border.width 1
        , Border.rounded 6
        ]
        [ field ch NameField "Name" ch.name
        , field ch NotableFeaturesField "Notable features" ch.notableFeatures
        , field ch ArchetypeField "Archetype" ch.archetype
        , field ch DesireField "Desire" ch.desire
        , field ch QuestField "Quest" ch.quest
        , field ch ConditionField "Condition" ch.condition
        , notesField ch
        , fateRow ch
        , commitRow ch (committedBoonsForSlot ch.slot committedBoons)
        ]


field : CharacterSheet -> CharacterField -> String -> String -> Element Msg
field ch fieldTag label value =
    Input.text
        (inputAttrs ++ [ Ui.onBlur (CharacterFieldBlur ch.slot) ])
        { onChange = CharacterFieldInput ch.slot fieldTag
        , text = value
        , placeholder = Nothing
        , label = fieldLabel label
        }


notesField : CharacterSheet -> Element Msg
notesField ch =
    Input.multiline
        (inputAttrs ++ [ height (px 72), Ui.onBlur (CharacterFieldBlur ch.slot) ])
        { onChange = CharacterFieldInput ch.slot NotesField
        , text = ch.notes
        , placeholder = Nothing
        , label = fieldLabel "Notes"
        , spellcheck = False
        }


fateRow : CharacterSheet -> Element Msg
fateRow ch =
    Element.row [ spacing Ui.sm, Element.centerY ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Boons")
        , el [ Font.semiBold, width (px 20), Font.center ] (text (String.fromInt ch.fate))
        , Ui.ghostButton { onPress = Just (FateDecrement ch.slot), label = "−" }
        , Ui.ghostButton { onPress = Just (FateIncrement ch.slot), label = "+" }
        ]


{-| Boons this character has pledged into the next roll. Spent on Accept.
-}
commitRow : CharacterSheet -> Int -> Element Msg
commitRow ch pledged =
    Element.row [ spacing Ui.sm, Element.centerY ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Pledged")
        , el [ Font.semiBold, width (px 20), Font.center ] (text (String.fromInt pledged))
        , Ui.ghostButton { onPress = Just (CommitBoonDecrement ch.slot), label = "−" }
        , Ui.ghostButton { onPress = Just (CommitBoonIncrement ch.slot), label = "+" }
        ]


fieldLabel : String -> Input.Label msg
fieldLabel label =
    Input.labelAbove [ Font.size 11, Font.color Ui.inkSoft ] (text label)


inputAttrs : List (Element.Attribute msg)
inputAttrs =
    [ padding Ui.sm
    , Border.color Ui.line
    , Border.width 1
    , Border.rounded 4
    , Font.size 13
    ]



-- LOG


messageLog : Time.Zone -> Maybe GameState -> Element Msg
messageLog zone maybeGs =
    Ui.card
        [ Ui.sectionTitle "Log"
        , case maybeGs of
            Nothing ->
                placeholder "Loading messages…"

            Just gs ->
                if List.isEmpty gs.messages then
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
                        (List.map (messageRow zone) gs.messages)
        ]


messageRow : Time.Zone -> Message -> Element msg
messageRow zone msg =
    let
        nameColor =
            case msg.role of
                Facilitator ->
                    Ui.facilitatorTint

                Player ->
                    Ui.ink
    in
    Element.row [ width fill, spacing Ui.md ]
        [ el
            [ Font.family Ui.mono
            , Font.size 11
            , Font.color Ui.inkSoft
            , Element.alignTop
            , width (px 116)
            ]
            (text (Format.timestamp zone msg.createdAt))
        , Element.paragraph [ spacing 3, Font.size 13 ]
            [ el [ Font.semiBold, Font.color nameColor ] (text (msg.authorName ++ ": "))
            , text msg.content
            ]
        ]



-- COMPOSER


composer : Model -> Element Msg
composer model =
    case model.auth of
        Nothing ->
            placeholder "Waiting for authentication…"

        Just _ ->
            Element.row [ spacing Ui.sm, width fill ]
                [ Input.text
                    (inputAttrs ++ [ width fill, Ui.onEnter SendMessage ])
                    { onChange = NewMessageChanged
                    , text = model.newMessage
                    , placeholder = Just (Input.placeholder [] (text "Write a message…"))
                    , label = Input.labelHidden "Message"
                    }
                , Ui.primaryButton { onPress = Just SendMessage, label = "Send" }
                ]



-- SHARED


placeholder : String -> Element msg
placeholder label =
    el [ Font.size 13, Font.color Ui.inkSoft ] (text label)
