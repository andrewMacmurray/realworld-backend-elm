module Utils.Encode exposing (maybe)

import Json.Encode as Encode


maybe : (a -> Encode.Value) -> Maybe a -> Encode.Value
maybe encode =
    Maybe.map encode >> Maybe.withDefault Encode.null
