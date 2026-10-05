module LogLine exposing (Event, Lead(..), Mark(..), Parsed(..), Roll, parse)

{-| What the log can draw from an event line (roadmap 32.6). A message is
stored text plus its `kind`, written once by the Worker's `logText`
(`worker/src/rules/log.ts`); this reads the structure back out of that text
— the move or roll it records and the die change at its end — so the log can
mark the line and set the change in a chip without a migration or a wire
change (the roadmap 32 decision). A line it does not recognise is a plain
event with no mark and no chip, so a new or reworded log line degrades to
text rather than breaking.

`LogLineTest` pins this against each line `logText` writes; a change to a
line's wording there needs the matching change here.
-}

import Outcome exposing (Outcome(..))


{-| The mark in an event line's mark column.
-}
type Mark
    = BoonMark
    | BaneMark
    | UpMark
    | DownMark


type Parsed
    = EventLine Event
    | RollLine Roll


{-| An event line: its text with any die change taken off the end, the mark
for its column, the die change as `( "d10", "d12" )`, and whether the text
already names who acted (a move names its character), in which case the log
does not add the author after it.
-}
type alias Event =
    { text : String
    , mark : Maybe Mark
    , step : Maybe ( String, String )
    , namesActor : Bool
    }


{-| A roll, a reroll or an Alter: the outcome, the face and its die, and
what happened.
-}
type alias Roll =
    { outcome : Outcome
    , face : Int
    , die : String
    , lead : Lead
    }


{-| Which kind of roll a roll line records, and who made it where the line
says: the Junction's roller (a Discord name), or the character that Altered.
-}
type Lead
    = Rolled String
    | Rerolled
    | Altered String


parse : String -> Parsed
parse content =
    case rollLine content of
        Just roll ->
            RollLine roll

        Nothing ->
            EventLine (eventLine content)


{-| `Junction — <name> rolled: <roll>`, `Reroll — <roll>`, and
`Alter — <label> pays <n> boons, rerolled: <roll>`.
-}
rollLine : String -> Maybe Roll
rollLine content =
    case String.split " — " content of
        "Junction" :: rest ->
            case splitOnce " rolled: " (String.join " — " rest) of
                Just ( who, roll ) ->
                    rollText roll |> Maybe.map (\r -> r (Rolled who))

                Nothing ->
                    Nothing

        [ "Reroll", outcomeText, faceText ] ->
            rollText (outcomeText ++ " — " ++ faceText) |> Maybe.map (\r -> r Rerolled)

        "Alter" :: rest ->
            case splitOnce " pays " (String.join " — " rest) of
                Just ( label, paid ) ->
                    case splitOnce "rerolled: " paid of
                        Just ( _, roll ) ->
                            rollText roll |> Maybe.map (\r -> r (Altered label))

                        Nothing ->
                            Nothing

                Nothing ->
                    Nothing

        _ ->
            Nothing


{-| `Flow — 7 on d10`, waiting for its lead.
-}
rollText : String -> Maybe (Lead -> Roll)
rollText text =
    case String.split " — " text of
        [ outcomeText, faceText ] ->
            case ( outcomeNamed outcomeText, String.split " on " faceText ) of
                ( Just o, [ face, die ] ) ->
                    case ( String.toInt face, isDie die ) of
                        ( Just f, True ) ->
                            Just (\lead -> { outcome = o, face = f, die = die, lead = lead })

                        _ ->
                            Nothing

                _ ->
                    Nothing

        _ ->
            Nothing


outcomeNamed : String -> Maybe Outcome
outcomeNamed text =
    case text of
        "Critical Friction" ->
            Just CriticalFriction

        "Friction" ->
            Just Friction

        "Flow" ->
            Just Flow

        "Critical Flow" ->
            Just CriticalFlow

        _ ->
            Nothing


eventLine : String -> Event
eventLine content =
    let
        ( text, step ) =
            dieChange content

        stepMark =
            case step of
                Just ( from, to ) ->
                    if dieSize to > dieSize from then
                        Just UpMark

                    else
                        Just DownMark

                Nothing ->
                    Nothing

        startsWith prefix =
            String.startsWith prefix content
    in
    if startsWith "Highlight Context — " || startsWith "Highlight — " then
        { text = text, mark = stepMark, step = step, namesActor = True }

    else if startsWith "Die stepped " then
        { text = text, mark = stepMark, step = step, namesActor = False }

    else if startsWith "Complicate — " then
        { text = text, mark = Just BaneMark, step = step, namesActor = True }

    else if startsWith "Create — " then
        { text = text, mark = Just BoonMark, step = step, namesActor = True }

    else if startsWith "Session note added (Boon)" then
        { text = text, mark = Just BoonMark, step = step, namesActor = False }

    else if startsWith "Session note added (Bane)" then
        { text = text, mark = Just BaneMark, step = step, namesActor = False }

    else
        { text = text
        , mark = Nothing
        , step = step
        , namesActor = String.contains " undone — " content
        }


{-| The `— d10 → d12` trailer, taken off the end of a line that changes the
die.
-}
dieChange : String -> ( String, Maybe ( String, String ) )
dieChange content =
    case List.reverse (String.split " — " content) of
        last :: before :: earlier ->
            case String.split " → " last of
                [ from, to ] ->
                    if isDie from && isDie to then
                        ( String.join " — " (List.reverse (before :: earlier)), Just ( from, to ) )

                    else
                        ( content, Nothing )

                _ ->
                    ( content, Nothing )

        _ ->
            ( content, Nothing )


isDie : String -> Bool
isDie text =
    String.startsWith "d" text && String.toInt (String.dropLeft 1 text) /= Nothing


dieSize : String -> Int
dieSize die =
    String.toInt (String.dropLeft 1 die) |> Maybe.withDefault 0


splitOnce : String -> String -> Maybe ( String, String )
splitOnce separator text =
    case String.indexes separator text of
        i :: _ ->
            Just ( String.left i text, String.dropLeft (i + String.length separator) text )

        [] ->
            Nothing
