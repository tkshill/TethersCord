module View.Helpers exposing
    ( ViewContext
    , characterLabel
    , countProposals
    , glossaryTitle
    , inputAttrs
    , latestProposalId
    , pendingHint
    , placeholder
    , stoneChip
    , tip
    , tipAttrs
    , withdrawLink
    )

{-| Small view helpers shared by more than one of the `View.*` section modules:
the `ViewContext` record threaded through every section, the proposal-count /
latest-id lookups, the "(n pending) · withdraw" hint, the bordered-input
attributes, the plain placeholder line, and the two glossary-tooltip helpers
that pair a label with its `Copy.Terms` gloss.
-}

import Copy
import Copy.Terms as Terms
import Element exposing (Element, el, none, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Attributes
import Kind
import Roll exposing (Stone(..))
import Time
import Types exposing (..)
import Ui


{-| The slices of `Model` every section needs. Computed once in `View.view` and
passed to each `View.*` module; a section that needs more model state takes its
own small record alongside this.
-}
type alias ViewContext =
    { facilitator : Bool
    , myId : Maybe String
    , zone : Time.Zone
    }


placeholder : String -> Element msg
placeholder label =
    el [ Font.size 13, Font.color Ui.inkSoft ] (text label)


{-| A section-card title carrying a native tooltip with its glossary gloss.
`label` is the card heading; `termKey` is the `Copy.Terms` name to look the gloss
up by (they differ where the card is plural, e.g. "Stones" / "Stone").
-}
glossaryTitle : String -> String -> Element msg
glossaryTitle label termKey =
    Ui.withTip (Terms.termShort termKey) (Ui.sectionTitle label)


{-| Wrap an inline label or button in a native tooltip for a glossary term,
looked up by name. An unknown name adds no tooltip. Shrink-wraps, so it is for
an element that is already its own size; for a full-width form field, put
`tipAttrs` on the input instead so its width is untouched.
-}
tip : String -> Element msg -> Element msg
tip termKey child =
    Ui.withTip (Terms.termShort termKey) child


{-| The `title`-attribute form of `tip`, to drop straight into an input's
attribute list so the tooltip covers the field without a wrapping element. Empty
list for an unknown term.
-}
tipAttrs : String -> List (Element.Attribute msg)
tipAttrs termKey =
    case Terms.termShort termKey of
        "" ->
            []

        gloss ->
            [ Element.htmlAttribute (Html.Attributes.title gloss) ]


inputAttrs : List (Element.Attribute msg)
inputAttrs =
    [ Element.padding Ui.sm
    , Border.color Ui.line
    , Border.width 1
    , Border.rounded 4
    , Font.size 13
    ]


{-| A character's name, falling back to its slot number. Matches the worker's
`characterLabel` used in log lines.
-}
characterLabel : CharacterSheet -> String
characterLabel ch =
    if String.trim ch.name /= "" then
        ch.name

    else
        Copy.characterFallback ch.slot


stoneChip : Stone -> Element msg
stoneChip stone =
    case stone of
        Boon ->
            Ui.stoneChip Ui.boonFill Copy.boonStone

        Bane ->
            Ui.stoneChip Ui.baneFill Copy.baneStone


countProposals : Maybe String -> Kind.ProposalKind -> List Proposal -> Int
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
is applied as a net delta.
-}
latestProposalId : Maybe String -> Kind.ProposalKind -> List Proposal -> Maybe String
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
proposal it refers to. Nothing when there are none.
-}
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
Renders nothing when there is no id to act on.
-}
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
                { onPress = Just (WithdrawProposal pid), label = text Copy.withdraw }

        Nothing ->
            none
