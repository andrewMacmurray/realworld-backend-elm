module Domain.Comments exposing
    ( Comment
    , add
    , delete
    , forArticle
    )

import Auth exposing (Auth)
import ConcurrentTask as Task exposing (ConcurrentTask)
import Error exposing (Error)
import Iso8601
import Json.Decode as Decode
import Lib.Database.Postgres as Pg
import Time
import Utils.Decode as Decode
import Utils.Maybe as Maybe
import Utils.Task as Task



-- Comments


type alias Comment =
    { id : Int
    , createdAt : Time.Posix
    , updatedAt : Time.Posix
    , body : String
    , author : Author
    }


type alias Author =
    { username : String
    , bio : Maybe String
    , image : Maybe String
    , following : Maybe Bool
    }


comment : Decode.Decoder Comment
comment =
    Decode.succeed Comment
        |> Decode.required "id" Decode.int
        |> Decode.required "created_at" Iso8601.decoder
        |> Decode.required "updated_at" Iso8601.decoder
        |> Decode.required "body" Decode.string
        |> Decode.required "author" author


author : Decode.Decoder Author
author =
    Decode.succeed Author
        |> Decode.required "username" Decode.string
        |> Decode.required "bio" (Decode.maybe Decode.string)
        |> Decode.required "image" (Decode.maybe Decode.string)
        |> Decode.required "following" (Decode.maybe Decode.bool)



-- Pg Decoders


oneComment : Pg.Decoder (Maybe Comment)
oneComment =
    Pg.expectOne comment


manyComments : Pg.Decoder (List Comment)
manyComments =
    Pg.expectMany comment


returningId : Pg.Decoder Int
returningId =
    Pg.expectExactlyOne (Decode.field "id" Decode.int)



-- Add Comment


type alias AddCommentOptions =
    { auth : Auth
    , slug : String
    , body : String
    }


add : AddCommentOptions -> ConcurrentTask Error Comment
add options =
    addComment_ options
        |> query returningId
        |> Task.andThen (\id -> find { id = id, auth = options.auth })
        |> Task.failOnNothing (Error.server "created comment does not exist")


addComment_ : AddCommentOptions -> Pg.Statement
addComment_ options =
    Pg.statement """
    INSERT INTO comments (article_id, user_id, body)
    VALUES
        ( (SELECT id FROM articles WHERE articles.slug = {SLUG})
        , {USER_ID}
        , {BODY}
        )
    RETURNING id
    """
        |> Pg.withString "SLUG" options.slug
        |> Pg.withInt "USER_ID" options.auth.userId
        |> Pg.withString "BODY" options.body


type alias FindCommentOptions =
    { auth : Auth
    , id : Int
    }


find : FindCommentOptions -> ConcurrentTask Error (Maybe Comment)
find =
    findComment >> query oneComment


findComment : FindCommentOptions -> Pg.Statement
findComment options =
    Pg.statement """
    WITH comments as ({COMMENTS})
    SELECT * FROM comments
    WHERE comments.id = {COMMENT_ID}
    """
        |> Pg.withInt "COMMENT_ID" options.id
        |> Pg.withFragment "COMMENTS"
            (baseComments
                { auth = Just options.auth
                }
            )



-- Comments


type alias CommentsOptions =
    { auth : Maybe Auth
    , slug : String
    }


forArticle : CommentsOptions -> ConcurrentTask Error (List Comment)
forArticle =
    commentsForArticle >> query manyComments


commentsForArticle : CommentsOptions -> Pg.Statement
commentsForArticle options =
    Pg.statement """
    WITH comments AS ({COMMENTS})
    SELECT * FROM comments
    WHERE comments.article_slug = {SLUG}
    """
        |> Pg.withString "SLUG" options.slug
        |> Pg.withFragment "COMMENTS"
            (baseComments
                { auth = options.auth
                }
            )



-- Delete Comment


type alias DeleteCommentOptions =
    { auth : Auth
    , id : Int
    }


delete : DeleteCommentOptions -> ConcurrentTask Error ()
delete options =
    exec (deleteComment options)


deleteComment : DeleteCommentOptions -> Pg.Statement
deleteComment options =
    Pg.statement """
    DELETE FROM comments
    WHERE
        comments.id = {COMMENT_ID} AND
        comments.user_id = {USER_ID}
    """
        |> Pg.withInt "COMMENT_ID" options.id
        |> Pg.withInt "USER_ID" options.auth.userId



-- Base Comments


type alias BaseComments =
    { auth : Maybe Auth
    }


baseComments : BaseComments -> Pg.Statement
baseComments options =
    Pg.statement """
    WITH authors as (
        SELECT
            users.id,
            json_build_object(
                'username', users.username,
                'bio', users.bio,
                'image', users.image,
                'following', ({FOLLOWING_QUERY})
            ) as json
        FROM users
    )

    SELECT
        comments.id,
        articles.slug as article_slug,
        comments.created_at,
        comments.updated_at,
        comments.body,
        authors.json as author
    FROM comments
    INNER JOIN authors ON authors.id = comments.user_id
    INNER JOIN articles ON articles.id = comments.article_id

    ORDER BY
        comments.updated_at DESC,
        comments.created_at DESC
    """
        |> Pg.withFragment "FOLLOWING_QUERY" (Maybe.maybe isFollowing Pg.false options.auth)


isFollowing : Auth -> Pg.Statement
isFollowing auth =
    Pg.statement """
    SELECT EXISTS(
        SELECT 1
        FROM follows
        WHERE
            follows.following = users.id AND
            follows.user_id = {USER_ID}
    )
    """
        |> Pg.withInt "USER_ID" auth.userId



-- Query


query : Pg.Decoder a -> Pg.Statement -> ConcurrentTask Error a
query decode_ =
    Pg.query decode_ >> Task.mapError Error.pg


exec : Pg.Statement -> ConcurrentTask Error ()
exec =
    Pg.exec >> Task.mapError Error.pg
