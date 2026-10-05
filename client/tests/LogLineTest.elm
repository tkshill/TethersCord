module LogLineTest exposing (suite)

{-| `LogLine.parse` against each line the Worker's `logText`
(`worker/src/rules/log.ts`) writes. `worker/test/rules/logLineParity.test.ts`
checks that every line `logText` writes is one of the strings below, so a
reworded line there fails until a case here follows it.
-}

import Expect
import LogLine exposing (Lead(..), Mark(..), Parsed(..))
import Outcome exposing (Outcome(..))
import Test exposing (Test, describe, test)


event : String -> Maybe Mark -> Maybe ( String, String ) -> Bool -> Parsed
event text mark step namesActor =
    EventLine { text = text, mark = mark, step = step, namesActor = namesActor }


roll : Outcome -> Int -> String -> Lead -> Parsed
roll outcome face die lead =
    RollLine { outcome = outcome, face = face, die = die, lead = lead }


cases : List ( String, Parsed )
cases =
    [ ( "Highlight — Wren: Desire — d10 → d12"
      , event "Highlight — Wren: Desire" (Just UpMark) (Just ( "d10", "d12" )) True
      )
    , ( "Highlight Context — Halvard: Captain Enna owes the ferryman (context boon) — d12 → d16"
      , event "Highlight Context — Halvard: Captain Enna owes the ferryman (context boon)" (Just UpMark) (Just ( "d12", "d16" )) True
      )
    , ( "Highlight Context — Mara: Soldiers at the well (context bane) — d10 → d8"
      , event "Highlight Context — Mara: Soldiers at the well (context bane)" (Just DownMark) (Just ( "d10", "d8" )) True
      )
    , ( "Complicate — Wren: Desire — gains 2 boons, a context bane is added"
      , event "Complicate — Wren: Desire — gains 2 boons, a context bane is added" (Just BaneMark) Nothing True
      )
    , ( "Create — Mara pays 1 boon: The tide turns late tonight"
      , event "Create — Mara pays 1 boon: The tide turns late tonight" (Just BoonMark) Nothing True
      )
    , ( "Session note added (Boon) — Oss keeps a ledger"
      , event "Session note added (Boon) — Oss keeps a ledger" (Just BoonMark) Nothing False
      )
    , ( "Session note added (Bane) — Soldiers at the second well"
      , event "Session note added (Bane) — Soldiers at the second well" (Just BaneMark) Nothing False
      )
    , ( "Session note removed (Bane) — Soldiers at the second well"
      , event "Session note removed (Bane) — Soldiers at the second well" Nothing Nothing False
      )
    , ( "Die stepped up — d10 → d12"
      , event "Die stepped up" (Just UpMark) (Just ( "d10", "d12" )) False
      )
    , ( "Die stepped down — d8 → d6"
      , event "Die stepped down" (Just DownMark) (Just ( "d8", "d6" )) False
      )
    , ( "Highlight undone — Wren — d12 → d10"
      , event "Highlight undone — Wren" Nothing (Just ( "d12", "d10" )) True
      )
    , ( "Create undone — Mara"
      , event "Create undone — Mara" Nothing Nothing True
      )
    , ( "Junction accepted — Flow — 11 on d16 — d16 → d10"
      , event "Junction accepted — Flow — 11 on d16" Nothing (Just ( "d16", "d10" )) False
      )
    , ( "Junction accepted — Critical Flow — 20 on d20 (context boon added) — d20 → d10"
      , event "Junction accepted — Critical Flow — 20 on d20 (context boon added)" Nothing (Just ( "d20", "d10" )) False
      )
    , ( "Junction accepted — Friction — 3 on d10"
      , event "Junction accepted — Friction — 3 on d10" Nothing Nothing False
      )
    , ( "Junction rejected — the roll is discarded"
      , event "Junction rejected — the roll is discarded" Nothing Nothing False
      )
    , ( "Session started — Get the child to the coast"
      , event "Session started — Get the child to the coast" Nothing Nothing False
      )
    , ( "Session ended — Get the child to the coast"
      , event "Session ended — Get the child to the coast" Nothing Nothing False
      )
    , ( "Goal updated — Get the child to the coast"
      , event "Goal updated — Get the child to the coast" Nothing Nothing False
      )
    , ( "Junction — Halvard rolled: Flow — 11 on d16"
      , roll Flow 11 "d16" (Rolled "Halvard")
      )
    , ( "Junction — sam rolled: Critical Friction — 1 on d6"
      , roll CriticalFriction 1 "d6" (Rolled "sam")
      )
    , ( "Reroll — Friction — 4 on d12"
      , roll Friction 4 "d12" Rerolled
      )
    , ( "Alter — Wren pays 2 boons, rerolled: Critical Flow — 12 on d12"
      , roll CriticalFlow 12 "d12" (Altered "Wren")
      )
    , ( "Something the client has never seen — d10 → nowhere"
      , event "Something the client has never seen — d10 → nowhere" Nothing Nothing False
      )
    , ( "Junction — not a roll at all"
      , event "Junction — not a roll at all" Nothing Nothing False
      )
    ]


suite : Test
suite =
    describe "LogLine.parse"
        (List.map
            (\( line, expected ) -> test line <| \_ -> Expect.equal expected (LogLine.parse line))
            cases
        )
