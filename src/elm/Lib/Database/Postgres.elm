module Lib.Database.Postgres exposing
    ( Decoder
    , Error(..)
    , Statement
    , empty
    , errorToString
    , exec
    , expectExactlyOne
    , expectMany
    , expectOne
    , false
    , joinStatementsWith
    , null
    , query
    , statement
    , whereAll
    , withFragment
    , withInt
    , withString
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Dict exposing (Dict)
import Dict.Extra
import Json.Decode as Decode
import Json.Encode as Encode



-- Statement


type Statement
    = Statement String (Dict String Param)


type Param
    = StringParam String
    | IntParam Int


statement : String -> Statement
statement s =
    Statement s Dict.empty


empty : Statement
empty =
    statement ""


null : Statement
null =
    statement "NULL"


false : Statement
false =
    statement "FALSE"


withFragment : String -> Statement -> Statement -> Statement
withFragment name (Statement s1 p1) (Statement s2 p2) =
    Statement
        (String.replace ("{" ++ name ++ "}") s1 s2)
        (Dict.union p1 p2)


withInt : String -> Int -> Statement -> Statement
withInt name =
    withParam name << IntParam


withString : String -> String -> Statement -> Statement
withString name =
    withParam name << StringParam


whereAll : List Statement -> Statement
whereAll statements =
    if List.isEmpty statements then
        empty

    else
        statement "WHERE {CLAUSES}"
            |> withFragment "CLAUSES" (joinStatementsWith " AND " statements)


joinStatementsWith : String -> List Statement -> Statement
joinStatementsWith sep statements =
    let
        scopeParams : Int -> Statement -> Statement
        scopeParams i (Statement s px) =
            let
                suffix : String -> String
                suffix k =
                    k ++ "_" ++ String.fromInt i

                renamedSQL : String
                renamedSQL =
                    Dict.keys px
                        |> List.foldl (\k acc -> String.replace ("{" ++ k ++ "}") ("{" ++ suffix k ++ "}") acc) s

                renamedParams : Dict String Param
                renamedParams =
                    Dict.Extra.mapKeys suffix px
            in
            Statement renamedSQL renamedParams

        indexed : List Statement
        indexed =
            List.indexedMap scopeParams statements
    in
    Statement
        (List.map (\(Statement s _) -> s) indexed |> String.join sep)
        (List.foldl (\(Statement _ p) acc -> Dict.union p acc) Dict.empty indexed)


withParam : String -> Param -> Statement -> Statement
withParam name p (Statement s px) =
    Statement s (Dict.insert name p px)



-- Encode


encodeStatement : Statement -> Encode.Value
encodeStatement (Statement s px) =
    let
        encodeParam : Param -> Encode.Value
        encodeParam p =
            case p of
                StringParam str ->
                    Encode.string str

                IntParam i ->
                    Encode.int i

        params : List ( String, Param )
        params =
            Dict.toList px

        encodedQuery : Encode.Value
        encodedQuery =
            List.indexedMap (\i ( name, _ ) -> ( i + 1, name )) params
                |> List.foldl (\( i, name ) acc -> String.replace ("{" ++ name ++ "}") ("$" ++ String.fromInt i) acc) s
                |> Encode.string

        encodedParams : Encode.Value
        encodedParams =
            Encode.list (encodeParam << Tuple.second) params
    in
    Encode.object
        [ ( "text", encodedQuery )
        , ( "values", encodedParams )
        ]



-- Decode


type Decoder a
    = Decoder (Decode.Decoder a)


expectMany : Decode.Decoder a -> Decoder (List a)
expectMany decoder =
    Decoder (Decode.list decoder)


expectOne : Decode.Decoder a -> Decoder (Maybe a)
expectOne decoder =
    Decode.list Decode.value
        |> Decode.andThen
            (\xs ->
                if List.isEmpty xs then
                    Decode.succeed Nothing

                else
                    Decode.index 0 decoder
                        |> Decode.map Just
            )
        |> Decoder


expectExactlyOne : Decode.Decoder a -> Decoder a
expectExactlyOne decoder =
    Decode.list Decode.value
        |> Decode.andThen
            (\xs ->
                case xs of
                    [] ->
                        Decode.fail "Got no results back"

                    [ _ ] ->
                        Decode.index 0 decoder

                    _ ->
                        Decode.fail "Got more than 1 result back"
            )
        |> Decoder


succeed : a -> Decoder a
succeed a =
    Decoder (Decode.succeed a)



-- Query


type Error
    = AccessError String
    | NotFound String
    | QueryError String
    | QueryDecodeError Decode.Error


type alias Results =
    { rows : Decode.Value
    }


exec : Statement -> ConcurrentTask Error ()
exec =
    query (succeed ())


query : Decoder a -> Statement -> ConcurrentTask Error a
query decoder statement_ =
    Task.define
        { function = "db:query"
        , expect = Task.expectJson decodeResults
        , errors = Task.expectThrows QueryError
        , args = encodeStatement statement_
        }
        |> Task.andThen (decodeQueryResults decoder >> Task.fromResult)


decodeQueryResults : Decoder a -> Results -> Result Error a
decodeQueryResults (Decoder decoder) results =
    Decode.decodeValue decoder results.rows
        |> Result.mapError QueryDecodeError


decodeResults : Decode.Decoder Results
decodeResults =
    Decode.map Results
        (Decode.field "rows" Decode.value)


errorToString : Error -> String
errorToString e =
    case e of
        AccessError e_ ->
            "DB_ACCESS_ERROR: " ++ e_

        NotFound e_ ->
            "DB_NOT_FOUND: " ++ e_

        QueryError e_ ->
            "DB_ERROR: " ++ e_

        QueryDecodeError e_ ->
            "DB_DECODE_ERROR: " ++ Decode.errorToString e_
