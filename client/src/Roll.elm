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
