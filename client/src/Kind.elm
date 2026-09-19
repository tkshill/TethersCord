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
constructor names — `Complicate`, `AddBoon` — already exist as `Msg`
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
    = Alter
    | AddDetail
    | GainInsight
    | Complicate


{-| What a queued proposal asks for. `AbilityProposal` wraps the ability kinds;
the rest are proposal-only.
-}
type ProposalKind
    = AddBoon
    | Highlight
    | AbilityProposal AbilityKind
    | AcceptCompel
    | UseSessionBoon


abilityToString : AbilityKind -> String
abilityToString kind =
    case kind of
        Alter ->
            "alter"

        AddDetail ->
            "add-detail"

        GainInsight ->
            "gain-insight"

        Complicate ->
            "complicate"


proposalKindToString : ProposalKind -> String
proposalKindToString kind =
    case kind of
        AddBoon ->
            "add-boon"

        Highlight ->
            "highlight"

        AbilityProposal ability ->
            abilityToString ability

        AcceptCompel ->
            "accept-compel"

        UseSessionBoon ->
            "use-session-boon"


abilityFromString : String -> Maybe AbilityKind
abilityFromString s =
    case s of
        "alter" ->
            Just Alter

        "add-detail" ->
            Just AddDetail

        "gain-insight" ->
            Just GainInsight

        "complicate" ->
            Just Complicate

        _ ->
            Nothing


proposalKindFromString : String -> Maybe ProposalKind
proposalKindFromString s =
    case s of
        "add-boon" ->
            Just AddBoon

        "highlight" ->
            Just Highlight

        "accept-compel" ->
            Just AcceptCompel

        "use-session-boon" ->
            Just UseSessionBoon

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
