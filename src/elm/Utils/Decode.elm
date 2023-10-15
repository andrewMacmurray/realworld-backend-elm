module Utils.Decode exposing
    ( andMap
    , intString
    , nonEmpty
    , required
    )

import Json.Decode as Decode exposing (Decoder)


required : String -> Decoder a -> Decoder (a -> b) -> Decoder b
required field decoder =
    andMap (Decode.field field decoder)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


nonEmpty : Decoder String
nonEmpty =
    Decode.string
        |> Decode.map String.trim
        |> Decode.andThen
            (\s ->
                if String.isEmpty s then
                    Decode.fail "can't be empty"

                else
                    Decode.succeed s
            )


intString : Decoder Int
intString =
    Decode.string
        |> Decode.andThen
            (\s ->
                case String.toInt s of
                    Just i ->
                        Decode.succeed i

                    Nothing ->
                        Decode.fail "Expecting an INT"
            )
