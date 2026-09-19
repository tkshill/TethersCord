module View.Entities exposing (view)

{-| A facilitator-owned reference list — the cast (`Npc`) or the map
(`Location`). The facilitator gets an editable list with an Add button and a
Delete per row; players get a plain read-only list, and the list is hidden from
them entirely while it is empty.
-}

import Copy
import Element exposing (Element, el, fill, height, none, px, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, inputAttrs, placeholder)


view : ViewContext -> EntityKind -> GameState -> Element Msg
view ctx kind gs =
    let
        ( title, singular ) =
            case kind of
                Npc ->
                    ( Copy.npcsTitle, Copy.npcSingular )

                Location ->
                    ( Copy.locationsTitle, Copy.locationSingular )

        entities =
            entitiesForKind kind gs
    in
    if not ctx.facilitator && List.isEmpty entities then
        none

    else
        Ui.flat
            (Ui.sectionTitle title
                :: (if List.isEmpty entities then
                        [ placeholder (Copy.noEntitiesYet title) ]

                    else
                        List.map (entityRow kind ctx.facilitator) entities
                   )
                ++ (if ctx.facilitator then
                        [ el []
                            (Ui.ghostButton
                                { onPress = Just (AddEntity kind)
                                , label = Copy.addEntity singular
                                }
                            )
                        ]

                    else
                        []
                   )
            )


entityRow : EntityKind -> Bool -> TableEntity -> Element Msg
entityRow kind facilitator entity =
    let
        boxAttrs =
            [ spacing Ui.xs
            , Element.paddingEach { top = 0, right = 0, bottom = Ui.sm, left = 0 }
            , width fill
            , Border.widthEach { top = 0, right = 0, bottom = 1, left = 0 }
            , Border.color Ui.line
            ]
    in
    if facilitator then
        Element.column boxAttrs
            [ Element.row [ width fill, spacing Ui.sm, Element.centerY ]
                [ el [ width fill ]
                    (Input.text
                        (inputAttrs ++ [ width fill, Ui.onBlur (EntityFieldBlur kind entity.id) ])
                        { onChange = EntityFieldInput kind entity.id EntityNameField
                        , text = entity.name
                        , placeholder = Just (Input.placeholder [] (text "Name"))
                        , label = Input.labelHidden "Name"
                        }
                    )
                , el [ Element.alignRight ]
                    (Ui.ghostButton { onPress = Just (DeleteEntity kind entity.id), label = Copy.entityDelete })
                ]
            , Input.multiline
                (inputAttrs ++ [ height (px 56), Ui.onBlur (EntityFieldBlur kind entity.id) ])
                { onChange = EntityFieldInput kind entity.id EntityNotesField
                , text = entity.notes
                , placeholder = Just (Input.placeholder [] (text "Notes"))
                , label = Input.labelHidden "Notes"
                , spellcheck = False
                }
            ]

    else
        Element.column boxAttrs
            [ el [ Font.semiBold, Font.size 13 ]
                (text
                    (if String.trim entity.name == "" then
                        Copy.entityUnnamed

                     else
                        entity.name
                    )
                )
            , if String.trim entity.notes == "" then
                none

              else
                Element.paragraph [ Font.size 12, Font.color Ui.inkSoft ] [ text entity.notes ]
            ]
