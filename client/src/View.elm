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
import Dict exposing (Dict)
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
    let
        facilitator =
            isFacilitator model
    in
    Ui.page
        [ header model
        , Ui.banner model.status
        , rollPanel facilitator model.gameState
        , characterSheets facilitator model.gameState
        , messageLog facilitator model.timeZone model.gameState
        , composer model
        ]


isFacilitator : Model -> Bool
isFacilitator model =
    case model.auth of
        Just auth ->
            auth.role == Facilitator

        Nothing ->
            False



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


rollPanel : Bool -> Maybe GameState -> Element Msg
rollPanel facilitator maybeGs =
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
                                (Ui.ghostButton { onPress = Just AddBoon, label = "Add boon" }
                                    :: onlyFacilitator facilitator
                                        [ Ui.primaryButton { onPress = Just RollStones, label = "Roll" } ]
                                )

                        Just pending ->
                            Element.column [ spacing Ui.sm, width fill ]
                                (Element.wrappedRow [ spacing Ui.xs ]
                                    (el [ Font.size 12, Font.color Ui.inkSoft ] (text "Rolled")
                                        :: List.map stoneChip pending.chosen
                                    )
                                    :: onlyFacilitator facilitator
                                        [ Element.wrappedRow [ spacing Ui.sm ]
                                            [ Ui.ghostButton { onPress = Just RerollStones, label = "Reroll" }
                                            , Ui.primaryButton { onPress = Just AcceptRoll, label = "Accept" }
                                            ]
                                        ]
                                )
                    ]
        ]


{-| The given elements, but only for the facilitator; an empty list otherwise.
Keeps the roll lifecycle and boon grants out of players' hands until player
moves become facilitator-approved proposals (roadmap section 5).
-}
onlyFacilitator : Bool -> List (Element msg) -> List (Element msg)
onlyFacilitator facilitator elements =
    if facilitator then
        elements

    else
        []


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


characterSheets : Bool -> Maybe GameState -> Element Msg
characterSheets facilitator maybeGs =
    Ui.card
        [ Ui.sectionTitle "Characters"
        , case maybeGs of
            Nothing ->
                placeholder "Loading character sheets…"

            Just gs ->
                Element.wrappedRow [ spacing Ui.md, width fill ]
                    (List.map (characterSheet facilitator gs.committedBoons) gs.characters)
        ]


characterSheet : Bool -> List CommittedBoon -> CharacterSheet -> Element Msg
characterSheet facilitator committedBoons ch =
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
        , fateRow facilitator ch
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


fateRow : Bool -> CharacterSheet -> Element Msg
fateRow facilitator ch =
    Element.row [ spacing Ui.sm, Element.centerY ]
        ([ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Boons")
         , el [ Font.semiBold, width (px 20), Font.center ] (text (String.fromInt ch.fate))
         ]
            ++ onlyFacilitator facilitator
                [ Ui.ghostButton { onPress = Just (FateDecrement ch.slot), label = "−" }
                , Ui.ghostButton { onPress = Just (FateIncrement ch.slot), label = "+" }
                ]
        )


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


messageLog : Bool -> Time.Zone -> Maybe GameState -> Element Msg
messageLog facilitator zone maybeGs =
    Ui.card
        [ logHeader facilitator maybeGs
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
                        (logRows zone (speakerColors gs.messages) gs.messages)
        ]


logHeader : Bool -> Maybe GameState -> Element Msg
logHeader facilitator maybeGs =
    let
        hasMessages =
            case maybeGs of
                Just gs ->
                    not (List.isEmpty gs.messages)

                Nothing ->
                    False
    in
    Element.row [ width fill, spacing Ui.md ]
        (Ui.sectionTitle "Log"
            :: (if facilitator && hasMessages then
                    [ el [ Element.alignRight ]
                        (Ui.ghostButton { onPress = Just ClearLog, label = "Clear log" })
                    ]

                else
                    []
               )
        )


{-| One stable colour per speaker: the facilitator, then each player in the
order they first speak. -}
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
changes. -}
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
