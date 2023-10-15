module Lib.Http.Server.Query exposing
    ( Query
    , Raw
    , decode
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


type Query a
    = Query (Raw -> a)


type alias Raw =
    Dict String String


decode : Query a -> Raw -> a
decode (Query run) raw =
    run raw


succeed : a -> Query a
succeed a =
    Query (\_ -> a)


map : (a -> b) -> Query a -> Query b
map f (Query a) =
    Query (\raw -> f (a raw))


map2 : (a -> b -> c) -> Query a -> Query b -> Query c
map2 f a b =
    map f a |> andMap b


with : Query a -> Query (a -> b) -> Query b
with =
    andMap


andMap : Query a -> Query (a -> b) -> Query b
andMap (Query a) (Query b) =
    Query (\raw -> b raw (a raw))


string : String -> Query (Maybe String)
string name =
    decodeParam name Decode.string


int : String -> Query (Maybe Int)
int name =
    decodeParam name Decode.intString


decodeParam : String -> Decoder a -> Query (Maybe a)
decodeParam name decoder =
    Query
        (\raw ->
            case Dict.get name raw of
                Nothing ->
                    Nothing

                Just a ->
                    Decode.decodeValue decoder (Encode.string a)
                        |> Result.toMaybe
        )
