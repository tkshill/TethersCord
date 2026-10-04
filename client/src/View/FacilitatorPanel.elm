module View.FacilitatorPanel exposing (view)

{-| The facilitator's tool (the ⚑ tab): stepping the die directly, a correction
that is logged but is not a move. Renders nothing for a player.

Interim (roadmap 31.4): the approval queue it used to hold is gone, since moves
now act at once. 31.5 moves these arrows beside the ladder on the status strip
and deletes this tab.
-}

import Action exposing (Action(..))
import Copy
import Die
import Element exposing (Element, el, none, spacing, text)
import Element.Font as Font
import Types exposing (..)
import Ui
import View.Helpers exposing (ViewContext)


view : ViewContext -> GameState -> Element Msg
view ctx gs =
    if not ctx.facilitator then
        none

    else
        Ui.flat
            [ Ui.sectionTitle Copy.theDie
            , Element.row [ spacing Ui.sm, Element.centerY ]
                [ stepButton ctx gs Die.Down "‹"
                , el [ Font.size 13, Font.semiBold ] (text (Die.label gs.die))
                , stepButton ctx gs Die.Up "›"
                ]
            ]


{-| A step the ladder allows; greyed at either end.
-}
stepButton : ViewContext -> GameState -> Die.Direction -> String -> Element Msg
stepButton ctx gs direction label =
    Ui.ghostButton
        { onPress =
            case Die.step direction gs.die of
                Just _ ->
                    Ui.press ctx.inflight (SteppingDie direction) (StepDie direction)

                Nothing ->
                    Nothing
        , label = label
        }
