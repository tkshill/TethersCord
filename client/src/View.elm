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
        , none
        , padding
        , px
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
        , Ui.errorNote model.error
        , sessionPanel facilitator model.confirming model.newSessionGoal model.goalEdit model.timeZone model.gameState
        , rollPanel facilitator myId model.proposalDrafts model.gameState
        , movesCard myId model.gameState
        , characterSheets facilitator myId model.selectedSlot model.gameState
        , messageLog facilitator model.confirming model.timeZone model.gameState
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


sessionPanel : Bool -> Maybe String -> String -> String -> Time.Zone -> Maybe GameState -> Element Msg
sessionPanel facilitator confirming draftGoal goalEdit zone maybeGs =
    Ui.card
        [ Ui.sectionTitle "Session"
        , case maybeGs |> Maybe.andThen .session of
            Just s ->
                Element.column [ spacing Ui.sm, width fill ]
                    [ if facilitator then
                        goalEditor confirming goalEdit s.goal

                      else
                        Element.paragraph [ Font.size 13 ]
                            [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Goal  ")
                            , text s.goal
                            ]
                    , Element.wrappedRow [ spacing Ui.xs, Element.centerY ]
                        (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Session pool")
                            :: List.map stoneChip s.pool
                        )
                    , if facilitator then
                        Ui.confirmButton
                            { armed = confirming == Just "end-session"
                            , idle = "End session"
                            , confirm = "End session"
                            , onArm = RequestConfirm "end-session"
                            , onConfirm = EndSession
                            , onCancel = CancelConfirm
                            }

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


{-| The facilitator's mid-session goal field. Shows the running goal until it is
edited; the confirm-gated Save writes it back. An empty or unchanged field
leaves the goal alone. -}
goalEditor : Maybe String -> String -> String -> Element Msg
goalEditor confirming goalEdit currentGoal =
    let
        shown =
            if String.trim goalEdit == "" then
                currentGoal

            else
                goalEdit

        changed =
            String.trim shown /= "" && shown /= currentGoal
    in
    Element.row [ spacing Ui.sm, width fill ]
        [ Input.text
            (inputAttrs ++ [ width fill ])
            { onChange = SessionGoalEditChanged
            , text = shown
            , placeholder = Nothing
            , label = Input.labelHidden "Edit session goal"
            }
        , if changed then
            Ui.confirmButton
                { armed = confirming == Just "edit-goal"
                , idle = "Save goal"
                , confirm = "Save goal"
                , onArm = RequestConfirm "edit-goal"
                , onConfirm = SaveSessionGoal
                , onCancel = CancelConfirm
                }

          else
            none
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


rollPanel : Bool -> Maybe String -> Dict String String -> Maybe GameState -> Element Msg
rollPanel facilitator myId drafts maybeGs =
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

                    target =
                        gs.overcome
                            |> Maybe.andThen
                                (\oc -> characterAtSlot oc.targetSlot gs.characters)

                    amTarget =
                        case target of
                            Just t ->
                                t.ownerId /= Nothing && t.ownerId == myId

                            Nothing ->
                                False

                    -- The facilitator can always roll; during an overcome the
                    -- target player can too.
                    canRoll =
                        facilitator || amTarget

                    -- A reroll during an overcome is bought with the target's
                    -- boons, so it needs at least that many.
                    rerollAffordable =
                        case target of
                            Just t ->
                                t.fate >= overcomeRerollCost

                            Nothing ->
                                True

                    costSuffix =
                        " (" ++ String.fromInt overcomeRerollCost ++ " boons)"

                    rerollLabel =
                        if gs.overcome == Nothing then
                            "Reroll"

                        else if amTarget then
                            -- Press Fate: the target buying their own reroll.
                            "Press Fate" ++ costSuffix

                        else
                            "Reroll" ++ costSuffix
                in
                Element.column [ spacing Ui.md, width fill ]
                    [ overcomeBlock facilitator target gs.characters
                    , Element.wrappedRow [ spacing Ui.xs ]
                        (List.map stoneChip gs.stonePool
                            ++ List.repeat committed
                                (Ui.pledgedStoneChip Ui.boonFill "Pledged")
                        )
                    , el [ Font.size 12, Font.color Ui.inkSoft ]
                        (text ("Bag of " ++ String.fromInt (List.length gs.stonePool + committed)))
                    , floatingBoonsBlock facilitator myId gs
                    , case gs.pendingRoll of
                        Nothing ->
                            Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                                (Ui.ghostButton { onPress = Just AddBoon, label = "Add boon" }
                                    :: pendingHint myAddBoons (latestProposalId myId "add-boon" gs.proposals)
                                    ++ onlyWhen canRoll
                                        [ Ui.primaryButton { onPress = Just RollStones, label = "Roll" } ]
                                )

                        Just pending ->
                            Element.column [ spacing Ui.sm, width fill ]
                                [ Element.wrappedRow [ spacing Ui.xs ]
                                    (el [ Font.size 12, Font.color Ui.inkSoft ] (text "Rolled")
                                        :: List.map stoneChip pending.chosen
                                    )
                                , Element.wrappedRow [ spacing Ui.sm ]
                                    (onlyWhen canRoll
                                        [ Ui.ghostButton
                                            { onPress =
                                                if rerollAffordable then
                                                    Just RerollStones

                                                else
                                                    Nothing
                                            , label = rerollLabel
                                            }
                                        ]
                                        ++ onlyWhen facilitator
                                            [ Ui.primaryButton { onPress = Just AcceptRoll, label = "Accept" } ]
                                    )
                                ]
                    , proposalsPanel facilitator drafts gs.characters gs.proposals
                    ]
        ]


{-| The session's floating boons — context the facilitator has approved that
belongs to no one. Any player can ask to spend one on the roll (a Highlight the
facilitator then approves); the button is muted once that request is queued. -}
floatingBoonsBlock : Bool -> Maybe String -> GameState -> Element Msg
floatingBoonsBlock facilitator myId gs =
    if List.isEmpty gs.floatingBoons then
        none

    else
        let
            iOwnASheet =
                List.any (\c -> c.ownerId /= Nothing && c.ownerId == myId) gs.characters

            row fb =
                let
                    queued =
                        List.any
                            (\p -> p.kind == "use-floating" && p.floatingId == Just fb.id)
                            gs.proposals
                in
                Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
                    [ Ui.pledgedStoneChip Ui.boonFill "Floating"
                    , Element.paragraph [ Font.size 12 ] [ text fb.text ]
                    , if queued then
                        el [ Font.size 11, Font.color Ui.inkSoft, Element.alignRight ] (text "(requested)")

                      else if iOwnASheet && not facilitator then
                        el [ Element.alignRight ]
                            (Ui.ghostButton { onPress = Just (UseFloatingBoon fb.id), label = "Use" })

                      else
                        none
                    ]
        in
        Element.column [ spacing Ui.xs, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Floating boons")
                :: List.map row gs.floatingBoons
            )


{-| The overcome line. When one is open it names the target and, for the
facilitator, offers "Call off"; otherwise the facilitator gets a button per
character to open one. Nothing shows for a player with no overcome running. -}
overcomeBlock : Bool -> Maybe CharacterSheet -> List CharacterSheet -> Element Msg
overcomeBlock facilitator target characters =
    case target of
        Just t ->
            Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
                (el [ Font.size 12, Font.semiBold ]
                    (text ("Overcome — " ++ characterLabel t))
                    :: onlyWhen facilitator
                        [ Ui.ghostButton { onPress = Just CancelOvercome, label = "Call off" } ]
                )

        Nothing ->
            if facilitator then
                Element.wrappedRow [ spacing Ui.xs, Element.centerY ]
                    (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Start overcome")
                        :: List.map
                            (\c ->
                                Ui.ghostButton
                                    { onPress = Just (StartOvercome c.slot)
                                    , label = characterLabel c
                                    }
                            )
                            characters
                    )

            else
                none


characterAtSlot : Int -> List CharacterSheet -> Maybe CharacterSheet
characterAtSlot slot characters =
    characters |> List.filter (\c -> c.slot == slot) |> List.head


{-| Facilitator's queue of player-initiated requests awaiting a decision. Hidden
for players and when empty. `drafts` holds the context note typed for each
Add a Detail / Gain Insight, keyed by proposal id so the rows do not share one
field. -}
proposalsPanel : Bool -> Dict String String -> List CharacterSheet -> List Proposal -> Element Msg
proposalsPanel facilitator drafts characters proposals =
    if not facilitator || List.isEmpty proposals then
        none

    else
        Element.column [ spacing Ui.sm, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Proposals")
                :: List.map (proposalRow drafts characters) proposals
            )


proposalRow : Dict String String -> List CharacterSheet -> Proposal -> Element Msg
proposalRow drafts characters p =
    let
        needsContext =
            p.kind == "add-detail" || p.kind == "gain-insight"

        draft =
            Dict.get p.id drafts |> Maybe.withDefault ""

        acceptEnabled =
            not needsContext || String.trim draft /= ""

        controls =
            Element.row [ spacing Ui.sm, Element.centerY, Element.alignRight ]
                [ Ui.ghostButton { onPress = Just (RejectProposal p.id), label = "Reject" }
                , Ui.primaryButton
                    { onPress =
                        if acceptEnabled then
                            Just (AcceptProposal p.id)

                        else
                            Nothing
                    , label = "Accept"
                    }
                ]
    in
    Element.column [ width fill, spacing Ui.xs ]
        [ Element.wrappedRow [ width fill, spacing Ui.sm, Element.centerY ]
            [ Element.paragraph [ Font.size 12 ]
                [ text (p.proposerName ++ " — " ++ describeProposal characters p) ]
            , controls
            ]
        , if needsContext then
            Input.text
                (inputAttrs ++ [ width fill ])
                { onChange = ProposalDraftChanged p.id
                , text = draft
                , placeholder = Just (Input.placeholder [] (text "Context this boon represents…"))
                , label = Input.labelHidden "Floating boon context"
                }

          else
            none
        ]


describeProposal : List CharacterSheet -> Proposal -> String
describeProposal characters p =
    case ( p.kind, p.delta >= 0 ) of
        ( "add-boon", _ ) ->
            "add a boon to the pool"

        ( "pledge", True ) ->
            "highlight an aspect (pledge a boon)"

        ( "pledge", False ) ->
            "withdraw a highlighted boon"

        ( "help-out", _ ) ->
            "Help Out — reroll the overcome"

        ( "add-detail", _ ) ->
            "Add a Detail — a floating boon"

        ( "gain-insight", _ ) ->
            "Gain Insight — a floating boon"

        ( "suggest-compel", _ ) ->
            "Suggest Compel on "
                ++ (p.targetSlot
                        |> Maybe.andThen (\s -> characterAtSlot s characters)
                        |> Maybe.map characterLabel
                        |> Maybe.withDefault "another character"
                   )
                ++ " (+1 / +2 boons)"

        ( "accept-compel", _ ) ->
            "Accept Compel — take a complication for 2 boons"

        ( "use-floating", _ ) ->
            "spend a floating boon on the roll"

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


{-| The id of the proposer's most recently queued proposal of `kind`, if any.
This is what the "withdraw" link beside a "(pending)" hint pulls back — the
latest matching one, since abilities and Add boon queue at most one and a pledge
is applied as a net delta. -}
latestProposalId : Maybe String -> String -> List Proposal -> Maybe String
latestProposalId myId kind proposals =
    myId
        |> Maybe.andThen
            (\id ->
                proposals
                    |> List.filter (\p -> p.proposerId == id && p.kind == kind)
                    |> List.reverse
                    |> List.head
            )
        |> Maybe.map .id


{-| A muted "(n pending)" note for the proposer, with a "withdraw" link for the
proposal it refers to. Nothing when there are none. -}
pendingHint : Int -> Maybe String -> List (Element Msg)
pendingHint n maybeId =
    if n <= 0 then
        []

    else
        [ Element.row [ spacing Ui.xs, Element.centerY ]
            [ el [ Font.size 11, Font.color Ui.inkSoft ]
                (text ("(" ++ String.fromInt n ++ " pending)"))
            , withdrawLink maybeId
            ]
        ]


{-| A small "withdraw" link for whichever pending proposal a hint refers to.
Renders nothing when there is no id to act on. -}
withdrawLink : Maybe String -> Element Msg
withdrawLink maybeId =
    case maybeId of
        Just pid ->
            Input.button
                [ Font.size 11
                , Font.color Ui.inkSoft
                , Font.underline
                , Element.mouseOver [ Font.color Ui.accent ]
                ]
                { onPress = Just (WithdrawProposal pid), label = text "withdraw" }

        Nothing ->
            none


{-| The given elements when `cond` holds, an empty list otherwise. Used to keep
roll-lifecycle controls out of the hands of anyone who may not use them.
-}
onlyWhen : Bool -> List (Element msg) -> List (Element msg)
onlyWhen cond elements =
    if cond then
        elements

    else
        []


{-| Boons the overcome target spends to Reroll. Mirrors the worker's
`REROLL_COST`. -}
overcomeRerollCost : Int
overcomeRerollCost =
    2


stoneChip : Stone -> Element msg
stoneChip stone =
    case stone of
        Boon ->
            Ui.stoneChip Ui.boonFill "Boon"

        Bane ->
            Ui.stoneChip Ui.baneFill "Bane"



-- MOVES


{-| The player's own abilities and moves, shown once they hold a sheet. Every
one is a request the facilitator approves; a button mutes to "(pending)" once
raised and, for the once-per-session abilities, "(used)" after approval. -}
movesCard : Maybe String -> Maybe GameState -> Element Msg
movesCard myId maybeGs =
    case maybeGs |> Maybe.andThen (\gs -> Maybe.map (Tuple.pair gs) (myOwnedSheet myId gs)) of
        Nothing ->
            none

        Just ( gs, ch ) ->
            Ui.card
                [ Ui.sectionTitle "Moves"
                , abilityRow myId gs ch
                , suggestCompelRow myId gs ch
                , let
                    pendingId =
                        latestProposalId myId "accept-compel" gs.proposals
                  in
                  Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
                    (el [ Font.size 11, Font.color Ui.inkSoft ] (text "Any time")
                        :: moveButton (pendingId /= Nothing) "Accept Compel" AcceptCompelMove
                        :: (if pendingId == Nothing then
                                []

                            else
                                [ withdrawLink pendingId ]
                           )
                    )
                ]


myOwnedSheet : Maybe String -> GameState -> Maybe CharacterSheet
myOwnedSheet myId gs =
    gs.characters
        |> List.filter (\c -> c.ownerId /= Nothing && c.ownerId == myId)
        |> List.head


abilityRow : Maybe String -> GameState -> CharacterSheet -> Element Msg
abilityRow myId gs ch =
    if gs.session == Nothing then
        el [ Font.size 12, Font.color Ui.inkSoft ]
            (text "Abilities open once a session is running.")

    else
        let
            overcomeRoll =
                gs.overcome /= Nothing && gs.pendingRoll /= Nothing

            button kind label available =
                let
                    used =
                        abilityUsed ch.slot kind gs.usedAbilities

                    pendingId =
                        latestProposalId myId kind gs.proposals

                    pending =
                        pendingId /= Nothing

                    suffix =
                        if used then
                            " (used)"

                        else if pending then
                            " (pending)"

                        else
                            ""

                    btn =
                        moveButton (used || pending || not available) (label ++ suffix) (UseAbility kind)
                in
                if pending then
                    Element.row [ spacing Ui.xs, Element.centerY ] [ btn, withdrawLink pendingId ]

                else
                    btn
        in
        Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
            [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Once per session")
            , button "help-out" "Help Out" overcomeRoll
            , button "add-detail" "Add a Detail" True
            , button "gain-insight" "Gain Insight" True
            ]


{-| Suggest Compel: a once-per-session ability that names another player's
character. One button per other claimed sheet; the whole row collapses to a
"(used)" / "(pending)" note once raised. -}
suggestCompelRow : Maybe String -> GameState -> CharacterSheet -> Element Msg
suggestCompelRow myId gs ch =
    if gs.session == Nothing then
        none

    else
        let
            used =
                abilityUsed ch.slot "suggest-compel" gs.usedAbilities

            pendingId =
                latestProposalId myId "suggest-compel" gs.proposals

            pending =
                pendingId /= Nothing

            targets =
                gs.characters
                    |> List.filter (\c -> c.slot /= ch.slot && c.ownerId /= Nothing)

            suffix =
                if used then
                    " (used)"

                else if pending then
                    " (pending)"

                else
                    ""
        in
        Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
            (el [ Font.size 11, Font.color Ui.inkSoft ] (text ("Suggest Compel" ++ suffix))
                :: (if used then
                        []

                    else if pending then
                        [ withdrawLink pendingId ]

                    else if List.isEmpty targets then
                        [ el [ Font.size 12, Font.color Ui.inkSoft ] (text "no other players") ]

                    else
                        List.map
                            (\c ->
                                Ui.ghostButton
                                    { onPress = Just (SuggestCompel c.slot)
                                    , label = characterLabel c
                                    }
                            )
                            targets
                   )
            )


{-| A ghost button that goes inert (no `onPress`) when `disabled`. -}
moveButton : Bool -> String -> Msg -> Element Msg
moveButton disabled label msg =
    Ui.ghostButton
        { onPress =
            if disabled then
                Nothing

            else
                Just msg
        , label = label
        }



-- CHARACTERS


characterSheets : Bool -> Maybe String -> Int -> Maybe GameState -> Element Msg
characterSheets facilitator myId selectedSlot maybeGs =
    Ui.card
        [ Ui.sectionTitle "Characters"
        , case maybeGs of
            Nothing ->
                placeholder "Loading character sheets…"

            Just gs ->
                let
                    selected =
                        case List.filter (\c -> c.slot == selectedSlot) gs.characters of
                            first :: _ ->
                                Just first

                            [] ->
                                List.head gs.characters
                in
                Element.column [ spacing Ui.md, width fill ]
                    [ tabStrip myId selectedSlot gs.characters
                    , case selected of
                        Just ch ->
                            characterSheet facilitator myId gs ch

                        Nothing ->
                            placeholder "No character sheets."
                    ]
        ]


{-| One tab per sheet, labelled by character name (or a slot number until one is
set) with a "(you)" marker on the sheet the viewer holds. -}
tabStrip : Maybe String -> Int -> List CharacterSheet -> Element Msg
tabStrip myId selectedSlot characters =
    Element.wrappedRow [ spacing Ui.xs, width fill ]
        (List.map
            (\c -> Ui.tab (c.slot == selectedSlot) (tabLabel myId c) (SelectSlot c.slot))
            characters
        )


tabLabel : Maybe String -> CharacterSheet -> String
tabLabel myId ch =
    if ch.ownerId /= Nothing && ch.ownerId == myId then
        characterLabel ch ++ " (you)"

    else
        characterLabel ch


{-| A character's name, falling back to its slot number. Matches the worker's
`characterLabel` used in log lines. -}
characterLabel : CharacterSheet -> String
characterLabel ch =
    if String.trim ch.name /= "" then
        ch.name

    else
        "Character " ++ String.fromInt (ch.slot + 1)


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

        pendingPledgeId =
            if mine then
                latestProposalId myId "pledge" gs.proposals

            else
                Nothing
    in
    Element.column
        [ spacing Ui.sm
        , padding Ui.md
        , width fill
        , Border.color Ui.line
        , Border.width 1
        , Border.rounded 6
        ]
        [ ownerRow facilitator mine ch
        , boonsBlock facilitator mine ch (committedBoonsForSlot ch.slot gs.committedBoons) pendingPledges pendingPledgeId
        , field editable ch NameField "Name" ch.name
        , field editable ch NotableFeaturesField "Notable features" ch.notableFeatures
        , field editable ch ArchetypeField "Archetype" ch.archetype
        , field editable ch DesireField "Desire" ch.desire
        , field editable ch QuestField "Quest" ch.quest
        , field editable ch ConditionField "Condition" ch.condition
        , notesField editable ch
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


{-| A character's boons, at the top of the sheet where a player can see their
spendable stones alongside the current roll. The boons show as circles; the ones
pledged into the next roll carry a centre dot rather than a separate count. The
facilitator gets a Grant `+` / `−`; the sheet's owner gets a Pledge `+` / `−`
and a note of any unresolved pledge proposals. -}
boonsBlock : Bool -> Bool -> CharacterSheet -> Int -> Int -> Maybe String -> Element Msg
boonsBlock facilitator mine ch pledged pending pendingId =
    Element.column [ spacing Ui.xs, width fill ]
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Boons")
        , boonCircles ch.fate pledged
        , Element.wrappedRow [ spacing Ui.sm, Element.centerY ]
            (grantControls facilitator ch ++ pledgeControls mine pending pendingId)
        ]


{-| `total` boon circles, the first `pledged` of them marked as pledged into the
next roll. -}
boonCircles : Int -> Int -> Element msg
boonCircles total pledged =
    if total <= 0 then
        el [ Font.size 12, Font.color Ui.inkSoft ] (text "None")

    else
        Element.wrappedRow [ spacing Ui.xs ]
            (List.range 1 total
                |> List.map (\i -> Ui.boonDot (i <= pledged))
            )


grantControls : Bool -> CharacterSheet -> List (Element Msg)
grantControls facilitator ch =
    if facilitator then
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Grant")
        , Ui.ghostButton { onPress = Just (FateDecrement ch.slot), label = "−" }
        , Ui.ghostButton { onPress = Just (FateIncrement ch.slot), label = "+" }
        ]

    else
        []


pledgeControls : Bool -> Int -> Maybe String -> List (Element Msg)
pledgeControls mine pending pendingId =
    if mine then
        -- "Highlight" is the player-facing name for pledging a boon to the roll.
        [ el [ Font.size 11, Font.color Ui.inkSoft ] (text "Highlight")
        , Ui.ghostButton { onPress = Just CommitBoonDecrement, label = "−" }
        , Ui.ghostButton { onPress = Just CommitBoonIncrement, label = "+" }
        ]
            ++ pendingHint pending pendingId

    else
        []


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


messageLog : Bool -> Maybe String -> Time.Zone -> Maybe GameState -> Element Msg
messageLog facilitator confirming zone maybeGs =
    Ui.card
        [ logHeader facilitator confirming maybeGs
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


logHeader : Bool -> Maybe String -> Maybe GameState -> Element Msg
logHeader facilitator confirming maybeGs =
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
                        (Ui.confirmButton
                            { armed = confirming == Just "clear-log"
                            , idle = "Clear log"
                            , confirm = "Clear log"
                            , onArm = RequestConfirm "clear-log"
                            , onConfirm = ClearLog
                            , onCancel = CancelConfirm
                            }
                        )
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
