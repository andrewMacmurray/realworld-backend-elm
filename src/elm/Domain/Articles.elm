module Domain.Articles exposing
    ( Article
    , Author
    , allTags
    , create
    , delete
    , favorite
    , feed
    , get
    , list
    , unfavorite
    , update
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



-- Article


type alias Article =
    { slug : String
    , title : String
    , description : String
    , body : String
    , createdAt : Time.Posix
    , updatedAt : Time.Posix
    , favorited : Bool
    , favoritesCount : Int
    , tagList : List String
    , author : Author
    }


type alias Author =
    { username : String
    , bio : Maybe String
    , image : Maybe String
    , following : Maybe Bool
    }


type alias Slug =
    { slug : String
    }


article : Decode.Decoder Article
article =
    Decode.succeed Article
        |> Decode.required "slug" Decode.string
        |> Decode.required "title" Decode.string
        |> Decode.required "description" Decode.string
        |> Decode.required "body" Decode.string
        |> Decode.required "created_at" Iso8601.decoder
        |> Decode.required "updated_at" Iso8601.decoder
        |> Decode.required "favorited" Decode.bool
        |> Decode.required "favorites_count" Decode.int
        |> Decode.required "tag_list" (Decode.list Decode.string)
        |> Decode.required "author" author


author : Decode.Decoder Author
author =
    Decode.succeed Author
        |> Decode.required "username" Decode.string
        |> Decode.required "bio" (Decode.maybe Decode.string)
        |> Decode.required "image" (Decode.maybe Decode.string)
        |> Decode.required "following" (Decode.maybe Decode.bool)


slug : Decode.Decoder Slug
slug =
    Decode.succeed Slug
        |> Decode.required "slug" Decode.string


tag : Decode.Decoder String
tag =
    Decode.field "tag" Decode.string



-- Pg Decoders


manyArticles : Pg.Decoder (List Article)
manyArticles =
    Pg.expectMany article


oneArticle : Pg.Decoder (Maybe Article)
oneArticle =
    Pg.expectOne article


returningSlug : Pg.Decoder Slug
returningSlug =
    Pg.expectExactlyOne slug


manyTags : Pg.Decoder (List String)
manyTags =
    Pg.expectMany tag



-- List Articles


type alias ListOptions =
    { auth : Maybe Auth
    , author : Maybe String
    , favorited : Maybe String
    , tag : Maybe String
    , limit : Maybe Int
    , offset : Maybe Int
    }


list : ListOptions -> ConcurrentTask Error (List Article)
list =
    listArticles >> query manyArticles


listArticles : ListOptions -> Pg.Statement
listArticles options =
    selectFromArticles
        { auth = options.auth
        , filter = userFilters options
        , limit = options.limit
        , offset = options.offset
        }


userFilters : ListOptions -> Pg.Statement
userFilters options =
    [ Maybe.map articlesByAuthor options.author
    , Maybe.map articlesFavoritedByUser options.favorited
    , Maybe.map articlesWithTag options.tag
    ]
        |> List.filterMap identity
        |> List.map (\st -> Pg.statement "articles.id IN ({FILTER})" |> Pg.withFragment "FILTER" st)
        |> Pg.whereAll


articlesByAuthor : String -> Pg.Statement
articlesByAuthor author_ =
    Pg.statement """
    SELECT articles.id
    FROM articles
    INNER JOIN users on users.id = articles.user_id
    WHERE users.username = {USERNAME}
    """
        |> Pg.withString "USERNAME" author_


articlesFavoritedByUser : String -> Pg.Statement
articlesFavoritedByUser user_ =
    Pg.statement """
    SELECT favorites.article_id
    FROM favorites
    INNER JOIN users ON users.id = favorites.user_id
    WHERE users.username = {USERNAME}
    """
        |> Pg.withString "USERNAME" user_


articlesWithTag : String -> Pg.Statement
articlesWithTag tag_ =
    Pg.statement """
    SELECT articles_tags.article_id
    FROM articles_tags
    INNER JOIN tags ON tags.id = articles_tags.tag_id
    WHERE tags.tag = {TAG}
    """
        |> Pg.withString "TAG" tag_



-- Feed Articles


type alias FeedOptions =
    { auth : Auth
    , limit : Maybe Int
    , offset : Maybe Int
    }


feed : FeedOptions -> ConcurrentTask Error (List Article)
feed =
    feedArticles >> query manyArticles


feedArticles : FeedOptions -> Pg.Statement
feedArticles options =
    selectFromArticles
        { auth = Just options.auth
        , limit = options.limit
        , offset = options.offset
        , filter = articleIsFromFollowedUser options.auth
        }


articleIsFromFollowedUser : Auth -> Pg.Statement
articleIsFromFollowedUser auth =
    Pg.statement """
    WHERE articles.id IN (
        SELECT articles.id
        FROM articles
        INNER JOIN follows ON follows.following = articles.user_id
        WHERE follows.user_id = {USER_ID}
    )
    """
        |> Pg.withInt "USER_ID" auth.userId



-- Get Article


type alias GetOptions =
    { auth : Maybe Auth
    , slug : String
    }


get : GetOptions -> ConcurrentTask Error (Maybe Article)
get =
    getArticle >> query oneArticle


getArticle : GetOptions -> Pg.Statement
getArticle options =
    selectFromArticles
        { auth = options.auth
        , filter = findBySlug options.slug
        , limit = Just 1
        , offset = Nothing
        }


findBySlug : String -> Pg.Statement
findBySlug slug_ =
    Pg.statement "WHERE articles.slug = {SLUG}"
        |> Pg.withString "SLUG" slug_



-- Create Article


type alias CreateOptions =
    { auth : Auth
    , title : String
    , description : String
    , body : String
    , tagList : List String
    }


create : CreateOptions -> ConcurrentTask Error Slug
create =
    createArticle >> query returningSlug


createArticle : CreateOptions -> Pg.Statement
createArticle options =
    Pg.statement """
    WITH created_article as (
        INSERT INTO articles (title, description, body, user_id)
        VALUES
            ( {TITLE}
            , {DESCRIPTION}
            , {BODY}
            , {USER_ID}
            )
        RETURNING id, slug
    ),

    tags_insert as (
        INSERT INTO tags (tag)
        VALUES {TAGS_VALUES}
        ON CONFLICT (tag) DO UPDATE
            SET tag = EXCLUDED.tag
        RETURNING id
    ),

    articles_tags_insert as (
        INSERT INTO articles_tags (article_id, tag_id)
        SELECT created_article.id, tags_insert.id FROM created_article
        LEFT JOIN tags_insert ON TRUE
        ON CONFLICT DO NOTHING
    )

    SELECT slug from created_article
    """
        |> Pg.withString "TITLE" options.title
        |> Pg.withString "DESCRIPTION" options.description
        |> Pg.withString "BODY" options.body
        |> Pg.withInt "USER_ID" options.auth.userId
        |> Pg.withFragment "TAGS_VALUES"
            (options.tagList
                |> List.map (\tag_ -> Pg.statement "(tagify({TAG}))" |> Pg.withString "TAG" tag_)
                |> Pg.joinStatementsWith ", "
            )



-- Update Article


type alias UpdateOptions =
    { auth : Auth
    , slug : String
    , title : Maybe String
    , description : Maybe String
    , body : Maybe String
    }


update : UpdateOptions -> ConcurrentTask Error Slug
update options =
    whenAuthorized options (updateArticle options |> query returningSlug)


updateArticle : UpdateOptions -> Pg.Statement
updateArticle options =
    case updateArticleFields options of
        [] ->
            Pg.statement "SELECT {SLUG} as slug" |> Pg.withString "SLUG" options.slug

        fields ->
            Pg.statement """
            UPDATE articles SET {UPDATE_FIELDS}
            WHERE
                articles.user_id = {USER_ID} AND
                articles.slug = {SLUG}
            RETURNING
                articles.slug
            """
                |> Pg.withFragment "UPDATE_FIELDS" (Pg.joinStatementsWith ", " fields)
                |> Pg.withInt "USER_ID" options.auth.userId
                |> Pg.withString "SLUG" options.slug


updateArticleFields : UpdateOptions -> List Pg.Statement
updateArticleFields options =
    List.filterMap identity
        [ Maybe.map (\t -> Pg.statement "title = {TITLE}" |> Pg.withString "TITLE" t) options.title
        , Maybe.map (\d -> Pg.statement "description = {DESCRIPTION}" |> Pg.withString "DESCRIPTION" d) options.description
        , Maybe.map (\b -> Pg.statement "body = {BODY}" |> Pg.withString "BODY" b) options.body
        ]



-- Delete Article


type alias DeleteOptions =
    { auth : Auth
    , slug : String
    }


delete : DeleteOptions -> ConcurrentTask Error ()
delete options =
    deleteArticle options
        |> exec
        |> whenAuthorized options


deleteArticle : DeleteOptions -> Pg.Statement
deleteArticle options =
    Pg.statement """
    DELETE FROM articles
    WHERE articles.slug = {SLUG}
    """
        |> Pg.withString "SLUG" options.slug



-- Favorite


type alias FavoriteOptions =
    { userId : Int
    , slug : String
    }


favorite : FavoriteOptions -> ConcurrentTask Error ()
favorite =
    favoriteArticle >> exec


favoriteArticle : FavoriteOptions -> Pg.Statement
favoriteArticle options =
    Pg.statement """
    INSERT INTO favorites (user_id, article_id)
    VALUES
        ( {USER_ID}
        , (SELECT id FROM articles WHERE slug = {SLUG})
        )
    ON CONFLICT DO NOTHING
    """
        |> Pg.withInt "USER_ID" options.userId
        |> Pg.withString "SLUG" options.slug



-- Unfavorite


type alias UnfavoriteOptions =
    { userId : Int
    , slug : String
    }


unfavorite : UnfavoriteOptions -> ConcurrentTask Error ()
unfavorite =
    unfavoriteArticle >> exec


unfavoriteArticle : UnfavoriteOptions -> Pg.Statement
unfavoriteArticle options =
    Pg.statement """
    DELETE FROM favorites
    WHERE
        user_id = {USER_ID} AND
        article_id = (SELECT id FROM articles WHERE slug = {SLUG})
    """
        |> Pg.withInt "USER_ID" options.userId
        |> Pg.withString "SLUG" options.slug



-- Tags


allTags : ConcurrentTask Error (List String)
allTags =
    query manyTags allTags_


allTags_ : Pg.Statement
allTags_ =
    Pg.statement """
    SELECT
        tags.tag,
        count(articles_tags.tag_id)
    FROM tags
    INNER JOIN articles_tags
        ON articles_tags.tag_id = tags.id
    GROUP BY 1
    ORDER BY 2 DESC
    """



-- Base Articles Query


type alias BaseArticles =
    { auth : Maybe Auth
    , filter : Pg.Statement
    , limit : Maybe Int
    , offset : Maybe Int
    }


selectFromArticles : BaseArticles -> Pg.Statement
selectFromArticles options =
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
    ),

    tag_list as (
        SELECT
            articles_tags.article_id,
            json_agg(tags.tag) as json
        FROM tags
        INNER JOIN articles_tags ON articles_tags.tag_id = tags.id
        GROUP BY 1
    )

    SELECT
        articles.id,
        articles.slug,
        articles.title,
        articles.description,
        articles.body,
        articles.created_at,
        articles.updated_at,
        ({FAVORITED_QUERY}) as favorited,
        json_array(tag_list.json) as tag_list,
        authors.json as author,
        (
            SELECT count(*)::int
            FROM favorites
            WHERE favorites.article_id = articles.id
        ) as favorites_count
    FROM articles
    INNER JOIN authors ON authors.id = articles.user_id
    LEFT JOIN tag_list ON tag_list.article_id = articles.id

    {FILTER_CLAUSES}

    ORDER BY
        articles.updated_at DESC,
        articles.created_at DESC
    LIMIT {LIMIT}
    OFFSET {OFFSET}
    """
        |> Pg.withFragment "FOLLOWING_QUERY" (Maybe.maybe isFollowing Pg.null options.auth)
        |> Pg.withFragment "FAVORITED_QUERY" (Maybe.maybe isFavoritedBy Pg.false options.auth)
        |> Pg.withFragment "FILTER_CLAUSES" options.filter
        |> Pg.withInt "LIMIT" (Maybe.withDefault 20 options.limit)
        |> Pg.withInt "OFFSET" (Maybe.withDefault 0 options.offset)


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


isFavoritedBy : Auth -> Pg.Statement
isFavoritedBy auth =
    Pg.statement """
    SELECT EXISTS(
        SELECT 1
        FROM favorites
        WHERE
            favorites.article_id = articles.id AND
            favorites.user_id = {USER_ID}
    )
    """
        |> Pg.withInt "USER_ID" auth.userId



-- Authorization


type alias AuthorizeOptions options =
    { options
        | auth : Auth
        , slug : String
    }


whenAuthorized : AuthorizeOptions options -> ConcurrentTask Error a -> ConcurrentTask Error a
whenAuthorized options task =
    Pg.query singleUserId (isAuthorized options)
        |> Task.failOnNothing (Pg.AccessError "article belongs to another user")
        |> Task.mapError Error.pg
        |> Task.andThenDo task


singleUserId : Pg.Decoder (Maybe Int)
singleUserId =
    Pg.expectOne (Decode.field "id" Decode.int)


isAuthorized : AuthorizeOptions options -> Pg.Statement
isAuthorized options =
    Pg.statement """
    SELECT users.id
    FROM users
    INNER JOIN articles on articles.user_id = users.id
    WHERE
        articles.slug = {SLUG} AND
        articles.user_id = {USER_ID}
    LIMIT 1
    """
        |> Pg.withString "SLUG" options.slug
        |> Pg.withInt "USER_ID" options.auth.userId



-- Query


query : Pg.Decoder a -> Pg.Statement -> ConcurrentTask Error a
query decode_ =
    Pg.query decode_ >> Task.mapError Error.pg


exec : Pg.Statement -> ConcurrentTask Error ()
exec =
    Pg.exec >> Task.mapError Error.pg
