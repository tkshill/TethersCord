module Copy.Terms exposing (Term, groupedTerms, termShort, terms)

{-| The game's vocabulary in one place: every term a player meets in the
interface, each with a one-line `short` (used as a tooltip on the label where the
term appears) and a two-to-three-sentence `long` (shown in the "How to play"
card). One definition, two surfaces.

The wording tracks `RULES.md`, which is the canonical statement of the rules — when
a rule changes, that file changes first and this one follows. `DESIGN_PRINCIPLES.md`
is the "why". It is meant to be revised freely — this module has no logic, only
data.
-}


type alias Term =
    { term : String
    , short : String
    , long : String
    }


{-| The terms grouped by the heading they sit under in the guide, in rough order
of play. `terms` is the flat list of all of them.
-}
groupedTerms : List ( String, List Term )
groupedTerms =
    [ ( "Roles", [ table, facilitator, player ] )
    , ( "The session", [ session, goal ] )
    , ( "Stones & the pool", [ stone, boon, bane, thePool ] )
    , ( "The Overcome", [ overcome, proposal ] )
    , ( "Moves", [ highlight, complicate, addDetail, alterFate, sessionBoon ] )
    , ( "Aspects & growth", [ aspect, archetype, desire, quest, condition ] )
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



-- ROLES


table : Term
table =
    { term = "Table"
    , short = "Everyone playing, plus the shared fiction you agree on."
    , long =
        "The whole group — the facilitator and the character players — together with the world you build between you. What the table agrees is true is true; the rules exist to keep everyone on the same page and enjoying themselves, not to settle every detail."
    }


facilitator : Term
facilitator =
    { term = "Facilitator"
    , short = "Frames scenes, plays the world, and rules on the moves players propose."
    , long =
        "An asymmetric role, not a leader. The facilitator presents situations, plays everyone who is not a player character, and accepts or rejects the moves players propose. They act directly where players propose and wait: rolling and rerolling an Overcome, granting boons, adjusting the pool, and planting session boons and banes."
    }


player : Term
player =
    { term = "Player"
    , short = "Runs one character — their wants, choices, and risks."
    , long =
        "Each player drives a single character: what they want, what they will risk for it, and how they act under pressure. Players edit their own sheet and send messages freely. Every other change to shared state is a move, and a move waits for the facilitator to accept it."
    }



-- THE SESSION


session : Term
session =
    { term = "Session"
    , short = "One game day, with a goal the table names and works toward."
    , long =
        "A session runs from the facilitator starting it, with a goal, to ending it. The goal is table talk: nothing is rolled to judge whether it was met. Starting or ending a session records the goal and dates and nothing else — the pool, waiting proposals, and session boons and banes all carry across."
    }


goal : Term
goal =
    { term = "Goal"
    , short = "What the table is working toward this session."
    , long =
        "Set by the facilitator when the session starts, and editable at any time. It names a target for the fiction; whether it is met is for the table to decide by playing it out, not by a roll."
    }



-- STONES & THE POOL


stone : Term
stone =
    { term = "Stone"
    , short = "The unit of chance — either a Boon or a Bane."
    , long =
        "Every Overcome is resolved by drawing two stones from the pool. There are only two kinds, Boon and Bane, so an outcome is read from the fiction rather than compared against a number."
    }


boon : Term
boon =
    { term = "Boon"
    , short = "A favourable stone, and the currency a character spends on moves."
    , long =
        "As a stone, the good result of a draw. As a resource, the boons on a character's sheet: spent on Highlight, Add Detail and Alter Fate, and gained when another player Complicates you. The facilitator can also grant or take them directly."
    }


bane : Term
bane =
    { term = "Bane"
    , short = "An unfavourable stone; the facilitator adds Banes to the pool."
    , long =
        "The bad result of a draw. Banes in the pool make an Overcome riskier. Players put Boons into the pool; the facilitator puts Banes in, directly or by using a session bane. Nothing marks a character's aspects with Banes at present."
    }


thePool : Term
thePool =
    { term = "The pool"
    , short = "The shared stones an Overcome draws from — two Boon and two Bane, reset after each."
    , long =
        "One shared set of stones. It starts at two Boon and two Bane, and returns to exactly that whenever an Overcome is accepted, so nothing carries from one Overcome to the next. In between, players add Boons (Highlight, or using a session boon) and the facilitator adds Banes."
    }



-- THE OVERCOME


overcome : Term
overcome =
    { term = "Overcome"
    , short = "A fork at the table: prepare the pool, roll two stones, the facilitator accepts or rejects."
    , long =
        "The facilitator declares a fork where the plot could go more than one way. The table prepares the pool, then one player presses Overcome to draw two stones. From that roll until the facilitator resolves it, the pool is frozen — a table rule the app does not enforce. Accepting resets the pool, and if two Boons or two Banes came up, plants a session boon or bane. Rejecting discards the roll and changes nothing else."
    }


proposal : Term
proposal =
    { term = "Proposal"
    , short = "A move waiting for the facilitator to accept or reject."
    , long =
        "Players do not change shared state directly. Highlight, Complicate, Add Detail, Alter Fate and using a session boon are proposals that queue for the facilitator; nothing happens, and nothing is paid, until one is accepted, and you can withdraw your own while it waits. Overcome is the exception: it needs no approval."
    }



-- MOVES


highlight : Term
highlight =
    { term = "Highlight"
    , short = "Pay 1 boon: an aspect shapes the outcome, and the pool gains a Boon."
    , long =
        "Note how an aspect of the scene will shape the outcome. It costs you one boon, paid when the facilitator accepts, and puts one Boon into the pool. Do it before the roll: once an Overcome is rolled, the pool is frozen until it is resolved."
    }


complicate : Term
complicate =
    { term = "Complicate"
    , short = "Suggest a complication for another character; their player gains 2 boons."
    , long =
        "Suggest a way another character could do something dangerous, destructive, or derailing. It is free to propose. When it is accepted, that character's player gains two boons and you gain nothing. Whether their character goes along is handled at the table."
    }


addDetail : Term
addDetail =
    { term = "Add Detail"
    , short = "Pay 1 boon to establish something true about the scene — it becomes a session boon."
    , long =
        "Propose a fact about the scene: suggest the wording yourself, or leave it blank and ask the facilitator for one. It costs one boon when accepted, and the result is a session boon anyone can spend later."
    }


alterFate : Term
alterFate =
    { term = "Alter Fate"
    , short = "Pay 2 boons to reroll a pending Overcome."
    , long =
        "Pay two boons to suggest an alternate action at the fork, and reroll. It works only while an Overcome has a roll pending, once per player per Overcome, and one at a time. A rejected Alter Fate costs nothing and does not use up your attempt."
    }


sessionBoon : Term
sessionBoon =
    { term = "Session boon"
    , short = "Something established as true, spendable into the pool — a session boon or a session bane."
    , long =
        "A note of something true in the fiction. An accepted Overcome that drew a matched pair makes one, Add Detail makes a session boon, and the facilitator can plant either kind at any time. Spending one adds a stone of its kind to the pool and marks it used: it stays on the table, visibly consumed, and cannot be spent again. Players spend session boons through a proposal; the facilitator uses session banes directly. They stay until the facilitator removes them — ending a session does not clear them."
    }



-- ASPECTS & GROWTH


aspect : Term
aspect =
    { term = "Aspect"
    , short = "One of a character's three always-true things: Archetype, Desire, Quest."
    , long =
        "Aspects are written to carry latent conflict with the world. They are always true; a Highlight makes one mechanically relevant to the roll."
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


condition : Term
condition =
    { term = "Condition"
    , short = "One evolving sentence for what strain is doing to the character."
    , long =
        "Always emotional or identity-level, never a number. It is the whole harm model — no wounds, no death mechanic. Update it when the situation actually shifts."
    }
