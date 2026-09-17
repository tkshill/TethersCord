module View.SessionAspects exposing (view)

{-| The Session aspects card (roadmap section 23.5, renamed and moved here
from the old Stones card as 23.3 anticipated): the table's floating boons —
Boon or Bane, 23.3 — context the facilitator has planted directly or approved
from an Add a Detail / Gain Insight (always a Boon). Read-only for players;
the facilitator can remove any of them outright, and plant a new one — kind
and note — through the fields at the bottom, shown even with none yet so
there is always somewhere to add the first one. "Use" on a floating boon
(23.3) is gone the same way "Add boon" is (23.2): the facilitator plants and
removes session context directly, with no third "spend it" state in between.
-}

import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Roll exposing (Stone(..))
import Set exposing (Set)
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, glossaryTitle, inputAttrs)


type alias Props =
    { inflight : Set String
    , floatingBoonDraft : String
    , floatingBoonKind : Stone
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.floatingBoons && not ctx.facilitator then
        none

    else
        Ui.card
            (glossaryTitle Copy.sessionAspectsTitle "Session aspect"
                :: List.map (row ctx.facilitator props.inflight) gs.floatingBoons
                ++ Ui.onlyWhen ctx.facilitator
                    [ addFloatingBoonRow props.inflight props.floatingBoonDraft props.floatingBoonKind ]
            )


row : Bool -> Set String -> FloatingBoon -> Element Msg
row facilitator inflight fb =
    Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
        [ floatingBoonChip fb.kind
        , Element.paragraph [ Font.size 12 ] [ text fb.text ]
        , if facilitator then
            el [ Element.alignRight ]
                (Ui.ghostButton
                    { onPress = Ui.press inflight ("stones:floating-delete:" ++ fb.id) (DeleteFloatingBoon fb.id)
                    , label = Copy.floatingBoonRemove
                    }
                )

          else
            none
        ]


{-| A session-context chip: coloured and captioned by `kind`, marked with a
centre dot to set it apart from a plain bag stone.
-}
floatingBoonChip : Stone -> Element msg
floatingBoonChip kind =
    case kind of
        Boon ->
            Ui.pledgedStoneChip Ui.boonFill Copy.boonStone

        Bane ->
            Ui.pledgedStoneChip Ui.baneFill Copy.baneStone


addFloatingBoonRow : Set String -> String -> Stone -> Element Msg
addFloatingBoonRow inflight draft draftKind =
    Element.wrappedRow [ spacing Ui.sm, width fill, Element.centerY ]
        [ Ui.tab (draftKind == Boon) Copy.boonStone (FloatingBoonKindChanged Boon)
        , Ui.tab (draftKind == Bane) Copy.baneStone (FloatingBoonKindChanged Bane)
        , Input.text
            (inputAttrs ++ [ width fill ])
            { onChange = FloatingBoonDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addFloatingBoonPlaceholder))
            , label = Input.labelHidden "New session aspect"
            }
        , Ui.ghostButton
            { onPress =
                if String.trim draft == "" then
                    Nothing

                else
                    Ui.press inflight "stones:floating-add" AddFloatingBoon
            , label = Copy.addFloatingBoon
            }
        ]
