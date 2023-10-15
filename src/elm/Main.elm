port module Main exposing (main)

import Json.Decode as Decode
import Lib.Http.Server as Server
import Lib.Http.Server.Response as Response
import Routes



-- Program


main : Program {} Server.Model Server.Msg
main =
    Server.worker
        { routes =
            Routes.all
                |> Server.handleOptions handleCorsOptions
                |> Server.mapResponse (corsHeaders >> appHeaders)
        , ports =
            { onRequest = onRequest
            , respond = respond
            , send = send
            , receive = receive
            }
        }



-- CORS Options


handleCorsOptions : List String -> Server.Endpoint () err ()
handleCorsOptions methods =
    Response.noContent
        |> Response.withHeader "Access-Control-Allow-Methods" (String.join "," methods)
        |> Server.respond


corsHeaders : Server.Response -> Server.Response
corsHeaders =
    Response.withHeaders
        [ ( "Access-Control-Allow-Origin", "*" )
        , ( "Access-Control-Allow-Headers"
          , String.join ","
                [ "X-Requested-With"
                , "Accept"
                , "Authorization"
                , "Accept-Version"
                , "Content-Length"
                , "Content-MD5"
                , "Content-Type"
                , "Date"
                , "X-Api-Version"
                ]
          )
        ]


appHeaders : Server.Response -> Server.Response
appHeaders =
    Response.withHeader "X-Powered-By" "Elm + Elm Concurrent Task"



-- Ports


port send : Decode.Value -> Cmd msg


port receive : (Decode.Value -> msg) -> Sub msg


port onRequest : (Server.RawRequest -> msg) -> Sub msg


port respond : Server.RawResponse -> Cmd msg
