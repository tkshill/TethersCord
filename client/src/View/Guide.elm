module View.Guide exposing (view)

{-| The Guide tool (roadmap 32.7, Table v2): three short parts in the order a
player needs them — the die with each rung's odds as a bar, the five moves with
their costs, and the four steps of a junction — then "See all terms", which
opens every term in `Copy.Terms` grouped as before. The tooltips teach a term
where a player meets it; the full list is the one place to read all of them,
and the path for touch, where `title` tooltips do not fire.
-}

import Copy
import Copy.Terms as Terms
import Die exposing (Die)
import Element exposing (Element, el, fill, px, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html.Attributes
import Types exposing (..)
import Ui


view : Bool -> Die -> Element Msg
view glossaryOpen die =
    Element.column [ spacing 18, width fill ]
        ([ theDie die
         , moves
         , junction
         , el []
            (Ui.linkButton
                { onPress = Just ToggleGlossary
                , label =
                    if glossaryOpen then
                        Copy.guideAllTermsHide

                    else
                        Copy.guideAllTermsShow
                }
            )
         ]
            ++ Ui.onlyWhen glossaryOpen (List.map group Terms.groupedTerms)
        )


section : String -> List (Element Msg) -> Element Msg
section title body =
    Element.column [ spacing Ui.sm, width fill ] (Ui.sectionTitle title :: body)


{-| The die: what it does, a bar per rung split by outcome (the current die's
label bold), and the legend.
-}
theDie : Die -> Element Msg
theDie current =
    let
        bar odds =
            let
                segment tone n =
                    if n <= 0 then
                        []

                    else
                        [ el [ width (Element.fillPortion n), Element.height fill, Background.color tone ] Element.none ]
            in
            Element.row
                [ width fill
                , spacing Ui.sm
                , Element.htmlAttribute (Html.Attributes.title (Copy.guideOddsTip odds))
                ]
                [ el
                    [ width (px 26)
                    , Font.family Ui.mono
                    , Font.size 11
                    , if odds.die == Die.label current then
                        Font.bold

                      else
                        Font.regular
                    ]
                    (text odds.die)
                , Element.row
                    [ width fill
                    , Element.height (px 10)
                    , spacing 1
                    , Border.rounded 2
                    , Element.clip
                    ]
                    (segment Ui.danger odds.faces.criticalFriction
                        ++ segment Ui.dangerSoft odds.faces.friction
                        ++ segment Ui.accentSoft odds.faces.flow
                        ++ segment Ui.accent odds.faces.criticalFlow
                    )
                ]

        swatch tone label =
            Element.row [ spacing 5, width fill ]
                [ el [ width (px 8), Element.height (px 8), Background.color tone ] Element.none
                , el [ Font.size 11, Font.color Ui.inkSoft ] (text label)
                ]
    in
    section Copy.guideDieTitle
        [ Element.paragraph [ Font.size 14, lineHeight 1.4 ] [ text Copy.guideDieText ]
        , Element.column [ spacing Ui.xs, width fill ] (List.map bar Terms.ladderOdds)
        , Element.column [ spacing Ui.xs, width fill, Element.paddingEach { top = 0, right = 0, bottom = 0, left = 34 } ]
            [ Element.row [ width fill, spacing Ui.sm ]
                [ swatch Ui.danger Copy.guideLegend.criticalFriction, swatch Ui.dangerSoft Copy.guideLegend.friction ]
            , Element.row [ width fill, spacing Ui.sm ]
                [ swatch Ui.accentSoft Copy.guideLegend.flow, swatch Ui.accent Copy.guideLegend.criticalFlow ]
            ]
        ]


{-| The five moves: name, what it does, and its cost.
-}
moves : Element Msg
moves =
    let
        row move =
            Element.row
                [ width fill
                , spacing Ui.sm
                , Element.paddingXY 0 6
                , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
                , Border.color Ui.line
                ]
                [ el [ width (px 92), Element.alignTop, Ui.fontSize 12.5, Font.semiBold ] (Element.paragraph [] [ text move.name ])
                , Element.paragraph [ width fill, Ui.fontSize 13.5, lineHeight 1.35, Element.alignTop ] [ text move.effect ]
                , el
                    [ Element.alignTop
                    , Ui.fontSize 11.5
                    , Font.color Ui.accent
                    , Ui.glyph
                    , Element.htmlAttribute (Html.Attributes.title move.costTip)
                    ]
                    (text move.cost)
                ]
    in
    section Copy.guideMovesTitle [ Element.column [ width fill ] (List.map row Copy.guideMoves) ]


{-| The four steps of a junction, numbered.
-}
junction : Element Msg
junction =
    let
        step n ( lead, rest ) =
            Element.row [ width fill, spacing Ui.sm ]
                [ el [ width (px 12), Element.alignTop, Font.family Ui.mono, Font.size 11, Font.color Ui.inkSoft ] (text (String.fromInt n))
                , Element.paragraph [ width fill, Ui.fontSize 12.5, lineHeight 1.35 ]
                    [ el [ Font.bold ] (text lead), text (" " ++ rest) ]
                ]
    in
    section Copy.guideJunctionTitle
        [ Element.column [ spacing 6, width fill ] (List.indexedMap (\i s -> step (i + 1) s) Copy.guideJunctionSteps) ]


{-| One heading from `groupedTerms` and its terms, in the full glossary. -}
group : ( String, List Terms.Term ) -> Element Msg
group ( heading, terms ) =
    section heading (List.map termRow terms)


termRow : Terms.Term -> Element Msg
termRow t =
    Element.paragraph [ Font.size 13, spacing 3 ]
        [ el [ Font.semiBold ] (text (t.term ++ " — "))
        , text t.long
        ]


lineHeight : Float -> Element.Attribute msg
lineHeight value =
    Element.htmlAttribute (Html.Attributes.style "line-height" (String.fromFloat value))
