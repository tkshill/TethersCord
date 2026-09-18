module View.Moves exposing (view)

{-| The Moves card, shown once the viewer holds a sheet: the once-per-session
abilities (Alter / Add a Detail / Gain Insight), Complicate against
another claimed sheet, and the any-time Accept Compel.

-- OFF while testing simplified interface (roadmap section 23.4): every entry
here used to be a button posting a proposal for the facilitator to accept or
reject. The `Msg` constructors (`UseAbility`, `SuggestCompel`,
`AcceptCompelMove`), their `Effect`s, `Api` calls, and the worker's proposal
routes are all still live and untouched — only this card's `onPress` hooks
are gone, so it now reads as a reminder of what a player can say at the
table, not a control that posts anything. Re-wiring is a search for this
comment.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Kind
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, accordionHeaderWith, characterLabel, tip)


{-| The four once-per-session (or fewer) abilities `remainingSummary` counts
against — every `Kind.AbilityKind` constructor.
-}
allAbilities : List Kind.AbilityKind
allAbilities =
    [ Kind.HelpOut, Kind.AddDetail, Kind.GainInsight, Kind.SuggestCompel ]


type alias Props =
    { open : Bool }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    case myOwnedSheet ctx.myId gs of
        Nothing ->
            none

        Just ch ->
            Ui.card
                (accordionHeaderWith props.open (Ui.sectionTitle Copy.movesTitle) (ToggleLeftSection MovesSection) (remainingSummary gs ch)
                    :: (if props.open then
                            [ abilityRow gs ch
                            , suggestCompelRow gs ch
                            , Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
                                [ el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.anyTime)
                                , tip "Accept Compel" (moveLabel Copy.acceptCompel)
                                ]
                            ]

                        else
                            []
                       )
                )


{-| "n of 4 left", shown beside the card title whether the accordion section is
open or closed (roadmap section 24, the 1c layout variant) — the one thing
about a character's Moves worth seeing at a glance without opening the card.
-}
remainingSummary : GameState -> CharacterSheet -> Element msg
remainingSummary gs ch =
    let
        remaining =
            List.length (List.filter (\k -> not (abilityUsed ch.slot k gs.usedAbilities)) allAbilities)
    in
    el [ Font.size 11, Font.color Ui.inkSoft ]
        (text (Copy.movesRemainingSummary remaining (List.length allAbilities)))


myOwnedSheet : Maybe String -> GameState -> Maybe CharacterSheet
myOwnedSheet myId gs =
    gs.characters
        |> List.filter (\c -> c.ownerId /= Nothing && c.ownerId == myId)
        |> List.head


abilityRow : GameState -> CharacterSheet -> Element Msg
abilityRow gs ch =
    if gs.session == Nothing then
        el [ Font.size 12, Font.color Ui.inkSoft ]
            (text Copy.abilitiesNeedSession)

    else
        let
            entry kind label =
                let
                    suffix =
                        if abilityUsed ch.slot kind gs.usedAbilities then
                            Copy.usedSuffix

                        else
                            ""
                in
                tip label (moveLabel (label ++ suffix))
        in
        Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
            [ el [ Font.size 11, Font.color Ui.inkSoft ] (text Copy.oncePerSession)
            , entry Kind.HelpOut Copy.helpOut
            , entry Kind.AddDetail Copy.addDetail
            , entry Kind.GainInsight Copy.gainInsight
            ]


{-| Complicate: a once-per-session ability that names another player's
character. One label per other claimed sheet; "(used)" once raised.
-}
suggestCompelRow : GameState -> CharacterSheet -> Element Msg
suggestCompelRow gs ch =
    if gs.session == Nothing then
        none

    else
        let
            used =
                abilityUsed ch.slot Kind.SuggestCompel gs.usedAbilities

            targets =
                gs.characters
                    |> List.filter (\c -> c.slot /= ch.slot && c.ownerId /= Nothing)

            suffix =
                if used then
                    Copy.usedSuffix

                else
                    ""
        in
        Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
            (tip "Complicate"
                (el [ Font.size 11, Font.color Ui.inkSoft ] (text (Copy.suggestCompel ++ suffix)))
                :: (if used then
                        []

                    else if List.isEmpty targets then
                        [ el [ Font.size 12, Font.color Ui.inkSoft ] (text Copy.noOtherPlayers) ]

                    else
                        List.map (\c -> moveLabel (characterLabel c)) targets
                   )
            )


{-| What was `Ui.ghostButton` before 23.4 — same size and position in the
row, but plain text: nothing here posts anymore.
-}
moveLabel : String -> Element Msg
moveLabel label =
    el
        [ Font.size 13
        , Font.color Ui.ink
        ]
        (text label)
