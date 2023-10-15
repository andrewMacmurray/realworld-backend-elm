module Lib.Http.Server.Response exposing
    ( Response
    , noContent
    , response
    , send
    , withBody
    , withHeader
    , withHeaders
    )

import Dict exposing (Dict)
import Json.Encode as Encode


type alias Response =
    { status : Int
    , body : Encode.Value
    , headers : Dict String String
    }


response : Int -> Response
response status =
    { status = status
    , body = Encode.null
    , headers = Dict.empty
    }


noContent : Response
noContent =
    response 204


withBody : Encode.Value -> Response -> Response
withBody body res =
    { res | body = body }


withHeader : String -> String -> Response -> Response
withHeader key val res =
    { res | headers = Dict.insert key val res.headers }


withHeaders : List ( String, String ) -> Response -> Response
withHeaders headers res =
    { res | headers = Dict.union (Dict.fromList headers) res.headers }


send : Int -> Encode.Value -> Response
send status body =
    response status |> withBody body
