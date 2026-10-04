module Api.Decode exposing (auth, gameState, message)

{-| Every decoder for what the Worker sends, in one place: the one boundary
where wire names become Elm names. Nothing else in the client reads JSON.

    Wire (worker/src/types.ts)          Elm
    ---------------------------------   -----------------------------------
    gameState.die (6 … 20)               GameState.die : Die
    junction.{die, face, outcome}        Junction.{die, face, outcome}
    outcome "critical-friction" …        Outcome.CriticalFriction …
    contextAspects[].kind "Boon"/"Bane"  ContextAspect.polarity : Polarity
    contextAspects[].fromAspect          ContextAspect.fromAspect : Maybe ( Int, Aspect )
    moves[].kind "highlight-context" …   MoveRecord.Kind (HighlightContext …)
    moves[].effects                      (not read: undo runs on the Worker)
    characters[].fate                    CharacterSheet.fate (the character's boons)
    "archetype" / "desire" / "quest"     Aspect.Archetype / Desire / Quest

A value the client cannot represent — a die off the ladder, an unknown outcome,
polarity or move kind — fails the decode rather than defaulting, so a client
older than its Worker shows nothing rather than something wrong.

-}

import Aspect exposing (Aspect(..))
import ContextAspect exposing (ContextAspect, Polarity(..))
import Die exposing (Die)
import Json.Decode as Decode exposing (Decoder)
import Junction exposing (Junction)
import MoveRecord exposing (MoveRecord)
import Outcome exposing (Outcome(..))
import Time
import Types exposing (Auth, CharacterSheet, GameState, Message, MessageKind(..), Role(..), Session, SessionSummary, TableEntity)


{-| Decode a string through a lookup, failing on anything it does not name.
-}
enum : String -> (String -> Maybe a) -> Decoder a
enum what lookup =
    Decode.string
        |> Decode.andThen
            (\s ->
                case lookup s of
                    Just value ->
                        Decode.succeed value

                    Nothing ->
                        Decode.fail ("Unknown " ++ what ++ " " ++ s)
            )


{-| Applies the next field decoder in a pipeline, so a record decoder can grow
past the `Decode.map8` ceiling.
-}
andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


posix : Decoder Time.Posix
posix =
    Decode.map Time.millisToPosix Decode.int



-- AUTH


{-| The `BackendAuthResult` the Discord bridge forwards (`Ports`).
-}
auth : Decoder Auth
auth =
    Decode.map4 Auth
        (Decode.field "userId" Decode.string)
        (Decode.field "username" Decode.string)
        (Decode.field "role" role)
        (Decode.field "sessionToken" Decode.string)


role : Decoder Role
role =
    enum "role"
        (\s ->
            case s of
                "facilitator" ->
                    Just Facilitator

                "player" ->
                    Just Player

                _ ->
                    Nothing
        )



-- THE LOG


{-| An unknown or missing kind reads as `Chat`, the styling every row had
before kinds existed.
-}
messageKind : Decoder MessageKind
messageKind =
    Decode.string
        |> Decode.map
            (\s ->
                if s == "event" then
                    Event

                else
                    Chat
            )


message : Decoder Message
message =
    Decode.map7 Message
        (Decode.field "id" Decode.string)
        (Decode.field "authorId" Decode.string)
        (Decode.field "authorName" Decode.string)
        (Decode.field "role" role)
        (Decode.oneOf [ Decode.field "kind" messageKind, Decode.succeed Chat ])
        (Decode.field "content" Decode.string)
        (Decode.field "createdAt" posix)



-- THE DIE AND THE JUNCTION


die : Decoder Die
die =
    Decode.int
        |> Decode.andThen
            (\n ->
                case Die.fromSize n of
                    Just d ->
                        Decode.succeed d

                    Nothing ->
                        Decode.fail ("A d" ++ String.fromInt n ++ " is not on the ladder")
            )


outcome : Decoder Outcome
outcome =
    enum "outcome"
        (\s ->
            case s of
                "critical-friction" ->
                    Just CriticalFriction

                "friction" ->
                    Just Friction

                "flow" ->
                    Just Flow

                "critical-flow" ->
                    Just CriticalFlow

                _ ->
                    Nothing
        )


junction : Decoder Junction
junction =
    Decode.map6 Junction
        (Decode.field "rolledBy" Decode.string)
        (Decode.field "die" die)
        (Decode.field "face" Decode.int)
        (Decode.field "outcome" outcome)
        (Decode.field "rerolls" Decode.int)
        (Decode.field "alteredSlots" (Decode.list Decode.int))



-- ASPECTS


aspect : Decoder Aspect
aspect =
    enum "aspect"
        (\s ->
            case s of
                "archetype" ->
                    Just Archetype

                "desire" ->
                    Just Desire

                "quest" ->
                    Just Quest

                _ ->
                    Nothing
        )


polarity : Decoder Polarity
polarity =
    enum "polarity"
        (\s ->
            case s of
                "Boon" ->
                    Just Boon

                "Bane" ->
                    Just Bane

                _ ->
                    Nothing
        )


contextAspect : Decoder ContextAspect
contextAspect =
    Decode.map6 ContextAspect
        (Decode.field "id" Decode.string)
        (Decode.field "kind" polarity)
        (Decode.field "text" Decode.string)
        (Decode.field "createdByName" Decode.string)
        (Decode.field "consumed" Decode.bool)
        (Decode.field "fromAspect"
            (Decode.nullable
                (Decode.map2 Tuple.pair
                    (Decode.field "slot" Decode.int)
                    (Decode.field "aspect" aspect)
                )
            )
        )



-- MOVES


moveKind : Decoder MoveRecord.Kind
moveKind =
    enum "move"
        (\s ->
            case s of
                "highlight" ->
                    Just MoveRecord.Highlight

                "highlight-context" ->
                    Just MoveRecord.HighlightContext

                "complicate" ->
                    Just MoveRecord.Complicate

                "create" ->
                    Just MoveRecord.Create

                "alter" ->
                    Just MoveRecord.Alter

                _ ->
                    Nothing
        )


moveRecord : Decoder MoveRecord
moveRecord =
    Decode.map7 MoveRecord
        (Decode.field "id" Decode.string)
        (Decode.field "kind" moveKind)
        (Decode.field "actorId" Decode.string)
        (Decode.field "actorName" Decode.string)
        (Decode.field "slot" (Decode.nullable Decode.int))
        (Decode.field "aspect" (Decode.nullable aspect))
        (Decode.field "messageId" Decode.string)



-- THE TABLE


session : Decoder Session
session =
    Decode.map2 Session
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)


sessionSummary : Decoder SessionSummary
sessionSummary =
    Decode.map4 SessionSummary
        (Decode.field "id" Decode.string)
        (Decode.field "goal" Decode.string)
        (Decode.field "startedAt" posix)
        (Decode.field "endedAt" posix)


aspectBanes : Decoder Types.AspectBanes
aspectBanes =
    Decode.map3 Types.AspectBanes
        (Decode.field "archetype" Decode.int)
        (Decode.field "desire" Decode.int)
        (Decode.field "quest" Decode.int)


tableEntity : Decoder TableEntity
tableEntity =
    Decode.map3 TableEntity
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "notes" Decode.string)


characterSheet : Decoder CharacterSheet
characterSheet =
    Decode.succeed CharacterSheet
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "slot" Decode.int)
        |> andMap (Decode.field "name" Decode.string)
        |> andMap (Decode.field "notableFeatures" Decode.string)
        |> andMap (Decode.field "archetype" Decode.string)
        |> andMap (Decode.field "desire" Decode.string)
        |> andMap (Decode.field "quest" Decode.string)
        |> andMap (Decode.field "condition" Decode.string)
        |> andMap (Decode.field "notes" Decode.string)
        |> andMap (Decode.field "fate" Decode.int)
        |> andMap (Decode.field "aspectBanes" aspectBanes)
        |> andMap (Decode.field "ownerId" (Decode.nullable Decode.string))


gameState : Decoder GameState
gameState =
    Decode.succeed GameState
        |> andMap (Decode.field "sessionId" Decode.string)
        |> andMap (Decode.field "messages" (Decode.list message))
        |> andMap (Decode.field "die" die)
        |> andMap (Decode.field "junction" (Decode.nullable junction))
        |> andMap (Decode.field "moves" (Decode.list moveRecord))
        |> andMap (Decode.field "session" (Decode.nullable session))
        |> andMap (Decode.field "characters" (Decode.list characterSheet))
        |> andMap (Decode.field "sessionHistory" (Decode.list sessionSummary))
        |> andMap (Decode.field "contextAspects" (Decode.list contextAspect))
        |> andMap (Decode.field "npcs" (Decode.list tableEntity))
        |> andMap (Decode.field "locations" (Decode.list tableEntity))
