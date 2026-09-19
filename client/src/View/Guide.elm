module View.Guide exposing (view)

{-| The "How to play" tool (roadmap section 27, the ? tab): every term in
`Copy.Terms`, grouped by the heading it sits under, in rough order of play. The
tooltips teach a term where a player meets it; this is the one place to read all
of them, and the path for touch, where `title` tooltips do not fire.
-}

import Copy.Terms as Terms
import Element exposing (Element, el, fill, spacing, text, width)
import Element.Font as Font
import Types exposing (..)
import Ui


view : Element Msg
view =
    Ui.flat (List.map group Terms.groupedTerms)


{-| One heading from `groupedTerms` and its terms. -}
group : ( String, List Terms.Term ) -> Element Msg
group ( heading, terms ) =
    Element.column [ spacing Ui.sm, width fill ]
        (el
            [ Font.size 11
            , Font.semiBold
            , Font.color Ui.inkSoft
            , Font.letterSpacing 0.5
            ]
            (text (String.toUpper heading))
            :: List.map termRow terms
        )


termRow : Terms.Term -> Element Msg
termRow t =
    Element.paragraph [ Font.size 13, spacing 3 ]
        [ el [ Font.semiBold ] (text (t.term ++ " — "))
        , text t.long
        ]
