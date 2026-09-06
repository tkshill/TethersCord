module Kind exposing
    ( AbilityKind(..)
    , ProposalKind(..)
    , abilityToString
    , decodeAbilityKind
    , decodeProposalKind
    , proposalKindToString
    )

{-| Typed names for the two enumerations the game passes over the wire as
strings: the kind of a queued `Proposal` and the once-per-session `AbilityKind`.

Kept in their own module (rather than in `Types` beside `Msg`) because several
constructor names — `SuggestCompel`, `AddBoon` — already exist as `Msg`
variants, and Elm's constructors must be unique within a module.

Bringing the client to parity with the Worker's `ProposalKind` / `AbilityKind`
unions means adding a kind now produces a compile error at every `case` that
must handle it, and `View.describeProposal` is a total match with no string
fall-through.

-}

import Json.Decode as Decode exposing (Decoder)


{-| The four abilities a player calls on once per session, each gated by
facilitator approval. A subset of `ProposalKind`, reached through
`AbilityProposal`.
-}
type AbilityKind
    = HelpOut
    | AddDetail
    | GainInsight
    | SuggestCompel


{-| What a queued proposal asks for. `AbilityProposal` wraps the ability kinds;
the rest are proposal-only.
-}
type ProposalKind
    = AddBoon
    | Pledge
    | AbilityProposal AbilityKind
    | AcceptCompel
    | UseFloating


abilityToString : AbilityKind -> String
abilityToString kind =
    case kind of
        HelpOut ->
            "help-out"

        AddDetail ->
            "add-detail"

        GainInsight ->
            "gain-insight"

        SuggestCompel ->
            "suggest-compel"


proposalKindToString : ProposalKind -> String
proposalKindToString kind =
    case kind of
        AddBoon ->
            "add-boon"

        Pledge ->
            "pledge"

        AbilityProposal ability ->
            abilityToString ability

        AcceptCompel ->
            "accept-compel"

        UseFloating ->
            "use-floating"


abilityFromString : String -> Maybe AbilityKind
abilityFromString s =
    case s of
        "help-out" ->
            Just HelpOut

        "add-detail" ->
            Just AddDetail

        "gain-insight" ->
            Just GainInsight

        "suggest-compel" ->
            Just SuggestCompel

        _ ->
            Nothing


proposalKindFromString : String -> Maybe ProposalKind
proposalKindFromString s =
    case s of
        "add-boon" ->
            Just AddBoon

        "pledge" ->
            Just Pledge

        "accept-compel" ->
            Just AcceptCompel

        "use-floating" ->
            Just UseFloating

        _ ->
            Maybe.map AbilityProposal (abilityFromString s)


decodeAbilityKind : Decoder AbilityKind
decodeAbilityKind =
    Decode.string
        |> Decode.andThen
            (\s ->
                case abilityFromString s of
                    Just kind ->
                        Decode.succeed kind

                    Nothing ->
                        Decode.fail ("Unknown ability kind " ++ s)
            )


decodeProposalKind : Decoder ProposalKind
decodeProposalKind =
    Decode.string
        |> Decode.andThen
            (\s ->
                case proposalKindFromString s of
                    Just kind ->
                        Decode.succeed kind

                    Nothing ->
                        Decode.fail ("Unknown proposal kind " ++ s)
            )
