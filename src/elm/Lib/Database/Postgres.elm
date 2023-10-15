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
import Json.Decode as Decode
import Json.Encode as Encode



-- Statement


type Statement
    = Statement String


statement : String -> Statement
statement =
    Statement


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
withFragment name =
    param name << unwrap_


withInt : String -> Int -> Statement -> Statement
withInt name =
    param name << String.fromInt


withString : String -> String -> Statement -> Statement
withString name =
    param name << escape


whereAll : List Statement -> Statement
whereAll statements =
    if List.isEmpty statements then
        empty

    else
        statement "WHERE {CLAUSES}"
            |> withFragment "CLAUSES" (joinStatementsWith " AND " statements)


escape : String -> String
escape s =
    "E" ++ quote (escapeCharacters s)


param : String -> String -> Statement -> Statement
param name value =
    unwrap_
        >> String.replace ("{" ++ name ++ "}") value
        >> Statement


joinStatementsWith : String -> List Statement -> Statement
joinStatementsWith sep =
    List.map unwrap_
        >> String.join sep
        >> Statement



-- Internal


unwrap_ : Statement -> String
unwrap_ (Statement s) =
    s


quote : String -> String
quote s =
    "'" ++ s ++ "'"


escapeCharacters : String -> String
escapeCharacters =
    String.replace "'" "\\'"



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
        , args = Encode.object [ ( "query", encodeStatement statement_ ) ]
        }
        |> Task.andThen (decodeQueryResults decoder >> Task.fromResult)


encodeStatement : Statement -> Encode.Value
encodeStatement =
    unwrap_ >> Encode.string


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
