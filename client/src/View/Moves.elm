module View.Moves exposing (view)

{-| The Moves card, shown once the viewer holds a sheet: the once-per-session
abilities (Help Out / Add a Detail / Gain Insight), Suggest Compel against
another claimed sheet, and the any-time Accept Compel. Every one is a request
the facilitator approves.
-}

import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Kind
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, characterLabel, latestProposalId, withdrawLink)


view : ViewContext -> GameState -> Element Msg
view ctx gs =
    case myOwnedSheet ctx.myId gs of
        Nothing ->
            none

        Just ch ->
            Ui.card
                [ Ui.sectionTitle "Moves"
                , abilityRow ctx.myId gs ch
                , suggestCompelRow ctx.myId gs ch
                , let
                    pendingId =
                        latestProposalId ctx.myId Kind.AcceptCompel gs.proposals
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
                        latestProposalId myId (Kind.AbilityProposal kind) gs.proposals

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
            , button Kind.HelpOut "Help Out" overcomeRoll
            , button Kind.AddDetail "Add a Detail" True
            , button Kind.GainInsight "Gain Insight" True
            ]


{-| Suggest Compel: a once-per-session ability that names another player's
character. One button per other claimed sheet; the whole row collapses to a
"(used)" / "(pending)" note once raised.
-}
suggestCompelRow : Maybe String -> GameState -> CharacterSheet -> Element Msg
suggestCompelRow myId gs ch =
    if gs.session == Nothing then
        none

    else
        let
            used =
                abilityUsed ch.slot Kind.SuggestCompel gs.usedAbilities

            pendingId =
                latestProposalId myId (Kind.AbilityProposal Kind.SuggestCompel) gs.proposals

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
