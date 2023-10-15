module Lib.Http.Server.Header exposing
    ( Error(..)
    , Headers
    , Raw
    , andThen
    , handleError
    , map
    , optional
    , run
    , string
    , succeed
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Lib.Http.Server.Response exposing (Response)



-- Headers


type Headers x a
    = Headers (Raw -> ConcurrentTask (Error x) a)


type alias Raw =
    Dict String String


type Error x
    = MissingHeader String
    | HeaderDecodeError String Decode.Error
    | TaskError x



-- Construct


string : String -> Headers x String
string name =
    decodeHeader name Decode.string


optional : Headers x a -> Headers x (Maybe a)
optional (Headers h) =
    Headers
        (\raw ->
            h raw
                |> Task.map Just
                |> Task.onError (\_ -> Task.succeed Nothing)
        )



-- Transform


map : (a -> b) -> Headers x a -> Headers x b
map f (Headers task) =
    Headers (\raw -> Task.map f (task raw))


succeed : a -> Headers x a
succeed a =
    Headers (\_ -> Task.succeed a)


andThen : (a -> ConcurrentTask x b) -> Headers x a -> Headers x b
andThen f (Headers h) =
    Headers (\raw -> h raw |> Task.andThen (f >> Task.mapError TaskError))


run : Headers x a -> Raw -> ConcurrentTask (Error x) a
run (Headers task) raw =
    task raw



-- Errors


handleError : (Encode.Value -> Response) -> (x -> Response) -> Error x -> Response
handleError toResponse handle err =
    case err of
        MissingHeader h ->
            toResponse
                (Encode.object
                    [ ( "headers"
                      , Encode.object
                            [ ( h, Encode.string "Missing required request header" )
                            ]
                      )
                    ]
                )

        HeaderDecodeError name x ->
            toResponse
                (Encode.object
                    [ ( "headers"
                      , Encode.object
                            [ ( name, Encode.string (Decode.errorToString x) )
                            ]
                      )
                    ]
                )

        TaskError x ->
            handle x



-- Internal


decodeHeader : String -> Decoder a -> Headers x a
decodeHeader name decoder =
    Headers
        (\raw ->
            case Dict.get (String.toLower name) raw of
                Nothing ->
                    Task.fail (MissingHeader name)

                Just a ->
                    Decode.decodeValue decoder (Encode.string a)
                        |> Result.mapError (HeaderDecodeError name)
                        |> Task.fromResult
        )
