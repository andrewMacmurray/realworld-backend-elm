module Error exposing
    ( Error(..)
    , auth
    , jwt
    , login
    , notFound
    , password
    , pg
    , server
    )

import Lib.Crypto.Jwt as Jwt
import Lib.Database.Postgres as Pg



-- Errors


type Error
    = Jwt Jwt.Error
    | Auth String
    | Password String
    | Pg Pg.Error
    | Server String
    | NotFound String


jwt : Jwt.Error -> Error
jwt =
    Jwt


auth : String -> Error
auth =
    Auth


password : String -> Error
password =
    Password


login : Error
login =
    Password "invalid email / password combination"


pg : Pg.Error -> Error
pg =
    Pg


server : String -> Error
server =
    Server


notFound : String -> Error
notFound =
    NotFound
