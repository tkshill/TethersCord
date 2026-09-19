module View.SessionAspects exposing (view)

{-| The Session aspects card (roadmap section 23.5, renamed and moved here
from the old Stones card as 23.3 anticipated): the table's session aspects —
Boon or Bane, 23.3 — context the facilitator has planted directly or approved
from an Add Detail / Gain Insight (always a Boon). Read-only for players;
the facilitator can remove any of them outright, and plant a new one — kind
and note — through the fields at the bottom, shown even with none yet so
there is always somewhere to add the first one. "Use" on a session aspect
(23.3) is gone the same way "Add boon" is (23.2): the facilitator plants and
removes session context directly, with no third "spend it" state in between.
-}

import Action exposing (Action(..))
import Copy
import Element exposing (Element, el, fill, none, spacing, text, width)
import Element.Font as Font
import Element.Input as Input
import Roll exposing (Stone(..))
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext, glossaryTitle, inputAttrs)


type alias Props =
    { sessionAspectDraft : String
    , sessionAspectKind : Stone
    }


view : ViewContext -> Props -> GameState -> Element Msg
view ctx props gs =
    if List.isEmpty gs.sessionAspects && not ctx.facilitator then
        none

    else
        Ui.card
            (glossaryTitle Copy.sessionAspectsTitle "Session boon"
                :: List.map (row ctx.facilitator ctx.inflight) gs.sessionAspects
                ++ Ui.onlyWhen ctx.facilitator
                    [ addSessionAspectRow ctx.inflight props.sessionAspectDraft props.sessionAspectKind ]
            )


row : Bool -> List Action -> SessionAspect -> Element Msg
row facilitator inflight fb =
    Element.wrappedRow [ spacing Ui.sm, Element.centerY, width fill ]
        [ sessionAspectChip fb.kind
        , Element.paragraph [ Font.size 12 ] [ text fb.text ]
        , if facilitator then
            el [ Element.alignRight ]
                (Ui.ghostButton
                    { onPress = Ui.press inflight (DeletingSessionAspect fb.id) (DeleteSessionAspect fb.id)
                    , label = Copy.sessionAspectRemove
                    }
                )

          else
            none
        ]


{-| A session-context chip: coloured and captioned by `kind`, marked with a
centre dot to set it apart from a plain bag stone.
-}
sessionAspectChip : Stone -> Element msg
sessionAspectChip kind =
    case kind of
        Boon ->
            Ui.highlightedStoneChip Ui.boonFill Copy.boonStone

        Bane ->
            Ui.highlightedStoneChip Ui.baneFill Copy.baneStone


addSessionAspectRow : List Action -> String -> Stone -> Element Msg
addSessionAspectRow inflight draft draftKind =
    Element.wrappedRow [ spacing Ui.sm, width fill, Element.centerY ]
        [ Ui.tab (draftKind == Boon) Copy.boonStone (SessionAspectKindChanged Boon)
        , Ui.tab (draftKind == Bane) Copy.baneStone (SessionAspectKindChanged Bane)
        , Input.text
            (inputAttrs ++ [ width fill ])
            { onChange = SessionAspectDraftChanged
            , text = draft
            , placeholder = Just (Input.placeholder [] (text Copy.addSessionAspectPlaceholder))
            , label = Input.labelHidden "New session boon or bane"
            }
        , Ui.ghostButton
            { onPress =
                if String.trim draft == "" then
                    Nothing

                else
                    Ui.press inflight AddingSessionAspect AddSessionAspect
            , label = Copy.addSessionAspect
            }
        ]
