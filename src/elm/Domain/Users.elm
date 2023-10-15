module Domain.Users exposing
    ( Profile
    , ToCreate
    , ToUpdate
    , User
    , create
    , findByEmail
    , findById
    , follow
    , getProfile
    , unfollow
    , update
    )

import Auth exposing (Auth)
import ConcurrentTask as Task exposing (ConcurrentTask)
import Error exposing (Error)
import Json.Decode as Decode
import Lib.Database.Postgres as Pg
import Utils.Decode as Decode
import Utils.Task as Task



-- User


type alias User =
    { id : Int
    , username : String
    , email : String
    , bio : Maybe String
    , image : Maybe String
    , password : String
    }


type alias Profile =
    { username : String
    , bio : Maybe String
    , image : Maybe String
    , following : Maybe Bool
    }


user : Decode.Decoder User
user =
    Decode.succeed User
        |> Decode.required "id" Decode.int
        |> Decode.required "username" Decode.string
        |> Decode.required "email" Decode.string
        |> Decode.required "bio" (Decode.nullable Decode.string)
        |> Decode.required "image" (Decode.nullable Decode.string)
        |> Decode.required "password" Decode.string


profile : Decode.Decoder Profile
profile =
    Decode.succeed Profile
        |> Decode.required "username" Decode.string
        |> Decode.required "bio" (Decode.nullable Decode.string)
        |> Decode.required "image" (Decode.nullable Decode.string)
        |> Decode.required "following" (Decode.nullable Decode.bool)



-- Pg Decoders


oneUser : Pg.Decoder (Maybe User)
oneUser =
    Pg.expectOne user


oneProfile : Pg.Decoder (Maybe Profile)
oneProfile =
    Pg.expectOne profile


returningOneUser : Pg.Decoder User
returningOneUser =
    Pg.expectExactlyOne user



-- By Id


findById : Int -> ConcurrentTask Error (Maybe User)
findById =
    userById >> query oneUser


userById : Int -> Pg.Statement
userById id =
    Pg.statement """
    SELECT {USER_COLUMNS} from users WHERE users.id = {USER_ID}
    """
        |> Pg.withFragment "USER_COLUMNS" userColumns
        |> Pg.withInt "USER_ID" id



-- By Email


findByEmail : String -> ConcurrentTask Error (Maybe User)
findByEmail =
    userByEmail >> query oneUser


userByEmail : String -> Pg.Statement
userByEmail email =
    Pg.statement """
    SELECT {USER_COLUMNS} from users WHERE users.email = {EMAIL}
    """
        |> Pg.withFragment "USER_COLUMNS" userColumns
        |> Pg.withString "EMAIL" email



-- Create


type alias ToCreate =
    { username : String
    , password : String
    , email : String
    }


create : ToCreate -> ConcurrentTask Error User
create =
    insertUser >> query returningOneUser


insertUser : ToCreate -> Pg.Statement
insertUser toCreate =
    Pg.statement """
    INSERT INTO users (username, password, email)
    VALUES ({USERNAME}, {PASSWORD}, {EMAIL})
    RETURNING {USER_COLUMNS}
    """
        |> Pg.withString "USERNAME" toCreate.username
        |> Pg.withString "PASSWORD" toCreate.password
        |> Pg.withString "EMAIL" toCreate.email
        |> Pg.withFragment "USER_COLUMNS" userColumns



-- Update


type alias ToUpdate =
    { auth : Auth
    , email : Maybe String
    , username : Maybe String
    , password : Maybe String
    , image : Maybe String
    , bio : Maybe String
    }


update : ToUpdate -> ConcurrentTask Error User
update =
    updateUser >> query returningOneUser


updateUser : ToUpdate -> Pg.Statement
updateUser toUpdate =
    Pg.statement """
    UPDATE users SET {UPDATE_FIELDS}
    WHERE users.id = {USER_ID}
    RETURNING {USER_COLUMNS}
    """
        |> Pg.withFragment "UPDATE_FIELDS" (toUpdateFields toUpdate)
        |> Pg.withInt "USER_ID" toUpdate.auth.userId
        |> Pg.withFragment "USER_COLUMNS" userColumns


toUpdateFields : ToUpdate -> Pg.Statement
toUpdateFields toUpdate =
    [ Maybe.map (\e -> Pg.statement "email = {EMAIL}" |> Pg.withString "EMAIL" e) toUpdate.email
    , Maybe.map (\u -> Pg.statement "username = {USERNAME}" |> Pg.withString "USERNAME" u) toUpdate.username
    , Maybe.map (\p -> Pg.statement "password = {PASSWORD}" |> Pg.withString "PASSWORD" p) toUpdate.password
    , Maybe.map (\i -> Pg.statement "image = {IMAGE}" |> Pg.withString "IMAGE" i) toUpdate.image
    , Maybe.map (\b -> Pg.statement "bio = {BIO}" |> Pg.withString "BIO" b) toUpdate.bio
    ]
        |> List.filterMap identity
        |> Pg.joinStatementsWith ", "



-- Follow


type alias ToFollow =
    { auth : Auth
    , username : String
    }


follow : ToFollow -> ConcurrentTask Error ()
follow options =
    followUser options
        |> exec
        |> whenUserExists options


followUser : ToFollow -> Pg.Statement
followUser toFollow =
    Pg.statement """
    INSERT INTO follows (user_id, following)
    VALUES ({USER_ID}, (SELECT id FROM users WHERE username = {USERNAME_TO_FOLLOW}))
    """
        |> Pg.withInt "USER_ID" toFollow.auth.userId
        |> Pg.withString "USERNAME_TO_FOLLOW" toFollow.username



-- Unfollow


type alias ToUnfollow =
    { auth : Auth
    , username : String
    }


unfollow : ToUnfollow -> ConcurrentTask Error ()
unfollow options =
    unfollowUser options
        |> exec
        |> whenUserExists options


unfollowUser : ToUnfollow -> Pg.Statement
unfollowUser toUnfollow =
    Pg.statement """
    DELETE FROM follows
    WHERE
        user_id = {USER_ID} AND
        following = (SELECT id from users WHERE username = {USERNAME_TO_UNFOLLOW})
    """
        |> Pg.withInt "USER_ID" toUnfollow.auth.userId
        |> Pg.withString "USERNAME_TO_UNFOLLOW" toUnfollow.username



-- Get Profile


type alias ProfileToFind =
    { auth : Maybe Auth
    , username : String
    }


getProfile : ProfileToFind -> ConcurrentTask Error (Maybe Profile)
getProfile =
    userProfile >> query oneProfile


userProfile : ProfileToFind -> Pg.Statement
userProfile options =
    options.auth
        |> Maybe.map (profileWithFollowing options.username)
        |> Maybe.withDefault (profileWithoutFollowing options.username)


profileWithoutFollowing : String -> Pg.Statement
profileWithoutFollowing username =
    Pg.statement """
    SELECT
        username,
        bio,
        image,
        null as following
    FROM users
    WHERE users.username = {PROFILE_USERNAME}
    """
        |> Pg.withString "PROFILE_USERNAME" username


profileWithFollowing : String -> Auth -> Pg.Statement
profileWithFollowing username auth =
    Pg.statement """
    with is_following as (
        SELECT 1
        FROM follows
        INNER JOIN users on users.id = follows.following
        WHERE follows.user_id = {USER_ID} and users.username = {PROFILE_USERNAME}
    )

    SELECT
        username,
        bio,
        image,
        (SELECT EXISTS(SELECT * from is_following)) as following
    FROM users
    WHERE users.username = {PROFILE_USERNAME}
    """
        |> Pg.withInt "USER_ID" auth.userId
        |> Pg.withString "PROFILE_USERNAME" username



-- Fragments


userColumns : Pg.Statement
userColumns =
    Pg.statement "id, username, email, bio, image, password"



-- Utils


whenUserExists : { options | username : String } -> ConcurrentTask Error a -> ConcurrentTask Error a
whenUserExists options task =
    Pg.query singleUserId (userExists options.username)
        |> Task.failOnNothing (Pg.NotFound "no user with that username")
        |> Task.mapError Error.pg
        |> Task.andThenDo task


singleUserId : Pg.Decoder (Maybe Int)
singleUserId =
    Pg.expectOne (Decode.field "id" Decode.int)


userExists : String -> Pg.Statement
userExists username =
    Pg.statement "SELECT id FROM users WHERE username = {USERNAME}"
        |> Pg.withString "USERNAME" username



-- Query


query : Pg.Decoder a -> Pg.Statement -> ConcurrentTask Error a
query decode_ =
    Pg.query decode_ >> Task.mapError Error.pg


exec : Pg.Statement -> ConcurrentTask Error ()
exec =
    Pg.exec >> Task.mapError Error.pg
