module Copy.Terms exposing (Term, groupedTerms, termShort, terms)

{-| The game's vocabulary in one place: every term a player meets in the
interface, each with a one-line `short` (used as a tooltip on the label where the
term appears) and a two-to-three-sentence `long` (shown in the "How to play"
card). One definition, two surfaces.

The wording tracks `CLAUDE.md` and `DESIGN_PRINCIPLES.md`. It is meant to be
revised freely — this module has no logic, only data.
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
    , ( "Stones & rolling"
      , [ stone, boon, bane, theBag, roll, overcome, highlight, pledge, proposal ]
      )
    , ( "Aspects & growth"
      , [ aspect, archetype, desire, quest, condition ]
      )
    , ( "Moves & compels"
      , [ compel, acceptCompel, complicate, floatingBoon, alter, addDetail, gainInsight ]
      )
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
    , short = "Frames scenes, plays the world, and rules on proposals."
    , long =
        "An asymmetric role, not a leader. The facilitator presents situations, plays everyone who is not a player character, offers compels, and accepts or rejects the proposals players raise. They roll and grant boons directly; players go through proposals."
    }


player : Term
player =
    { term = "Player"
    , short = "Runs one character — their wants, choices, and risks."
    , long =
        "Each player drives a single character: what they want, what they will risk for it, and how they act under pressure. Players edit their own sheet directly, but change shared state — the pool, the roll, another sheet — by raising a proposal."
    }



-- THE SESSION


session : Term
session =
    { term = "Session"
    , short = "One game day, with a goal the table names and works toward."
    , long =
        "A session runs from the facilitator starting it — naming a goal — to ending it. The goal is table talk, not a mechanic: nothing rolls to judge whether it was met. The stone pool runs independently of session boundaries; ending a session only tops it back up if it has run short."
    }


goal : Term
goal =
    { term = "Goal"
    , short = "What the table is working toward this session."
    , long =
        "Set by the facilitator when the session starts, and editable at any time. It names a target for the fiction; whether it is met is for the table to decide by playing it out, not by a roll."
    }



-- STONES & ROLLING


stone : Term
stone =
    { term = "Stone"
    , short = "The unit of chance — drawn from a bag, it is either a Boon or a Bane."
    , long =
        "Every risky action is resolved by drawing stones. There are only two kinds, Boon and Bane, so an outcome is read from the fiction rather than compared against a number."
    }


boon : Term
boon =
    { term = "Boon"
    , short = "A favourable stone, and the currency a character banks and spends."
    , long =
        "As an outcome, the good result of a draw. As a resource, the boons on a character's sheet — earned from compels and moves, spent to Highlight an aspect and tilt a roll."
    }


bane : Term
bane =
    { term = "Bane"
    , short = "An unfavourable stone; Banes stick to aspects and accumulate there."
    , long =
        "The bad result of a draw. A mixed overcome roll drops one onto one of the acting character's three aspects at random, where it accumulates. A Bane drawn any other way stays in the pool, same as a Boon."
    }


theBag : Term
theBag =
    { term = "The bag"
    , short = "The one shared pool every roll draws from, plus any boons pledged into this roll."
    , long =
        "Nothing resets it — a fresh table starts with two Boon and two Bane, and from there it only changes through rolls and moves. Ending a session tops it back up to that floor if it has run short. Highlighting an aspect pledges boons into it for the next roll, each adding a Boon and tilting the odds; those pledged boons are spent when the roll is accepted."
    }


roll : Term
roll =
    { term = "Roll"
    , short = "Draw two stones from the bag to resolve a risky attempt."
    , long =
        "The core mechanic. The two drawn stones leave the bag; two of a kind both return whole, while a mixed pair returns only the Boon and sends the Bane onto one of the acting character's aspects at random."
    }


overcome : Term
overcome =
    { term = "Overcome"
    , short = "The facilitator declares a split point where the plot could diverge."
    , long =
        "The facilitator declares a split point in the narrative where the plot could diverge. That fork is what an Alter can later pay to resolve down an alternate path."
    }


highlight : Term
highlight =
    { term = "Highlight"
    , short = "Spend a boon to note how an aspect will shape the outcome, adding a boon to the pool."
    , long =
        "Spend one boon to note how an aspect of the scene will influence the outcome, and add one boon to the pool."
    }


pledge : Term
pledge =
    { term = "Pledge"
    , short = "Boons committed to the next roll — the mechanic under Highlight."
    , long =
        "Pledged boons sit in the bag as marked stones and come off the character's sheet once the roll is accepted. Until then the proposer can withdraw them."
    }


proposal : Term
proposal =
    { term = "Proposal"
    , short = "A change a player wants to shared state; it waits for the facilitator to accept or reject."
    , long =
        "Players do not touch the pool, the roll, or another sheet directly — they raise a proposal, such as Add boon, Highlight, or a move, that queues for the facilitator. Nothing happens until it is accepted, and you can withdraw your own while it is pending."
    }



-- ASPECTS & GROWTH


aspect : Term
aspect =
    { term = "Aspect"
    , short = "One of a character's three always-true things: Archetype, Desire, Quest."
    , long =
        "Aspects are written to carry latent conflict with the world. They are always true; a Highlight only makes one mechanically relevant for a roll. They only ever accumulate Banes."
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
    , short = "One evolving sentence for what the accumulated strain is doing to the character."
    , long =
        "Rewritten after a Bane lands, always emotional or identity-level, never a number. It is the whole harm model — no wounds, no death mechanic. Update it when the situation actually shifts, not once per Bane."
    }



-- MOVES & COMPELS


compel : Term
compel =
    { term = "Compel"
    , short = "The facilitator offers a complication; accepting it pays boons and costs nothing else."
    , long =
        "Strictly positive and facilitator-gated. A fictional twist that makes a scene harder or more interesting; the player who takes it is paid in boons, with no mechanical penalty. Whether the character consents is table talk."
    }


acceptCompel : Term
acceptCompel =
    { term = "Accept Compel"
    , short = "Take the offered complication for two boons. Any time."
    , long =
        "The move for accepting a compel the facilitator has offered."
    }


complicate : Term
complicate =
    { term = "Complicate"
    , short = "Once per session, suggest a dangerous, destructive, or derailing action for another character."
    , long =
        "Suggest a way a character could do something dangerous, destructive, or derailing. That character's player gains two boons. Their consent is handled at the table."
    }


floatingBoon : Term
floatingBoon =
    { term = "Session aspect"
    , short = "A Boon or a Bane owned by nobody, planted by the facilitator."
    , long =
        "A session context — a Boon or a Bane, with a note of what it stands for — the facilitator plants directly, or approves from a player's Add a Detail or Gain Insight (always a Boon). It stays until the facilitator removes it, or the session ends."
    }


alter : Term
alter =
    { term = "Alter"
    , short = "Pay two boons to suggest an alternate action at a fork, triggering a re-roll."
    , long =
        "Pay two boons to suggest an alternate action to resolve a fork. Triggers a re-roll."
    }


addDetail : Term
addDetail =
    { term = "Add a Detail"
    , short = "Once per session, establish something true about the scene — it becomes a floating boon."
    , long =
        "Propose a fact or additional detail to the scene about the situation. The facilitator types the context and approves, and a floating boon enters the session for anyone to spend."
    }


gainInsight : Term
gainInsight =
    { term = "Gain Insight"
    , short = "Once per session, learn something from the facilitator — it becomes a floating boon."
    , long =
        "Ask the facilitator a question or for clarification about the scene. They'll answer to the best of their ability. Once approved, a floating boon is created for anyone to spend if they can make it related to their action."
    }
