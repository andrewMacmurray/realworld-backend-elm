module Lib.Http.Server exposing
    ( Endpoint
    , Error(..)
    , HandlerResponse
    , Model
    , Msg
    , RawRequest
    , RawResponse
    , Request
    , RequestError(..)
    , RequestPool
    , Resolver
    , Response
    , Route
    , Routes
    , andThen
    , delete
    , endpoint
    , get
    , handleOptions
    , handleRequest
    , handleResponse
    , mapResponse
    , path
    , post
    , program
    , put
    , request
    , respond
    , routes
    , sendJson
    , subscriptions
    , withHeaders
    , withJsonBody
    , withParams
    , withQuery
    , worker
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Lib.Http.Server.Header as Header exposing (Headers)
import Lib.Http.Server.Param as Param exposing (Params)
import Lib.Http.Server.Query as Query exposing (Query)
import Lib.Http.Server.Response as Response
import Set exposing (Set)



-- Http Server


type Request x a
    = Request (Context -> ConcurrentTask (Error x) a)


type Error x
    = RequestError (RequestError x)
    | HandlerError x


type RequestError x
    = BodyError Decode.Error
    | HeadersError (Header.Error x)
    | ParamsError Param.Error


type alias Context =
    { pathParams : Param.Raw
    , headers : Header.Raw
    , query : Query.Raw
    , requestBody : Encode.Value
    }


type alias Endpoint req err res =
    { request : Request err req
    , handler : req -> ConcurrentTask err res
    , respond : Result (Error err) res -> Response
    }


type alias Response =
    Response.Response


type alias Route =
    { method : String
    , path : String
    , handler : Context -> ConcurrentTask Response Response
    }


type Routes
    = Path String (List Routes)
    | Routes (List Routes)
    | Base Route



-- Routes


get : String -> Endpoint req err res -> Routes
get =
    method "GET"


post : String -> Endpoint req err res -> Routes
post =
    method "POST"


put : String -> Endpoint req err res -> Routes
put =
    method "PUT"


delete : String -> Endpoint req err res -> Routes
delete =
    method "DELETE"


options : String -> Endpoint req err res -> Routes
options =
    method "OPTIONS"


method : String -> String -> Endpoint req err res -> Routes
method method_ path_ endpoint_ =
    Base
        { method = method_
        , path = path_
        , handler = toHandler endpoint_
        }


path : String -> List Routes -> Routes
path =
    Path


routes : List Routes -> Routes
routes =
    Routes



-- Endpoint


endpoint :
    { handler : req -> ConcurrentTask err res
    , respond : Result (Error err) res -> Response
    }
    -> Request err req
    -> Endpoint req err res
endpoint ep req =
    { request = req
    , handler = ep.handler
    , respond = ep.respond
    }


respond : Response -> Endpoint () x ()
respond res =
    endpoint
        { handler = Task.succeed
        , respond = always res
        }
        (request ())


toHandler : Endpoint req err res -> Context -> ConcurrentTask Response Response
toHandler endpoint_ context =
    runRequest context endpoint_.request
        |> Task.mapError (Err >> endpoint_.respond)
        |> Task.andThen
            (\req ->
                endpoint_.handler req
                    |> Task.map Ok
                    |> Task.onError (HandlerError >> Err >> Task.succeed)
                    |> Task.map endpoint_.respond
            )


runRequest : Context -> Request x a -> ConcurrentTask (Error x) a
runRequest context (Request run) =
    run context



-- Json Response


sendJson : (x -> Response.Errors) -> Int -> (a -> Encode.Value) -> Result (Error x) a -> Response
sendJson handleError status encode res =
    case res of
        Ok a ->
            Response.sendJson status (encode a)

        Err e ->
            Response.sendErrors (toErrors handleError e)


toErrors : (x -> Response.Errors) -> Error x -> Response.Errors
toErrors handleError e =
    case e of
        RequestError re_ ->
            case re_ of
                BodyError e_ ->
                    Response.error 422 "body" (bodyErrors e_ [])

                HeadersError e_ ->
                    Header.handleError 422 handleError e_

                ParamsError e_ ->
                    Response.error 422 "params" (Param.errors e_)

        HandlerError e_ ->
            handleError e_


bodyErrors : Decode.Error -> List Encode.Value -> List Encode.Value
bodyErrors err xs =
    case err of
        Decode.Field field (Decode.Failure reason _) ->
            Encode.string (field ++ " " ++ reason) :: xs

        Decode.Field _ e ->
            bodyErrors e xs

        Decode.Index i (Decode.Failure reason _) ->
            Encode.string ("Problem at index " ++ String.fromInt i ++ " " ++ reason) :: xs

        Decode.Index _ e ->
            bodyErrors e xs

        Decode.OneOf errs ->
            List.concatMap (\x -> bodyErrors x xs) errs

        Decode.Failure reason _ ->
            Encode.string reason :: xs



-- Options Routes


handleOptions : (List String -> Endpoint req err res) -> Routes -> Routes
handleOptions handler baseRoutes =
    let
        build : Route -> Dict String (Set String) -> Dict String (Set String)
        build route =
            Dict.update route.path
                (\entry ->
                    case entry of
                        Just methods ->
                            Just (Set.insert route.method methods)

                        Nothing ->
                            Just (Set.singleton route.method)
                )

        optionsRoutes : Routes
        optionsRoutes =
            flattenRoutes baseRoutes
                |> List.foldl build Dict.empty
                |> Dict.map (\path_ methods -> options path_ (handler (Set.toList methods)))
                |> Dict.values
                |> routes
    in
    routes
        [ optionsRoutes
        , baseRoutes
        ]



-- Middleware


mapResponse : (Response -> Response) -> Routes -> Routes
mapResponse toRes routes_ =
    case routes_ of
        Base route ->
            Base { route | handler = route.handler >> Task.map toRes >> Task.mapError toRes }

        Path base rx ->
            Path base (List.map (mapResponse toRes) rx)

        Routes rx ->
            Routes (List.map (mapResponse toRes) rx)



-- Create Request


request : a -> Request x a
request fn =
    Request (\_ -> Task.succeed fn)


andThen : (a -> ConcurrentTask x b) -> Request x a -> Request x b
andThen f (Request run) =
    Request (\context -> run context |> Task.andThen (f >> Task.mapError HandlerError))



-- Body


withJsonBody : Decoder a -> Request x (a -> b) -> Request x b
withJsonBody decoder (Request req) =
    Request
        (\context ->
            req context
                |> Task.andThen
                    (\a ->
                        case Decode.decodeValue decoder context.requestBody of
                            Ok b ->
                                Task.succeed (a b)

                            Err x ->
                                Task.fail (RequestError (BodyError x))
                    )
        )



-- Params


withParams : Params a -> Request x (a -> b) -> Request x b
withParams params (Request req) =
    Request
        (\context ->
            req context
                |> Task.andThen
                    (\a ->
                        case Param.decode params context.pathParams of
                            Ok b ->
                                Task.succeed (a b)

                            Err e ->
                                Task.fail (RequestError (ParamsError e))
                    )
        )



-- Headers


withHeaders : Headers x a -> Request x (a -> b) -> Request x b
withHeaders headers (Request req) =
    Request
        (\context ->
            Task.map2 (\req_ headers_ -> req_ headers_)
                (req context)
                (context.headers
                    |> Header.run headers
                    |> Task.mapError (HeadersError >> RequestError)
                )
        )



-- Query


withQuery : Query a -> Request x (a -> b) -> Request x b
withQuery params (Request req) =
    Request
        (\context ->
            req context
                |> Task.map (\next -> next (Query.decode params context.query))
        )



-- Raw Request Response


type alias RawRequest =
    { resolve : Resolver
    , request :
        { body : Encode.Value
        , headers : Encode.Value
        , query : Encode.Value
        , method : String
        , path : String
        }
    }


type alias RawResponse =
    { resolve : Resolver
    , response :
        { body : Encode.Value
        , headers : Encode.Value
        , status : Int
        }
    }


type alias Resolver =
    Encode.Value


type alias RequestPool msg =
    Task.Pool msg Response Response


type alias HandlerResponse =
    Task.Response Response Response


type alias RequestOptions msg =
    { routes : Routes
    , request : RawRequest
    , requests : RequestPool msg
    , send : Encode.Value -> Cmd msg
    , onResponse : HandlerResponse -> msg
    }


type alias ResponseOptions =
    { resolve : Encode.Value
    , response : HandlerResponse
    }


handleResponse : ProgramOptions -> ResponseOptions -> Cmd Msg
handleResponse program_ options_ =
    case options_.response of
        Task.Success res ->
            program_.ports.respond
                { resolve = options_.resolve
                , response =
                    { body = res.body
                    , headers = encodeHeaders res.headers
                    , status = res.status
                    }
                }

        Task.Error res ->
            program_.ports.respond
                { resolve = options_.resolve
                , response =
                    { body = res.body
                    , headers = encodeHeaders res.headers
                    , status = res.status
                    }
                }

        Task.UnexpectedError e ->
            program_.ports.respond
                { resolve = options_.resolve
                , response =
                    { body = encodeUnexpectedError e
                    , headers = encodeHeaders Dict.empty
                    , status = 500
                    }
                }


encodeHeaders : Dict String String -> Encode.Value
encodeHeaders =
    Encode.dict identity Encode.string


encodeUnexpectedError : Task.UnexpectedError -> Encode.Value
encodeUnexpectedError e =
    Encode.object
        [ ( "error", Encode.string "Internal Server Error" )
        , ( "reason", Encode.string (unexpectedErrorToString e) )
        ]


unexpectedErrorToString : Task.UnexpectedError -> String
unexpectedErrorToString err =
    case err of
        Task.UnhandledJsException e ->
            "Unhandled JS Exception: " ++ e.function ++ "," ++ e.message

        Task.ResponseDecoderFailure e ->
            "Response Decoder Failure: " ++ e.function ++ "," ++ Decode.errorToString e.error

        Task.ErrorsDecoderFailure e ->
            "Errors Decoder Failure: " ++ e.function ++ "," ++ Decode.errorToString e.error

        Task.MissingFunction e ->
            "Missing Function: " ++ e

        Task.InternalError e ->
            "Task Runner Error: " ++ e


handleRequest : ProgramOptions -> RequestOptions Msg -> ( RequestPool Msg, Cmd Msg )
handleRequest program_ options_ =
    findMatchingRoute options_.request options_.routes
        |> Maybe.map
            (\match ->
                Task.attempt
                    { pool = options_.requests
                    , onComplete = options_.onResponse
                    , send = options_.send
                    }
                    (match.route.handler (toRequestContext match.params options_.request))
            )
        |> Maybe.withDefault
            ( options_.requests
            , program_.ports.respond
                { resolve = options_.request.resolve
                , response =
                    { status = 404
                    , headers = encodeHeaders Dict.empty
                    , body = Encode.object [ ( "message", Encode.string "Not Found" ) ]
                    }
                }
            )


toRequestContext : Param.Raw -> RawRequest -> Context
toRequestContext params rawRequest =
    { headers = toRawHeaders rawRequest
    , query = toRawQuery rawRequest
    , pathParams = params
    , requestBody = rawRequest.request.body
    }


toRawHeaders : RawRequest -> Dict String String
toRawHeaders raw =
    Decode.decodeValue (Decode.dict Decode.string) raw.request.headers
        |> Result.withDefault Dict.empty


toRawQuery : RawRequest -> Dict String String
toRawQuery raw =
    Decode.decodeValue (Decode.dict Decode.string) raw.request.query
        |> Result.withDefault Dict.empty



-- Route Matcher


type alias Match =
    { route : Route
    , params : Param.Raw
    }


findMatchingRoute : RawRequest -> Routes -> Maybe Match
findMatchingRoute req =
    flattenRoutes
        >> findMatchingRoutes req
        >> List.head


flattenRoutes : Routes -> List Route
flattenRoutes =
    let
        go : String -> List Route -> Routes -> List Route
        go base flattened rx =
            case rx of
                Base route ->
                    { route | path = base ++ route.path } :: flattened

                Routes routes_ ->
                    List.concatMap (go base flattened) routes_

                Path path_ routes_ ->
                    List.concatMap (go (base ++ path_) flattened) routes_
    in
    go "" []


findMatchingRoutes : RawRequest -> List Route -> List Match
findMatchingRoutes req =
    List.filterMap
        (\route ->
            if req.request.method == route.method then
                toPathMatch req.request.path route
                    |> Maybe.map (Match route)

            else
                Nothing
        )


toPathMatch : String -> Route -> Maybe Param.Raw
toPathMatch rawPath route =
    let
        routeParts : List String
        routeParts =
            String.split "/" (String.toLower route.path)

        requestParts : List String
        requestParts =
            String.split "/" (String.toLower rawPath)

        getParam : String -> String -> Maybe ( String, String )
        getParam routePart requestPart =
            if String.startsWith "{" routePart && String.endsWith "}" routePart then
                Just
                    ( routePart
                        |> String.dropLeft 1
                        |> String.dropRight 1
                    , requestPart
                    )

            else
                Nothing
    in
    if List.length routeParts == List.length requestParts then
        List.foldl
            (\( routePart, requestPart ) match ->
                case match of
                    Nothing ->
                        Nothing

                    Just params ->
                        case getParam routePart requestPart of
                            Just ( param, value ) ->
                                Just (Dict.insert param value params)

                            Nothing ->
                                if routePart == requestPart then
                                    Just params

                                else
                                    Nothing
            )
            (Just Dict.empty)
            (List.map2 Tuple.pair routeParts requestParts)

    else
        Nothing



-- Program


type alias ProgramOptions =
    { routes : Routes
    , ports :
        { send : Decode.Value -> Cmd Msg
        , receive : (Decode.Value -> Msg) -> Sub Msg
        , onRequest : (RawRequest -> Msg) -> Sub Msg
        , respond : RawResponse -> Cmd Msg
        }
    }


type alias Program flags =
    { init : flags -> ( Model, Cmd Msg )
    , update : Msg -> Model -> ( Model, Cmd Msg )
    , subscriptions : Model -> Sub Msg
    }


worker : ProgramOptions -> Platform.Program flags Model Msg
worker =
    program >> Platform.worker


program : ProgramOptions -> Program flags
program options_ =
    { init = \_ -> init
    , update = update options_
    , subscriptions = subscriptions options_
    }



-- Model


type alias Model =
    { requests : RequestPool Msg
    }


type Msg
    = ServerRequestReceived RawRequest
    | OnServerRequestProgress ( RequestPool Msg, Cmd Msg )
    | ServerResponseGenerated Resolver HandlerResponse



-- Init


init : ( Model, Cmd Msg )
init =
    ( { requests = Task.pool }
    , Cmd.none
    )



-- Update


update : ProgramOptions -> Msg -> Model -> ( Model, Cmd Msg )
update options_ msg model =
    case msg of
        ServerRequestReceived request_ ->
            updateRequests model
                (handleRequest options_
                    { routes = options_.routes
                    , request = request_
                    , onResponse = ServerResponseGenerated request_.resolve
                    , requests = model.requests
                    , send = options_.ports.send
                    }
                )

        OnServerRequestProgress progress ->
            updateRequests model progress

        ServerResponseGenerated resolve response ->
            ( model
            , handleResponse options_
                { resolve = resolve
                , response = response
                }
            )


updateRequests : Model -> ( RequestPool Msg, Cmd Msg ) -> ( Model, Cmd Msg )
updateRequests model ( requests, cmd ) =
    ( { model | requests = requests }, cmd )



-- Subscriptions


subscriptions : ProgramOptions -> Model -> Sub Msg
subscriptions options_ model =
    Sub.batch
        [ options_.ports.onRequest ServerRequestReceived
        , Task.onProgress
            { send = options_.ports.send
            , receive = options_.ports.receive
            , onProgress = OnServerRequestProgress
            }
            model.requests
        ]
