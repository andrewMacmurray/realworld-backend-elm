module Auth.Password exposing
    ( create
    , verify
    )

import ConcurrentTask as Task exposing (ConcurrentTask)
import Domain.Users exposing (User)
import Error exposing (Error)
import Lib.Crypto.BCrypt as BCrypt
import Regex exposing (Regex)



-- Create New Password


create : String -> ConcurrentTask Error String
create password =
    checkNew password
        |> Result.mapError Error.password
        |> Task.fromResult
        |> Task.andThenDo
            (BCrypt.hash
                { password = password
                , saltRounds = 10
                }
            )



-- Password Criteria


type alias Criteria =
    { regex : String
    , error : String
    }


checkNew : String -> Result String String
checkNew password =
    let
        errors : List Criteria
        errors =
            List.filter (passesCriteria password >> not) [ above10, upper, lower, numbers ]
    in
    if List.isEmpty errors then
        Ok password

    else
        Err (formatErrors errors)


upper : Criteria
upper =
    { regex = "(?=.*[A-Z])"
    , error = "contain uppercase"
    }


lower : Criteria
lower =
    { regex = "(?=.*[a-z])"
    , error = "contain lower"
    }


above10 : Criteria
above10 =
    { regex = "(?=.{10,})"
    , error = "at least 10 characters"
    }


numbers : Criteria
numbers =
    { regex = "(?=.*[0-9])"
    , error = "contain numbers"
    }


passesCriteria : String -> Criteria -> Bool
passesCriteria password criteria =
    Regex.contains
        (criteria.regex
            |> Regex.fromString
            |> Maybe.withDefault Regex.never
        )
        password


formatErrors : List Criteria -> String
formatErrors criteria =
    "Password does not meet criteria: " ++ String.join ", " (List.map .error criteria)



-- Verify Hashed Password


verify : String -> User -> ConcurrentTask Error User
verify plaintext user =
    BCrypt.compare
        { plaintext = plaintext
        , hashed = user.password
        }
        |> Task.andThen
            (\isValid ->
                if isValid then
                    Task.succeed user

                else
                    Task.fail Error.login
            )
