module CopyTermsTest exposing (suite)

{-| Sanity checks on the glossary data: every term is fully filled in, the flat
list matches the grouped one, and `termShort` resolves a known name and shrugs
off an unknown one.
-}

import Copy.Terms as Terms
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Copy.Terms"
        [ test "every term has a name, a short gloss, and a long definition" <|
            \_ ->
                Terms.terms
                    |> List.filter
                        (\t ->
                            String.trim t.term
                                == ""
                                || String.trim t.short
                                == ""
                                || String.trim t.long
                                == ""
                        )
                    |> Expect.equalLists []
        , test "the flat list is the grouped list concatenated" <|
            \_ ->
                List.length Terms.terms
                    |> Expect.equal
                        (Terms.groupedTerms
                            |> List.concatMap Tuple.second
                            |> List.length
                        )
        , test "term names are unique" <|
            \_ ->
                let
                    names =
                        List.map .term Terms.terms
                in
                List.length names
                    |> Expect.equal (List.length (dedupe names))
        , test "termShort resolves a known term" <|
            \_ ->
                Terms.termShort "Overcome"
                    |> Expect.equal overcomeShort
        , test "termShort returns \"\" for an unknown name" <|
            \_ ->
                Terms.termShort "Nonsense"
                    |> Expect.equal ""
        ]


overcomeShort : String
overcomeShort =
    Terms.terms
        |> List.filter (\t -> t.term == "Overcome")
        |> List.head
        |> Maybe.map .short
        |> Maybe.withDefault "MISSING"


dedupe : List String -> List String
dedupe xs =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []
        xs
