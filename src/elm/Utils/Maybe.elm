module Utils.Maybe exposing (maybe)


maybe : (a -> b) -> b -> Maybe a -> b
maybe f default =
    Maybe.map f >> Maybe.withDefault default
