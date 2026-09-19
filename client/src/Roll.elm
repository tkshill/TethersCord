module Roll exposing (..)

{-| A stone names its outcome: `Boon` is favourable, `Bane` is not. (Earlier
builds called these `WhiteStone` / `BlackStone`.)
-}


type Stone
    = Boon
    | Bane


initialStones : List Stone
initialStones =
    [ Boon
    , Bane
    , Boon
    , Bane
    ]


stoneLabel : Stone -> String
stoneLabel stone =
    case stone of
        Boon ->
            "Boon"

        Bane ->
            "Bane"


{-| `stones` with one occurrence of each of `taken` removed, by kind. Stones carry
no identity beyond their kind, so this is by count, not position. Used to show
the pool with a pending Overcome's drawn stones lifted out of it.
-}
without : List Stone -> List Stone -> List Stone
without taken stones =
    List.foldl removeOne stones taken


removeOne : Stone -> List Stone -> List Stone
removeOne stone stones =
    case stones of
        [] ->
            []

        first :: rest ->
            if first == stone then
                rest

            else
                first :: removeOne stone rest
