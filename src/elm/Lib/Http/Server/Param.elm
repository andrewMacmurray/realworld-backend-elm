module Lib.Http.Server.Param exposing
    ( Error
    , Params
    , Raw
    , decode
    , errors
    , int
    , map2
    , string
    , succeed
    , with
    )

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Utils.Decode as Decode


type Params a
    = Params (Raw -> Result Error a)


type Error
    = MissingParam String
    | DecodeError String Decode.Error


type alias Raw =
    Dict String String


decode : Params a -> Raw -> Result Error a
decode (Params run) raw =
    run raw


succeed : a -> Params a
succeed a =
    Params (\_ -> Ok a)


map2 : (a -> b -> c) -> Params a -> Params b -> Params c
map2 f a b =
    succeed f
        |> andMap a
        |> andMap b


with : Params a -> Params (a -> b) -> Params b
with =
    andMap


andMap : Params a -> Params (a -> b) -> Params b
andMap (Params a) (Params b) =
    Params (\raw -> Result.map2 (<|) (b raw) (a raw))


string : String -> Params String
string name =
    decodeParam name Decode.string


int : String -> Params Int
int name =
    decodeParam name Decode.intString


decodeParam : String -> Decoder a -> Params a
decodeParam name decoder =
    Params
        (\raw ->
            case Dict.get name raw of
                Nothing ->
                    Err (MissingParam name)

                Just a ->
                    Decode.decodeValue decoder (Encode.string a)
                        |> Result.mapError (DecodeError name)
        )



-- Errors


errors : Error -> List Encode.Value
errors e =
    case e of
        MissingParam name ->
            [ Encode.object
                [ ( name, Encode.string "Missing expected request parameter in route definition" )
                ]
            ]

        DecodeError name error ->
            [ Encode.object
                [ ( name, Encode.string (Decode.errorToString error) )
                ]
            ]
