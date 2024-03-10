module Lib.Http.Server.Response exposing
    ( Errors
    , Response
    , error
    , noContent
    , respond
    , sendErrors
    , sendJson
    , withHeader
    , withHeaders
    , withJsonBody
    )

import Dict exposing (Dict)
import Json.Encode as Encode


type alias Response =
    { status : Int
    , body : Encode.Value
    , headers : Dict String String
    }


respond : Int -> Response
respond status =
    { status = status
    , body = Encode.null
    , headers = Dict.empty
    }


noContent : Response
noContent =
    respond 204


withJsonBody : Encode.Value -> Response -> Response
withJsonBody body res =
    { res | body = body }
        |> withHeader "Content-type" "application/json"


withHeader : String -> String -> Response -> Response
withHeader key val res =
    { res | headers = Dict.insert key val res.headers }


withHeaders : List ( String, String ) -> Response -> Response
withHeaders headers res =
    { res | headers = Dict.union (Dict.fromList headers) res.headers }


sendJson : Int -> Encode.Value -> Response
sendJson status body =
    respond status |> withJsonBody body



-- Errors


type alias Errors =
    { status : Int
    , errors : List ( String, List Encode.Value )
    }


error : Int -> String -> List Encode.Value -> Errors
error status name details =
    { status = status
    , errors = [ ( name, details ) ]
    }


sendErrors : Errors -> Response
sendErrors e =
    sendJson e.status
        (Encode.object
            [ ( "errors"
              , e.errors
                    |> Dict.fromList
                    |> Encode.dict identity (Encode.list identity)
              )
            ]
        )
