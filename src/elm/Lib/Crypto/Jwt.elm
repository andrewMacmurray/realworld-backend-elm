module Lib.Crypto.Jwt exposing
    ( Error(..)
    , sign
    , verify
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode



-- JWT


type Error
    = SignError String
    | VerifyError String
    | DecodeError Decode.Error



-- Sign


sign : Encode.Value -> ConcurrentTask Error String
sign payload =
    Task.define
        { function = "jwt:sign"
        , expect = Task.expectString
        , errors = Task.expectThrows SignError
        , args = payload
        }



-- Verify


verify : Decoder a -> String -> ConcurrentTask Error a
verify decode token =
    Task.define
        { function = "jwt:verify"
        , expect = Task.expectJson Decode.value
        , errors = Task.expectThrows VerifyError
        , args = Encode.string token
        }
        |> Task.andThen
            (Decode.decodeValue decode
                >> Result.mapError DecodeError
                >> Task.fromResult
            )
