module Lib.Crypto.BCrypt exposing
    ( CompareOptions
    , HashOptions
    , compare
    , hash
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Json.Decode as Decode
import Json.Encode as Encode



-- Hash


type alias HashOptions =
    { saltRounds : Int
    , password : String
    }


hash : HashOptions -> ConcurrentTask x String
hash options =
    Task.define
        { function = "bcrypt:hash"
        , expect = Task.expectString
        , errors = Task.expectNoErrors
        , args =
            Encode.object
                [ ( "saltRounds", Encode.int options.saltRounds )
                , ( "password", Encode.string options.password )
                ]
        }



-- Compare


type alias CompareOptions =
    { plaintext : String
    , hashed : String
    }


compare : CompareOptions -> ConcurrentTask x Bool
compare options =
    Task.define
        { function = "bcrypt:compare"
        , expect = Task.expectJson Decode.bool
        , errors = Task.expectNoErrors
        , args =
            Encode.object
                [ ( "plaintext", Encode.string options.plaintext )
                , ( "hashed", Encode.string options.hashed )
                ]
        }
