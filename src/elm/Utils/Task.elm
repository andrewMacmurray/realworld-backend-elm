module Utils.Task exposing (andThenWith, failOnNothing)

import ConcurrentTask as Task exposing (ConcurrentTask)


andThenWith : (b -> a -> c) -> (a -> ConcurrentTask x b) -> ConcurrentTask x a -> ConcurrentTask x c
andThenWith f next =
    Task.andThen (\a -> next a |> Task.map (\b -> f b a))


failOnNothing : x -> ConcurrentTask x (Maybe a) -> ConcurrentTask x a
failOnNothing x =
    Task.andThen
        (\val ->
            case val of
                Just a ->
                    Task.succeed a

                Nothing ->
                    Task.fail x
        )
