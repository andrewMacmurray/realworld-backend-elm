module Auth exposing
    ( Auth
    , generateToken
    , verifyToken
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Error exposing (Error)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Lib.Crypto.Jwt as Jwt



-- Auth


type alias Auth =
    { userId : Int
    , token : String
    }



-- Generate


generateToken : { user | id : Int } -> ConcurrentTask Error String
generateToken user =
    encodeAuth user
        |> Jwt.sign
        |> Task.mapError Error.jwt



-- Verify


verifyToken : String -> ConcurrentTask Error Auth
verifyToken token =
    token
        |> Jwt.verify (decodeAuth token)
        |> Task.mapError Error.jwt



-- Encode / Decode


decodeAuth : String -> Decoder Auth
decodeAuth token =
    Decode.map2 Auth
        (Decode.field "user_id" Decode.int)
        (Decode.succeed token)


encodeAuth : { user | id : Int } -> Encode.Value
encodeAuth user =
    Encode.object
        [ ( "user_id", Encode.int user.id )
        ]
