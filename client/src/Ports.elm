port module Ports exposing
    ( DiscordInbound(..)
    , authorize
    , decodeInbound
    , fromDiscord
    , wsGameState
    , wsStatus
    )

{-| The bridge between Elm and the TypeScript host (`client/src/main.ts` and
`DiscordBridge.ts`).

Ports declared here still surface on the single `app.ports` object that
`Elm.Main.init` returns; the JS side does not care which module defines them.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Types exposing (Auth, decodeRole)



-- PORTS


{-| Outbound requests to the Discord SDK (currently only `Authorize`).
-}
port toDiscord : Encode.Value -> Cmd msg


{-| Inbound messages from the Discord bridge: auth results and failures.
-}
port fromDiscord : (Decode.Value -> msg) -> Sub msg


{-| Full `GameState` snapshots pushed over the backend WebSocket.
-}
port wsGameState : (Decode.Value -> msg) -> Sub msg


{-| Backend WebSocket lifecycle, as a bare tag: `"connected"`, `"reconnecting"`,
`"offline"`, or `"rejected"`.
-}
port wsStatus : (String -> msg) -> Sub msg


authorize : List String -> Cmd msg
authorize scopes =
    toDiscord <|
        Encode.object
            [ ( "type", Encode.string "Authorize" )
            , ( "scopes", Encode.list Encode.string scopes )
            ]



-- INBOUND DECODING


{-| A message from the Discord bridge, narrowed to the cases the client acts on.
-}
type DiscordInbound
    = BackendAuth Auth
    | AuthRejected String
    | UnknownInbound


decodeInbound : Decode.Value -> DiscordInbound
decodeInbound value =
    Decode.decodeValue inboundDecoder value
        |> Result.withDefault UnknownInbound


inboundDecoder : Decode.Decoder DiscordInbound
inboundDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "BackendAuthResult" ->
                        Decode.map BackendAuth (Decode.field "data" decodeAuth)

                    "AuthFailed" ->
                        Decode.map AuthRejected (Decode.at [ "data", "message" ] Decode.string)

                    _ ->
                        Decode.succeed UnknownInbound
            )


decodeAuth : Decode.Decoder Auth
decodeAuth =
    Decode.map4 Auth
        (Decode.field "userId" Decode.string)
        (Decode.field "username" Decode.string)
        (Decode.field "role" decodeRole)
        (Decode.field "sessionToken" Decode.string)
