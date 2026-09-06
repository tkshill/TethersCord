module Copy.Terms exposing (Term, groupedTerms, termShort, terms)

{-| The game's vocabulary in one place: every term a player meets in the
interface, each with a one-line `short` (used as a tooltip on the label where the
term appears) and a two-to-three-sentence `long` (shown in the "How to play"
card). One definition, two surfaces.

The wording tracks `CLAUDE.md`, `DESIGN_PRINCIPLES.md`, and roadmap section 19.
It is meant to be revised freely — this module has no logic, only data.
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
    , ( "The session", [ session, goal, sessionPool, carry ] )
    , ( "Stones & rolling"
      , [ stone, boon, bane, theBag, roll, overcome, highlight, pledge, proposal ]
      )
    , ( "Aspects & growth"
      , [ aspect, archetype, desire, quest, condition, untether, frenzy ]
      )
    , ( "Moves & compels"
      , [ compel, acceptCompel, suggestCompel, floatingBoon, helpOut, addDetail, gainInsight ]
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
    , short = "One game day with a goal, carrying its own pool of stones."
    , long =
        "A session runs from the facilitator starting it — naming a goal — to ending it. Its own stone pool fills from the rolls made during it, and at the end one stone is drawn from that pool to say whether the goal was met."
    }


goal : Term
goal =
    { term = "Goal"
    , short = "What the table is working toward this session."
    , long =
        "Set by the facilitator when the session starts, and editable at any time. At session end a single stone drawn from the session pool decides it: a Boon means the goal was met, a Bane means it failed."
    }


sessionPool : Term
sessionPool =
    { term = "Session pool"
    , short = "Stones a session gathers from its rolls; one is drawn at the end to judge the goal."
    , long =
        "Separate from the bag. Overcome results feed it — two of a kind whole, a mixed roll's Boon only. At session end one stone is drawn from it to decide the goal. Then its Boons flush and its Banes carry into the next session."
    }


carry : Term
carry =
    { term = "Carry"
    , short = "Banes held over from last session, already in this session's pool."
    , long =
        "A met goal keeps the pool's Banes for next session and flushes its Boons; a failed goal flushes everything. Because Banes build up and Boons do not, goals get harder each session until a failure resets the pool."
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
    , short = "An unfavourable stone; Banes stick to aspects and carry between sessions."
    , long =
        "The bad result of a draw. A mixed overcome roll drops one onto one of the acting character's three aspects at random, where it stays until an untether clears it. Banes in the session pool carry over; Boons do not."
    }


theBag : Term
theBag =
    { term = "The bag"
    , short = "The four base stones — two Boon, two Bane — plus any boons pledged into this roll."
    , long =
        "Every roll starts from the same four. Highlighting an aspect pledges boons into the bag, each adding a Boon and tilting the odds; those pledged boons are spent when the roll is accepted."
    }


roll : Term
roll =
    { term = "Roll"
    , short = "Draw two stones from the bag to resolve a risky attempt."
    , long =
        "The core mechanic. Two stones come out: two of a kind both feed the session pool; a mixed pair sends the Boon to the pool and a Bane onto one of the acting character's aspects at random."
    }


overcome : Term
overcome =
    { term = "Overcome"
    , short = "A framed risky attempt by one character. Draw two stones from the bag."
    , long =
        "The facilitator names the character attempting something hard; that player, or the facilitator, rolls. The result routes as any roll does. Accepting it closes the overcome, and the verdict is played out in the fiction."
    }


highlight : Term
highlight =
    { term = "Highlight"
    , short = "Spend a boon to add a favourable stone to your next roll, because an aspect is true now."
    , long =
        "Point at one of your aspects and spend boons from your sheet; each adds a Boon to the bag for the next roll. The boons are deducted when the roll is accepted. A reroll keeps them in."
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
        "Aspects are written to carry latent conflict with the world. They are always true; a Highlight only makes one mechanically relevant for a roll. They only ever accumulate Banes, and are rewritten or replaced after an untether."
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


untether : Term
untether =
    { term = "Untether"
    , short = "A failed goal breaks one character on one aspect; they must rewrite or replace it."
    , long =
        "Also called a reckoning. When a session goal fails, one Bane is drawn from across every aspect of every character; its owner comes untethered on that aspect and all their aspect Banes clear. One at a time, never on two failures running, and the scene resolves by the end of the next session."
    }


frenzy : Term
frenzy =
    { term = "Frenzy"
    , short = "The session a character is untethered: they cannot Highlight the broken aspect."
    , long =
        "While untethered the character is in full focus. The broken aspect cannot justify a Highlight, though the other two still can, and their own mixed-roll Banes go to the session pool instead of onto an aspect."
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
        "The move for accepting a compel the facilitator has offered. Raised as a proposal; on approval the proposer is paid two boons."
    }


suggestCompel : Term
suggestCompel =
    { term = "Suggest Compel"
    , short = "Once per session, point the facilitator at another character for a compel."
    , long =
        "Name another player's character as a good target for a compel. If the facilitator runs with it, you take one boon and the compelled character takes two. Their consent is handled at the table."
    }


floatingBoon : Term
floatingBoon =
    { term = "Floating boon"
    , short = "A boon owned by nobody, from an approved Add a Detail or Gain Insight."
    , long =
        "Created when the facilitator approves an Add a Detail or Gain Insight, with a note of the context it stands for. Any player can spend it on a roll, as a Highlight the facilitator approves. Unspent ones are discarded at session end."
    }


helpOut : Term
helpOut =
    { term = "Help Out"
    , short = "Once per session, reroll the open overcome for free."
    , long =
        "Available only while an overcome roll is on the table. On approval the roll is redrawn with no Press Fate cost."
    }


addDetail : Term
addDetail =
    { term = "Add a Detail"
    , short = "Once per session, establish something true about the scene — it becomes a floating boon."
    , long =
        "Propose a fact about the situation. The facilitator types the context and approves, and a floating boon enters the session for anyone to spend."
    }


gainInsight : Term
gainInsight =
    { term = "Gain Insight"
    , short = "Once per session, learn something from the facilitator — it becomes a floating boon."
    , long =
        "The same effect as Add a Detail: an approved question or realisation, noted by the facilitator, becomes a floating boon. The answer itself is table talk."
    }
