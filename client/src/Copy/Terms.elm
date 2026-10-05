module Copy.Terms exposing (Odds, Term, groupedTerms, ladderOdds, termShort, terms)

{-| The game's vocabulary in one place: every term a player meets in the
interface, each with a one-line `short` (used as a tooltip on the label where the
term appears) and a two-to-three-sentence `long` (shown in the Guide). One
definition, two surfaces.

The wording tracks `RULES.md`, the canonical statement of the rules, and the
names follow `CONTEXT.md` — when a rule changes, that file changes first and
this one follows. `DESIGN_PRINCIPLES.md` is the "why". It is meant to be
revised freely — this module has no logic, only data.
-}


type alias Term =
    { term : String
    , short : String
    , long : String
    }


{-| The terms grouped by the heading they sit under in the Guide, in rough order
of play. `terms` is the flat list of all of them.
-}
groupedTerms : List ( String, List Term )
groupedTerms =
    [ ( "Roles", [ table, facilitator, player ] )
    , ( "The die", [ die, ladder, flow, friction, criticals ] )
    , ( "The Junction", [ junction, preparation ] )
    , ( "Boons & aspects", [ boon, aspect, archetype, desire, quest, contextAspect ] )
    , ( "Moves", [ highlight, highlightContext, complicate, create, alter, undo ] )
    , ( "The session", [ session, goal ] )
    ]


terms : List Term
terms =
    List.concatMap Tuple.second groupedTerms


{-| The one-line gloss for a term, matched by its display name (the `term`
field). Unknown names return `""`, so a mistyped tooltip key degrades to no
tooltip rather than a crash.
-}
termShort : String -> String
termShort name =
    terms
        |> List.filter (\t -> t.term == name)
        |> List.head
        |> Maybe.map .short
        |> Maybe.withDefault ""


{-| The odds on each rung of the ladder, as `RULES.md` tabulates them: die,
Critical Friction, Friction, Flow, Critical Flow. Copy, not a calculation — the
Worker reads every roll.
-}
ladderOdds : List Odds
ladderOdds =
    [ { die = "d6", criticalFriction = "33%", friction = "33%", flow = "—", criticalFlow = "33%", faces = { criticalFriction = 2, friction = 2, flow = 0, criticalFlow = 2 } }
    , { die = "d8", criticalFriction = "25%", friction = "25%", flow = "25%", criticalFlow = "25%", faces = { criticalFriction = 2, friction = 2, flow = 2, criticalFlow = 2 } }
    , { die = "d10", criticalFriction = "20%", friction = "20%", flow = "40%", criticalFlow = "20%", faces = { criticalFriction = 2, friction = 2, flow = 4, criticalFlow = 2 } }
    , { die = "d12", criticalFriction = "17%", friction = "17%", flow = "50%", criticalFlow = "17%", faces = { criticalFriction = 2, friction = 2, flow = 6, criticalFlow = 2 } }
    , { die = "d16", criticalFriction = "12.5%", friction = "12.5%", flow = "62.5%", criticalFlow = "12.5%", faces = { criticalFriction = 2, friction = 2, flow = 10, criticalFlow = 2 } }
    , { die = "d20", criticalFriction = "10%", friction = "10%", flow = "70%", criticalFlow = "10%", faces = { criticalFriction = 2, friction = 2, flow = 14, criticalFlow = 2 } }
    ]


{-| One rung's odds: each outcome's chance as the Guide prints it, and how
many faces read as it (the Guide's odds bars are sized by these).
-}
type alias Odds =
    { die : String
    , criticalFriction : String
    , friction : String
    , flow : String
    , criticalFlow : String
    , faces : { criticalFriction : Int, friction : Int, flow : Int, criticalFlow : Int }
    }



-- ROLES


table : Term
table =
    { term = "Table"
    , short = "Everyone playing, plus the shared fiction you agree on."
    , long =
        "The whole group — the facilitator and the players — together with the world you build between you. What the table agrees is true is true; the rules keep everyone on the same page, they do not settle every detail."
    }


facilitator : Term
facilitator =
    { term = "Facilitator"
    , short = "Frames scenes, plays the world, resolves each Junction, and can undo any move."
    , long =
        "A role, not a leader. The facilitator presents situations, plays everyone who is not a player character, and accepts or rejects each Junction's roll. They make direct edits — stepping the die, granting boons, adding and wording context boons and banes — and can undo any player's move."
    }


player : Term
player =
    { term = "Player"
    , short = "Runs one character — their wants, choices, and risks."
    , long =
        "Each player drives a single character: what they want, what they will risk for it, and how they act under pressure. Players edit their own sheet, send messages and make moves. A move takes effect at once; nobody approves it, and you can undo your own until the Junction is rolled."
    }



-- THE DIE


die : Term
die =
    { term = "Die"
    , short = "The one die every Junction rolls. Its size is its rung on the ladder."
    , long =
        "There is one die at the table, and it decides every Junction. Moves step it up or down the ladder before the roll; accepting a Junction returns it to the d10."
    }


ladder : Term
ladder =
    { term = "Ladder"
    , short = "d6 → d8 → d10 → d12 → d16 → d20. The die starts each Junction at the d10."
    , long =
        "The die's sizes, in order. A boon steps it up a rung, a bane steps it down. A step past either end is not allowed — nothing is spent and nothing happens. The bigger the die, the likelier a Flow."
    }


flow : Term
flow =
    { term = "Flow"
    , short = "A roll of 5 or more: the story takes the easier path."
    , long =
        "The outcome where things go the characters' way, or at least not against them. On a d10 a Flow comes up 60% of the time, counting a Critical Flow."
    }


friction : Term
friction =
    { term = "Friction"
    , short = "A roll of 4 or less: the story takes the harder path."
    , long =
        "The outcome with more difficulty or conflict. It is not failure — it is the version of events that pushes back. A 1 or a 2 is a Critical Friction."
    }


criticals : Term
criticals =
    { term = "Criticals"
    , short = "1–2 is a Critical Friction; the die's top two faces a Critical Flow."
    , long =
        "Accepting a Critical Flow adds a context boon, a Critical Friction a context bane. The two are always equally likely — two faces each — so a smaller die makes the story more volatile both ways and a larger one steadies it. On a d6 every Flow is a Critical Flow."
    }



-- THE JUNCTION


junction : Term
junction =
    { term = "Junction"
    , short = "A point where the story could go two ways: prepare, roll the die, the facilitator accepts or rejects."
    , long =
        "The facilitator declares a point where the story could go an easier way (Flow) or a harder one (Friction). The table prepares, then anyone presses the current die on the ladder to roll it. After the roll, the only move left is Alter, and the facilitator may reroll for free. Accepting keeps the last roll, returns the die to the d10 and turns a critical into a context aspect. Rejecting discards the roll and leaves the die where it was."
    }


preparation : Term
preparation =
    { term = "Preparation"
    , short = "Everything before the roll: the moves are made, and can be undone."
    , long =
        "Highlight, Highlight Context, Complicate and Create are all made before the Junction is rolled, so boons are spent proactively, not only after a Friction. Once the die is rolled, those moves are locked and can no longer be undone."
    }



-- BOONS & ASPECTS


boon : Term
boon =
    { term = "Boon"
    , short = "A character's currency: spent on Highlight, Create and Alter, earned by Complicate."
    , long =
        "The ☼ marks on a character's sheet. Spend them on moves, earn two with Complicate; the facilitator can also grant or take them directly. Boon on its own always means this currency — a context boon is something else."
    }


aspect : Term
aspect =
    { term = "Aspect"
    , short = "A statement that is true in the fiction: a character's three, or a context aspect."
    , long =
        "A character is written around three aspects — Archetype, Desire, Quest — that carry latent conflict with the world. They are always true; on your own sheet, the right half of one Highlights it and the left half Complicates it."
    }


archetype : Term
archetype =
    { term = "Archetype"
    , short = "Who the character is to the world — the role others read onto them."
    , long =
        "The public shape of the character: what a stranger assumes, what a title or reputation implies. Write it so the world's expectation of it can be leaned on, or turned against them."
    }


desire : Term
desire =
    { term = "Desire"
    , short = "What the character wants badly enough to risk things for."
    , long =
        "The private hunger that pulls the character into danger. Concrete enough to act on, unmet enough to keep mattering."
    }


quest : Term
quest =
    { term = "Quest"
    , short = "The concrete thing the character is trying to do right now."
    , long =
        "The near-term objective — a place to reach, a person to convince, a thing to carry. It changes as the fiction moves; the Archetype and Desire beneath it do not."
    }


contextAspect : Term
contextAspect =
    { term = "Context aspect"
    , short = "Something true about the situation, owned by nobody: a context boon ☼ or a context bane ☽, with one use."
    , long =
        "An accepted Critical Flow adds a context boon and a Critical Friction a context bane; Create adds a boon and Complicate a bane; the facilitator can add either. Anyone may highlight one: a boon steps the die up, a bane steps it down, and it is consumed — it stays on the table, struck through, and cannot be used again. They stay until the facilitator removes them; ending a session does not clear them."
    }



-- MOVES


highlight : Term
highlight =
    { term = "Highlight"
    , short = "Pay 1 boon to make one of your aspects matter: the die steps up."
    , long =
        "Show how one of your character aspects shapes what happens next — press the right half of it on your sheet. It costs one boon and steps the die up one rung. Highlights stack: three take a d10 to a d20."
    }


highlightContext : Term
highlightContext =
    { term = "Highlight Context"
    , short = "Use a context aspect's one use: a boon steps the die up, a bane steps it down."
    , long =
        "Bring a context aspect to bear by pressing it in the context list. It is free and open to anyone. Highlighting a context bane makes the Junction riskier and more volatile — a choice a player may make."
    }


complicate : Term
complicate =
    { term = "Complicate"
    , short = "Your aspect drags you into trouble: gain 2 boons, and a context bane appears."
    , long =
        "Suggest how one of your character aspects pulls your character into something dangerous, destructive, or derailing — press the left half of it on your sheet. It is free: you gain two boons, and the trouble becomes a context bane for the facilitator to word."
    }


create : Term
create =
    { term = "Create"
    , short = "Pay 1 boon to make something true about the scene — a context boon in your words."
    , long =
        "Establish a fact in the field under the context list. It costs one boon and becomes a context boon. Leave it blank and it is recorded as a detail from you, for the facilitator to word."
    }


alter : Term
alter =
    { term = "Alter"
    , short = "Pay 2 boons to reroll a pending Junction on the same die."
    , long =
        "Suggest an alternate action and reroll — the only move after a roll, from the button beside the result. Each character may Alter once per Junction."
    }


undo : Term
undo =
    { term = "Undo"
    , short = "Reverse one move's own effects, from its line in the log."
    , long =
        "The facilitator can undo any move; a player can undo their own. It reverses that move and nothing else, so moves made since are kept. Undo closes when the Junction is rolled; an Alter can be undone until its Junction is accepted or rejected."
    }



-- THE SESSION


session : Term
session =
    { term = "Session"
    , short = "One sitting of play, from the facilitator starting it with a goal to ending it."
    , long =
        "A session runs from the facilitator starting it, with a goal, to ending it. Starting or ending one records the goal and dates and nothing else — the die, open moves, and context boons and banes all carry across."
    }


goal : Term
goal =
    { term = "Goal"
    , short = "What the table is working toward this session."
    , long =
        "Set by the facilitator when the session starts, and editable at any time. It names a target for the fiction; whether it is met is for the table to decide by playing it out, not by a roll."
    }
