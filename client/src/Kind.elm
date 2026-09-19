module Kind exposing
    ( ProposalKind(..)
    , decodeProposalKind
    , proposalKindToString
    )

{-| The kind of a queued `Proposal`, at parity with the Worker's `ProposalKind`
union (`worker/src/types.ts`): a typed name for what a player asked the
facilitator to rule on. These are the five official move names except Overcome,
which needs no approval and so is never a proposal (`RULES.md`).

Kept in its own module (rather than in `Types` beside `Msg`) because several
constructor names — `Highlight`, `Complicate`, `AddDetail`, `Alter` — are also
the names of `Msg` variants, and Elm's constructors must be unique within a
module. Adding a kind now produces a compile error at every `case` that must
handle it, and `View.FacilitatorPanel.describeProposal` is a total match with no
string fall-through.

-}

import Json.Decode as Decode exposing (Decoder)


type ProposalKind
    = Highlight
    | Complicate
    | AddDetail
    | Alter
    | UseSessionBoon


proposalKindToString : ProposalKind -> String
proposalKindToString kind =
    case kind of
        Highlight ->
            "highlight"

        Complicate ->
            "complicate"

        AddDetail ->
            "add-detail"

        Alter ->
            "alter"

        UseSessionBoon ->
            "use-session-boon"


proposalKindFromString : String -> Maybe ProposalKind
proposalKindFromString s =
    case s of
        "highlight" ->
            Just Highlight

        "complicate" ->
            Just Complicate

        "add-detail" ->
            Just AddDetail

        "alter" ->
            Just Alter

        "use-session-boon" ->
            Just UseSessionBoon

        _ ->
            Nothing


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
