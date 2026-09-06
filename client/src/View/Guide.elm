module View.Guide exposing (view)

{-| The "How to play" card: a collapsed-by-default panel that lays out every
term in `Copy.Terms`, grouped by the heading it sits under, in rough order of
play. The tooltips (step 3) teach a term where a player meets it; this is the
one place to read all of them, and the path for touch, where `title` tooltips
do not fire.
-}

import Copy.Terms as Terms
import Element exposing (Element, el, fill, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext)


type alias Props =
    { expanded : Bool }


view : ViewContext -> Props -> Element Msg
view _ props =
    Ui.card
        (header props.expanded
            :: (if props.expanded then
                    List.map group Terms.groupedTerms

                else
                    []
               )
        )


{-| The card title doubles as the toggle: a ▸ / ▾ marker beside "How to play".
-}
header : Bool -> Element Msg
header expanded =
    Input.button [ width fill ]
        { onPress = Just ToggleGuide
        , label =
            Element.row [ spacing Ui.sm, width fill ]
                [ el [ Font.size 12, Font.color Ui.inkSoft ]
                    (text
                        (if expanded then
                            "▾"

                         else
                            "▸"
                        )
                    )
                , Ui.sectionTitle "How to play"
                ]
        }


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
