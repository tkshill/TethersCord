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

        myId =
            Maybe.map .userId model.auth
    in
    Ui.page
        [ header model
        , connectionNote model.connection
        , Ui.banner model.status
        , sessionPanel facilitator model.timeZone model.newSessionGoal model.gameState
        , rollPanel facilitator myId model.gameState
        , characterSheets facilitator myId model.gameState
        , messageLog facilitator model.timeZone model.gameState
        , composer model
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
            note Ui.inkSoft "Reconnecting to the table…"

        Offline ->
            note Ui.danger "Connection lost. Reload the Activity to reconnect."

        Rejected ->
            note Ui.danger "Session rejected — reload the Activity to sign in again."


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



-- SESSION


sessionPanel : Bool -> Time.Zone -> String -> Maybe GameState -> Element Msg
sessionPanel facilitator zone draftGoal maybeGs =
    Ui.card
        [ Ui.sectionTitle "Session"
        , case maybeGs |> Maybe.andThen .session of
            Just s ->
                Element.column [ spacing Ui.sm, width fill ]
                    [ Element.paragraph [ Font.size 13 ]
                        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Goal  ")
                        , text s.goal
                        ]
                    , Element.wrappedRow [ spacing Ui.xs, Element.centerY ]
                        (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Session pool")
                            :: List.map stoneChip s.pool
                        )
                    , if facilitator then
                        Ui.ghostButton { onPress = Just EndSession, label = "End session" }

                      else
                        none
                    ]

            Nothing ->
                if facilitator then
                    Element.row [ spacing Ui.sm, width fill ]
                        [ Input.text
                            (inputAttrs ++ [ width fill, Ui.onEnter StartSession ])
                            { onChange = SessionGoalChanged
                            , text = draftGoal
                            , placeholder = Just (Input.placeholder [] (text "Session goal…"))
                            , label = Input.labelHidden "Session goal"
                            }
                        , Ui.primaryButton { onPress = Just StartSession, label = "Start session" }
                        ]

                else
                    placeholder "No session running."
        , sessionHistoryView zone
            (maybeGs |> Maybe.map .sessionHistory |> Maybe.withDefault [])
        ]


{-| The table's completed sessions, newest first: each one's start date, goal,
and how it landed. Hidden until a session has ended. -}
sessionHistoryView : Time.Zone -> List SessionSummary -> Element msg
sessionHistoryView zone history =
    if List.isEmpty history then
        none

    else
        Element.column [ spacing Ui.xs, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Past sessions")
                :: List.map (pastSessionRow zone) history
            )


pastSessionRow : Time.Zone -> SessionSummary -> Element msg
pastSessionRow zone s =
    Element.row [ width fill, spacing Ui.sm ]
        [ el
            [ Font.family Ui.mono
            , Font.size 11
            , Font.color Ui.inkSoft
            , Element.alignTop
            , width (px 76)
            ]
            (text (Format.date zone s.startedAt))
        , Element.paragraph [ Font.size 12, spacing 3 ]
            [ text s.goal
            , el [ Font.color (verdictColor s.outcome), Font.semiBold ]
                (text ("  " ++ verdictWord s.outcome))
            ]
        ]


{-| The leading word of a stored outcome string ("met (Boon, Boon)" → "met"). -}
verdictWord : String -> String
verdictWord outcome =
    outcome |> String.words |> List.head |> Maybe.withDefault outcome


verdictColor : String -> Element.Color
verdictColor outcome =
    case verdictWord outcome of
        "met" ->
            Ui.speakerColor 2

        "failed" ->
            Ui.danger

        _ ->
            Ui.inkSoft



-- STONES


rollPanel : Bool -> Maybe String -> Maybe GameState -> Element Msg
rollPanel facilitator myId maybeGs =
    Ui.card
        [ Ui.sectionTitle "Stones"
        , case maybeGs of
            Nothing ->
                placeholder "Loading stone pool…"

            Just gs ->
                let
                    committed =
                        List.foldl (\c acc -> acc + c.count) 0 gs.committedBoons

                    myAddBoons =
                        countProposals myId "add-boon" gs.proposals
                in
                Element.column [ spacing Ui.md, width fill ]
                    [ Element.wrappedRow [ spacing Ui.xs ] (List.map stoneChip gs.stonePool)
                    , el [ Font.size 12, Font.color Ui.inkSoft ]
                        (text (poolSummary (List.length gs.stonePool) committed))
                    , case gs.pendingRoll of
                        Nothing ->
                            Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                                (Ui.ghostButton { onPress = Just AddBoon, label = "Add boon" }
                                    :: pendingHint myAddBoons
                                    ++ onlyFacilitator facilitator
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
                    , proposalsPanel facilitator gs.proposals
                    ]
        ]


{-| Facilitator's queue of player-initiated stone changes awaiting a decision.
Hidden for players and when empty.
-}
proposalsPanel : Bool -> List Proposal -> Element Msg
proposalsPanel facilitator proposals =
    if not facilitator || List.isEmpty proposals then
        none

    else
        Element.column [ spacing Ui.sm, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Proposals")
                :: List.map proposalRow proposals
            )


proposalRow : Proposal -> Element Msg
proposalRow p =
    Element.row [ width fill, spacing Ui.sm, Element.centerY ]
        [ Element.paragraph [ Font.size 12 ]
            [ text (p.proposerName ++ " — " ++ describeProposal p) ]
        , el [ Element.alignRight ]
            (Ui.ghostButton { onPress = Just (RejectProposal p.id), label = "Reject" })
        , Ui.primaryButton { onPress = Just (AcceptProposal p.id), label = "Accept" }
        ]


describeProposal : Proposal -> String
describeProposal p =
    case ( p.kind, p.delta >= 0 ) of
        ( "add-boon", _ ) ->
            "add a boon to the pool"

        ( "pledge", True ) ->
            "pledge a boon"

        ( "pledge", False ) ->
            "withdraw a boon"

        _ ->
            p.kind


countProposals : Maybe String -> String -> List Proposal -> Int
countProposals myId kind proposals =
    case myId of
        Just id ->
            List.length
                (List.filter (\p -> p.proposerId == id && p.kind == kind) proposals)

        Nothing ->
            0


{-| A muted "(n pending)" note for the proposer, or nothing when there are none.
-}
pendingHint : Int -> List (Element msg)
pendingHint n =
    if n <= 0 then
        []

    else
        [ el [ Font.size 11, Font.color Ui.inkSoft ]
            (text ("(" ++ String.fromInt n ++ " pending)"))
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


characterSheets : Bool -> Maybe String -> Maybe GameState -> Element Msg
characterSheets facilitator myId maybeGs =
    Ui.card
        [ Ui.sectionTitle "Characters"
        , case maybeGs of
            Nothing ->
                placeholder "Loading character sheets…"

            Just gs ->
                Element.wrappedRow [ spacing Ui.md, width fill ]
                    (List.map (characterSheet facilitator myId gs) gs.characters)
        ]


characterSheet : Bool -> Maybe String -> GameState -> CharacterSheet -> Element Msg
characterSheet facilitator myId gs ch =
    let
        mine =
            ch.ownerId /= Nothing && ch.ownerId == myId

        editable =
            facilitator || mine || ch.ownerId == Nothing

        pendingPledges =
            if mine then
                countProposals myId "pledge" gs.proposals

            else
                0
    in
    Element.column
        [ spacing Ui.sm
        , padding Ui.md
        , width (fill |> minimum 240)
        , Border.color Ui.line
        , Border.width 1
        , Border.rounded 6
        ]
        [ ownerRow facilitator mine ch
        , field editable ch NameField "Name" ch.name
        , field editable ch NotableFeaturesField "Notable features" ch.notableFeatures
        , field editable ch ArchetypeField "Archetype" ch.archetype
        , field editable ch DesireField "Desire" ch.desire
        , field editable ch QuestField "Quest" ch.quest
        , field editable ch ConditionField "Condition" ch.condition
        , notesField editable ch
        , fateRow facilitator ch
        , commitRow mine (committedBoonsForSlot ch.slot gs.committedBoons) pendingPledges
        ]


{-| Who holds this sheet, and the claim / release control. Players claim an
unclaimed sheet; the owner (or facilitator) can release it. -}
ownerRow : Bool -> Bool -> CharacterSheet -> Element Msg
ownerRow facilitator mine ch =
    let
        ( label, action ) =
            if mine then
                ( "Your character"
                , Just (Ui.ghostButton { onPress = Just (ReleaseSlot ch.slot), label = "Release" })
                )

            else if ch.ownerId == Nothing then
                ( "Unclaimed"
                , if facilitator then
                    Nothing

                  else
                    Just (Ui.ghostButton { onPress = Just (ClaimSlot ch.slot), label = "Claim" })
                )

            else
                ( "Claimed", Nothing )
    in
    Element.row [ width fill, spacing Ui.sm, Element.centerY ]
        (el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
            :: (case action of
                    Just btn ->
                        [ el [ Element.alignRight ] btn ]

                    Nothing ->
                        []
               )
        )


field : Bool -> CharacterSheet -> CharacterField -> String -> String -> Element Msg
field editable ch fieldTag label value =
    if editable then
        Input.text
            (inputAttrs ++ [ Ui.onBlur (CharacterFieldBlur ch.slot) ])
            { onChange = CharacterFieldInput ch.slot fieldTag
            , text = value
            , placeholder = Nothing
            , label = fieldLabel label
            }

    else
        readOnlyField label value


notesField : Bool -> CharacterSheet -> Element Msg
notesField editable ch =
    if editable then
        Input.multiline
            (inputAttrs ++ [ height (px 72), Ui.onBlur (CharacterFieldBlur ch.slot) ])
            { onChange = CharacterFieldInput ch.slot NotesField
            , text = ch.notes
            , placeholder = Nothing
            , label = fieldLabel "Notes"
            , spellcheck = False
            }

    else
        readOnlyField "Notes" ch.notes


readOnlyField : String -> String -> Element msg
readOnlyField label value =
    Element.column [ spacing Ui.xs, width fill ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
        , Element.paragraph
            (inputAttrs ++ [ Font.color Ui.inkSoft ])
            [ text
                (if String.trim value == "" then
                    "—"

                 else
                    value
                )
            ]
        ]


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


{-| Boons pledged into the next roll. The count shows on every sheet; only the
sheet's owner gets the `+` / `−` and a note of their unresolved pledges. -}
commitRow : Bool -> Int -> Int -> Element Msg
commitRow mine pledged pending =
    Element.row [ spacing Ui.sm, Element.centerY ]
        ([ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Pledged")
         , el [ Font.semiBold, width (px 20), Font.center ] (text (String.fromInt pledged))
         ]
            ++ (if mine then
                    Ui.ghostButton { onPress = Just CommitBoonDecrement, label = "−" }
                        :: Ui.ghostButton { onPress = Just CommitBoonIncrement, label = "+" }
                        :: pendingHint pending

                else
                    []
               )
        )


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
