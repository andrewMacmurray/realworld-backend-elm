module Routes exposing (all)

import Auth exposing (Auth)
import Auth.Password as Password
import ConcurrentTask as Task exposing (ConcurrentTask)
import Domain.Articles as Articles
import Domain.Comments as Comments
import Domain.Users as Users
import Error exposing (Error)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Lib.Database.Postgres as Pg
import Lib.Http.Server as Server
import Lib.Http.Server.Header as Header exposing (Headers)
import Lib.Http.Server.Param as Param
import Lib.Http.Server.Query as Query
import Lib.Http.Server.Response as Response
import Time
import Utils.Decode as Decode
import Utils.Encode as Encode
import Utils.Task as Task



-- All


all : Server.Routes
all =
    Server.path "/api"
        [ Server.post "/users/login" login
        , Server.post "/users" register
        , Server.get "/user" getCurrentUser
        , Server.put "/user" updateUser
        , Server.get "/profiles/{username}" getProfile
        , Server.post "/profiles/{username}/follow" followUser
        , Server.delete "/profiles/{username}/follow" unfollowUser
        , Server.get "/articles" listArticles
        , Server.get "/articles/feed" feedArticles
        , Server.get "/articles/{slug}" getArticle
        , Server.post "/articles" createArticle
        , Server.put "/articles/{slug}" updateArticle
        , Server.delete "/articles/{slug}" deleteArticle
        , Server.post "/articles/{slug}/comments" addComment
        , Server.get "/articles/{slug}/comments" getComments
        , Server.delete "/articles/{slug}/comments/{id}" deleteComment
        , Server.post "/articles/{slug}/favorite" favoriteArticle
        , Server.delete "/articles/{slug}/favorite" unfavoriteArticle
        , Server.get "/tags" getTags
        ]



-- Login


type alias LoginRequest =
    { body : Login
    }


type alias Login =
    { email : String
    , password : String
    }


type alias LoginResponse =
    { user : User
    }


login : Server.Endpoint LoginRequest Error LoginResponse
login =
    Server.request LoginRequest
        |> Server.withJsonBody
            (Decode.field "user"
                (Decode.succeed Login
                    |> Decode.required "email" Decode.nonEmpty
                    |> Decode.required "password" Decode.nonEmpty
                )
            )
        |> Server.endpoint
            { handler = loginHandler
            , respond = respondWith 200 encodeUser
            }


loginHandler : LoginRequest -> ConcurrentTask Error LoginResponse
loginHandler req =
    Users.findByEmail req.body.email
        |> Task.failOnNothing Error.login
        |> Task.andThen (Password.verify req.body.password)
        |> Task.andThenWith userResponse Auth.generateToken



-- Register


type alias RegisterRequest =
    { body : Registration
    }


type alias Registration =
    { username : String
    , email : String
    , password : String
    }


type alias RegisterResponse =
    { user : User
    }


register : Server.Endpoint RegisterRequest Error RegisterResponse
register =
    Server.request RegisterRequest
        |> Server.withJsonBody
            (Decode.field "user"
                (Decode.map3 Registration
                    (Decode.field "username" Decode.nonEmpty)
                    (Decode.field "email" Decode.nonEmpty)
                    (Decode.field "password" Decode.nonEmpty)
                )
            )
        |> Server.endpoint
            { handler = registerHandler
            , respond = respondWith 201 encodeUser
            }


registerHandler : RegisterRequest -> ConcurrentTask Error RegisterResponse
registerHandler request =
    Password.create request.body.password
        |> Task.andThen
            (\hashed ->
                Users.create
                    { email = request.body.email
                    , username = request.body.username
                    , password = hashed
                    }
            )
        |> Task.andThenWith userResponse Auth.generateToken



-- Get Current User


type alias GetCurrentUserRequest =
    { auth : Auth
    }


type alias GetUserCurrentResponse =
    { user : User
    }


getCurrentUser : Server.Endpoint GetCurrentUserRequest Error GetUserCurrentResponse
getCurrentUser =
    Server.request GetCurrentUserRequest
        |> Server.withHeaders requiredAuth
        |> Server.endpoint
            { handler = getCurrentUserHandler
            , respond = respondWith 200 encodeUser
            }


getCurrentUserHandler : GetCurrentUserRequest -> ConcurrentTask Error GetUserCurrentResponse
getCurrentUserHandler req =
    Users.findById req.auth.userId
        |> serverErrorOnNothing "User not found"
        |> Task.map (userResponse req.auth.token)



-- Update User


type alias UpdateUserRequest =
    { auth : Auth
    , body : UpdateUserBody
    }


type alias UpdateUserBody =
    { email : Maybe String
    , username : Maybe String
    , password : Maybe String
    , image : Maybe String
    , bio : Maybe String
    }


type alias UpdateUserResponse =
    { user : User
    }


updateUser : Server.Endpoint UpdateUserRequest Error UpdateUserResponse
updateUser =
    Server.request UpdateUserRequest
        |> Server.withHeaders requiredAuth
        |> Server.withJsonBody
            (Decode.field "user"
                (Decode.map5 UpdateUserBody
                    (Decode.maybe (Decode.field "email" Decode.nonEmpty))
                    (Decode.maybe (Decode.field "username" Decode.nonEmpty))
                    (Decode.maybe (Decode.field "password" Decode.nonEmpty))
                    (Decode.maybe (Decode.field "image" Decode.nonEmpty))
                    (Decode.maybe (Decode.field "bio" Decode.nonEmpty))
                )
            )
        |> Server.endpoint
            { handler = updateUserHandler
            , respond = respondWith 200 encodeUser
            }


updateUserHandler : UpdateUserRequest -> ConcurrentTask Error UpdateUserResponse
updateUserHandler req =
    Users.update
        { auth = req.auth
        , email = req.body.email
        , username = req.body.username
        , password = req.body.password
        , image = req.body.image
        , bio = req.body.bio
        }
        |> Task.map (userResponse req.auth.token)



-- Get Profile


type alias GetProfileRequest =
    { auth : Maybe Auth
    , username : String
    }


type alias GetProfileResponse =
    { profile : Profile
    }


getProfile : Server.Endpoint GetProfileRequest Error GetProfileResponse
getProfile =
    Server.request GetProfileRequest
        |> Server.withHeaders optionalAuth
        |> Server.withParams (Param.string "username")
        |> Server.endpoint
            { handler = getProfileHandler
            , respond = respondWith 200 encodeProfile
            }


getProfileHandler : GetProfileRequest -> ConcurrentTask Error GetProfileResponse
getProfileHandler req =
    Users.getProfile { auth = req.auth, username = req.username }
        |> notFoundOnNothing "profile"
        |> Task.map profileResponse



-- Follow User


type alias FollowUserRequest =
    { auth : Auth
    , username : String
    }


type alias FollowUserResponse =
    { profile : Profile
    }


followUser : Server.Endpoint FollowUserRequest Error FollowUserResponse
followUser =
    Server.request FollowUserRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams (Param.string "username")
        |> Server.endpoint
            { handler = followUserHandler
            , respond = respondWith 200 encodeProfile
            }


followUserHandler : FollowUserRequest -> ConcurrentTask Error FollowUserResponse
followUserHandler req =
    Users.follow { auth = req.auth, username = req.username }
        |> Task.andThenDo (Users.getProfile { auth = Just req.auth, username = req.username })
        |> serverErrorOnNothing "Missing Profile"
        |> Task.map profileResponse



-- Unfollow User


type alias UnfollowUserRequest =
    { auth : Auth
    , username : String
    }


type alias UnfollowUserResponse =
    { profile : Profile
    }


unfollowUser : Server.Endpoint UnfollowUserRequest Error UnfollowUserResponse
unfollowUser =
    Server.request UnfollowUserRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams (Param.string "username")
        |> Server.endpoint
            { handler = unfollowUserHandler
            , respond = respondWith 200 encodeProfile
            }


unfollowUserHandler : UnfollowUserRequest -> ConcurrentTask Error UnfollowUserResponse
unfollowUserHandler req =
    Users.unfollow { auth = req.auth, username = req.username }
        |> Task.andThenDo (Users.getProfile { auth = Just req.auth, username = req.username })
        |> serverErrorOnNothing "Missing Profile"
        |> Task.map profileResponse



-- List Articles


type alias ListArticlesRequest =
    { auth : Maybe Auth
    , query : ListArticlesQuery
    }


type alias ListArticlesQuery =
    { author : Maybe String
    , favorited : Maybe String
    , tag : Maybe String
    , limit : Maybe Int
    , offset : Maybe Int
    }


type alias ListArticlesResponse =
    { articles : List Article
    }


listArticles : Server.Endpoint ListArticlesRequest Error ListArticlesResponse
listArticles =
    Server.request ListArticlesRequest
        |> Server.withHeaders optionalAuth
        |> Server.withQuery
            (Query.succeed ListArticlesQuery
                |> Query.with (Query.string "author")
                |> Query.with (Query.string "favorited")
                |> Query.with (Query.string "tag")
                |> Query.with (Query.int "limit")
                |> Query.with (Query.int "offset")
            )
        |> Server.endpoint
            { handler = listArticlesHandler
            , respond = respondWith 200 encodeMultipleArticles
            }


listArticlesHandler : ListArticlesRequest -> ConcurrentTask Error ListArticlesResponse
listArticlesHandler req =
    Articles.list
        { auth = req.auth
        , author = req.query.author
        , favorited = req.query.favorited
        , tag = req.query.tag
        , limit = req.query.limit
        , offset = req.query.offset
        }
        |> Task.map articlesResponse



-- Feed Articles


type alias FeedArticlesRequest =
    { auth : Auth
    , query : FeedArticlesQuery
    }


type alias FeedArticlesQuery =
    { limit : Maybe Int
    , offset : Maybe Int
    }


type alias FeedArticlesResponse =
    { articles : List Article
    }


feedArticles : Server.Endpoint FeedArticlesRequest Error FeedArticlesResponse
feedArticles =
    Server.request FeedArticlesRequest
        |> Server.withHeaders requiredAuth
        |> Server.withQuery
            (Query.succeed FeedArticlesQuery
                |> Query.with (Query.int "limit")
                |> Query.with (Query.int "offset")
            )
        |> Server.endpoint
            { handler = feedArticlesHandler
            , respond = respondWith 200 encodeMultipleArticles
            }


feedArticlesHandler : FeedArticlesRequest -> ConcurrentTask Error FeedArticlesResponse
feedArticlesHandler req =
    Articles.feed
        { auth = req.auth
        , limit = req.query.limit
        , offset = req.query.offset
        }
        |> Task.map articlesResponse



-- Get Article


type alias GetArticleRequest =
    { auth : Maybe Auth
    , slug : String
    }


type alias GetArticleResponse =
    { article : Article
    }


getArticle : Server.Endpoint GetArticleRequest Error GetArticleResponse
getArticle =
    Server.request GetArticleRequest
        |> Server.withHeaders optionalAuth
        |> Server.withParams (Param.string "slug")
        |> Server.endpoint
            { handler = getArticleHandler
            , respond = respondWith 200 encodeSingleArticle
            }


getArticleHandler : GetArticleRequest -> ConcurrentTask Error GetArticleResponse
getArticleHandler req =
    Articles.get { auth = req.auth, slug = req.slug }
        |> notFoundOnNothing "article"
        |> Task.map articleResponse



-- Create Article


type alias CreateArticleRequest =
    { auth : Auth
    , body : CreateArticleBody
    }


type alias CreateArticleBody =
    { title : String
    , description : String
    , body : String
    , tagList : List String
    }


type alias CreateArticleResponse =
    { article : Article
    }


createArticle : Server.Endpoint CreateArticleRequest Error CreateArticleResponse
createArticle =
    Server.request CreateArticleRequest
        |> Server.withHeaders requiredAuth
        |> Server.withJsonBody
            (Decode.field "article"
                (Decode.succeed CreateArticleBody
                    |> Decode.required "title" Decode.nonEmpty
                    |> Decode.required "description" Decode.nonEmpty
                    |> Decode.required "body" Decode.nonEmpty
                    |> Decode.required "tagList" (Decode.list Decode.nonEmpty)
                )
            )
        |> Server.endpoint
            { handler = createArticleHandler
            , respond = respondWith 201 encodeSingleArticle
            }


createArticleHandler : CreateArticleRequest -> ConcurrentTask Error CreateArticleResponse
createArticleHandler req =
    Articles.create
        { auth = req.auth
        , title = req.body.title
        , description = req.body.description
        , body = req.body.body
        , tagList = req.body.tagList
        }
        |> Task.andThen (\created -> Articles.get { auth = Just req.auth, slug = created.slug })
        |> serverErrorOnNothing "Missing article"
        |> Task.map articleResponse



-- Update Article


type alias UpdateArticleRequest =
    { auth : Auth
    , slug : String
    , body : UpdateArticleBody
    }


type alias UpdateArticleBody =
    { title : Maybe String
    , description : Maybe String
    , body : Maybe String
    }


type alias UpdateArticleResponse =
    { article : Article
    }


updateArticle : Server.Endpoint UpdateArticleRequest Error UpdateArticleResponse
updateArticle =
    Server.request UpdateArticleRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams (Param.string "slug")
        |> Server.withJsonBody
            (Decode.field "article"
                (Decode.map3 UpdateArticleBody
                    (Decode.maybe (Decode.field "title" Decode.nonEmpty))
                    (Decode.maybe (Decode.field "description" Decode.nonEmpty))
                    (Decode.maybe (Decode.field "body" Decode.nonEmpty))
                )
            )
        |> Server.endpoint
            { handler = updateArticleHandler
            , respond = respondWith 200 encodeSingleArticle
            }


updateArticleHandler : UpdateArticleRequest -> ConcurrentTask Error UpdateArticleResponse
updateArticleHandler req =
    Articles.update
        { auth = req.auth
        , slug = req.slug
        , title = req.body.title
        , description = req.body.description
        , body = req.body.body
        }
        |> Task.andThen (\updated -> Articles.get { auth = Just req.auth, slug = updated.slug })
        |> serverErrorOnNothing "Missing article"
        |> Task.map articleResponse



-- Delete Article


type alias DeleteArticleRequest =
    { auth : Auth
    , slug : String
    }


type alias DeleteArticleResponse =
    ()


deleteArticle : Server.Endpoint DeleteArticleRequest Error DeleteArticleResponse
deleteArticle =
    Server.request DeleteArticleRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams (Param.string "slug")
        |> Server.endpoint
            { handler = deleteArticleHandler
            , respond = respondNoContent
            }


deleteArticleHandler : DeleteArticleRequest -> ConcurrentTask Error DeleteArticleResponse
deleteArticleHandler req =
    Articles.delete
        { auth = req.auth
        , slug = req.slug
        }



-- Add Comment


type alias AddCommentRequest =
    { auth : Auth
    , body : AddCommentBody
    , slug : String
    }


type alias AddCommentBody =
    { body : String
    }


type alias AddCommentResponse =
    { comment : Comment
    }


addComment : Server.Endpoint AddCommentRequest Error AddCommentResponse
addComment =
    Server.request AddCommentRequest
        |> Server.withHeaders requiredAuth
        |> Server.withJsonBody
            (Decode.field "comment"
                (Decode.succeed AddCommentBody
                    |> Decode.required "body" Decode.nonEmpty
                )
            )
        |> Server.withParams (Param.string "slug")
        |> Server.endpoint
            { handler = addCommentHandler
            , respond = respondWith 201 encodeSingleComment
            }


addCommentHandler : AddCommentRequest -> ConcurrentTask Error AddCommentResponse
addCommentHandler req =
    Comments.add
        { auth = req.auth
        , slug = req.slug
        , body = req.body.body
        }
        |> Task.map commentResponse



-- Get Comments


type alias GetCommentsRequest =
    { auth : Maybe Auth
    , slug : String
    }


type alias GetCommentsResponse =
    { comments : List Comment
    }


getComments : Server.Endpoint GetCommentsRequest Error GetCommentsResponse
getComments =
    Server.request GetCommentsRequest
        |> Server.withHeaders optionalAuth
        |> Server.withParams (Param.string "slug")
        |> Server.endpoint
            { handler = getCommentsHandler
            , respond = respondWith 200 encodeMultipleComments
            }


getCommentsHandler : GetCommentsRequest -> ConcurrentTask Error GetCommentsResponse
getCommentsHandler req =
    Comments.forArticle
        { auth = req.auth
        , slug = req.slug
        }
        |> Task.map commentsResponse



-- Delete Comment


type alias DeleteCommentRequest =
    { auth : Auth
    , params : DeleteCommentParams
    }


type alias DeleteCommentParams =
    { slug : String
    , commentId : Int
    }


type alias DeleteCommentResponse =
    ()


deleteComment : Server.Endpoint DeleteCommentRequest Error DeleteCommentResponse
deleteComment =
    Server.request DeleteCommentRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams
            (Param.succeed DeleteCommentParams
                |> Param.with (Param.string "slug")
                |> Param.with (Param.int "id")
            )
        |> Server.endpoint
            { handler = deleteCommentHandler
            , respond = respondNoContent
            }


deleteCommentHandler : DeleteCommentRequest -> ConcurrentTask Error DeleteCommentResponse
deleteCommentHandler req =
    Comments.delete
        { auth = req.auth
        , id = req.params.commentId
        }



-- Favorite Article


type alias FavoriteArticleRequest =
    { auth : Auth
    , slug : String
    }


type alias FavoriteArticleResponse =
    { article : Article
    }


favoriteArticle : Server.Endpoint FavoriteArticleRequest Error FavoriteArticleResponse
favoriteArticle =
    Server.request FavoriteArticleRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams (Param.string "slug")
        |> Server.endpoint
            { handler = favoriteArticleHandler
            , respond = respondWith 200 encodeSingleArticle
            }


favoriteArticleHandler : FavoriteArticleRequest -> ConcurrentTask Error FavoriteArticleResponse
favoriteArticleHandler req =
    Articles.favorite
        { userId = req.auth.userId
        , slug = req.slug
        }
        |> Task.andThenDo (Articles.get { auth = Just req.auth, slug = req.slug })
        |> serverErrorOnNothing "Missing article"
        |> Task.map articleResponse



-- Unfavorite Article


type alias UnfavoriteArticleRequest =
    { auth : Auth
    , slug : String
    }


type alias UnfavoriteArticleResponse =
    { article : Article
    }


unfavoriteArticle : Server.Endpoint UnfavoriteArticleRequest Error UnfavoriteArticleResponse
unfavoriteArticle =
    Server.request UnfavoriteArticleRequest
        |> Server.withHeaders requiredAuth
        |> Server.withParams (Param.string "slug")
        |> Server.endpoint
            { handler = unfavoriteArticleHandler
            , respond = respondWith 200 encodeSingleArticle
            }


unfavoriteArticleHandler : UnfavoriteArticleRequest -> ConcurrentTask Error FavoriteArticleResponse
unfavoriteArticleHandler req =
    Articles.unfavorite
        { userId = req.auth.userId
        , slug = req.slug
        }
        |> Task.andThenDo (Articles.get { auth = Just req.auth, slug = req.slug })
        |> serverErrorOnNothing "Missing article"
        |> Task.map articleResponse



-- Tags


type alias GetTagsRequest =
    ()


type alias GetTagsResponse =
    { tags : List String
    }


getTags : Server.Endpoint GetTagsRequest Error GetTagsResponse
getTags =
    Server.request ()
        |> Server.endpoint
            { handler = getTagsHandler
            , respond = respondWith 200 encodeTags
            }


getTagsHandler : GetTagsRequest -> ConcurrentTask Error GetTagsResponse
getTagsHandler _ =
    Articles.allTags
        |> Task.map tagsResponse



-- Auth


requiredAuth : Headers Error Auth
requiredAuth =
    Header.string "Authorization"
        |> Header.andThen toAuthHeader


optionalAuth : Headers Error (Maybe Auth)
optionalAuth =
    Header.optional requiredAuth


toAuthHeader : String -> ConcurrentTask Error Auth
toAuthHeader header =
    if String.startsWith "Token " header then
        Auth.verifyToken (String.dropLeft 6 header)

    else
        Task.fail (Error.auth "Invalid Auth Header")



-- Helpers


serverErrorOnNothing : String -> ConcurrentTask Error (Maybe a) -> ConcurrentTask Error a
serverErrorOnNothing message =
    Task.failOnNothing (Error.server message)


notFoundOnNothing : String -> ConcurrentTask Error (Maybe a) -> ConcurrentTask Error a
notFoundOnNothing value =
    Task.failOnNothing (Error.notFound value)



-- User


type alias User =
    { email : String
    , token : String
    , username : String
    , bio : Maybe String
    , image : Maybe String
    }


userResponse : String -> Users.User -> { user : User }
userResponse token user =
    { user =
        { email = user.email
        , username = user.username
        , image = user.image
        , bio = user.bio
        , token = token
        }
    }


encodeUser : { response | user : User } -> Encode.Value
encodeUser { user } =
    Encode.object
        [ ( "user"
          , Encode.object
                [ ( "email", Encode.string user.email )
                , ( "token", Encode.string user.token )
                , ( "username", Encode.string user.username )
                , ( "bio", Encode.maybe Encode.string user.bio )
                , ( "image", Encode.maybe Encode.string user.image )
                ]
          )
        ]



-- Profile


type alias Profile =
    { username : String
    , bio : Maybe String
    , image : Maybe String
    , following : Maybe Bool
    }


profileResponse : Users.Profile -> { profile : Profile }
profileResponse profile =
    { profile = profile }


encodeProfile : { response | profile : Profile } -> Encode.Value
encodeProfile res =
    Encode.object
        [ ( "profile"
          , Encode.object
                [ ( "username", Encode.string res.profile.username )
                , ( "bio", Encode.maybe Encode.string res.profile.bio )
                , ( "image", Encode.maybe Encode.string res.profile.image )
                , ( "following", Encode.maybe Encode.bool res.profile.following )
                ]
          )
        ]



-- Article


type alias Article =
    { slug : String
    , title : String
    , description : String
    , body : String
    , tagList : List String
    , createdAt : Time.Posix
    , updatedAt : Time.Posix
    , favorited : Bool
    , favoritesCount : Int
    , author : Author
    }


type alias Author =
    { username : String
    , bio : Maybe String
    , image : Maybe String
    , following : Maybe Bool
    }


articlesResponse : List Articles.Article -> { articles : List Article }
articlesResponse articles =
    { articles = articles }


articleResponse : Articles.Article -> { article : Article }
articleResponse article =
    { article = article }


encodeMultipleArticles : { response | articles : List Article } -> Encode.Value
encodeMultipleArticles res =
    Encode.object
        [ ( "articles", Encode.list encodeArticle res.articles )
        , ( "articlesCount", Encode.int (List.length res.articles) )
        ]


encodeSingleArticle : { response | article : Article } -> Encode.Value
encodeSingleArticle res =
    Encode.object
        [ ( "article", encodeArticle res.article )
        ]


encodeArticle : Article -> Encode.Value
encodeArticle a =
    Encode.object
        [ ( "slug", Encode.string a.slug )
        , ( "title", Encode.string a.title )
        , ( "description", Encode.string a.description )
        , ( "body", Encode.string a.body )
        , ( "tagList", Encode.list Encode.string a.tagList )
        , ( "createdAt", Iso8601.encode a.createdAt )
        , ( "updatedAt", Iso8601.encode a.updatedAt )
        , ( "favorited", Encode.bool a.favorited )
        , ( "favoritesCount", Encode.int a.favoritesCount )
        , ( "author", encodeAuthor a.author )
        ]


encodeAuthor : Author -> Encode.Value
encodeAuthor a =
    Encode.object
        [ ( "username", Encode.string a.username )
        , ( "bio", Encode.maybe Encode.string a.bio )
        , ( "image", Encode.maybe Encode.string a.image )
        , ( "following", Encode.maybe Encode.bool a.following )
        ]



-- Comment


type alias Comment =
    { id : Int
    , createdAt : Time.Posix
    , updatedAt : Time.Posix
    , body : String
    , author : Author
    }


commentsResponse : List Comments.Comment -> { comments : List Comment }
commentsResponse comments =
    { comments = comments }


commentResponse : Comments.Comment -> { comment : Comment }
commentResponse comment =
    { comment = comment }


encodeMultipleComments : { response | comments : List Comment } -> Encode.Value
encodeMultipleComments res =
    Encode.object [ ( "comments", Encode.list encodeComment res.comments ) ]


encodeSingleComment : { response | comment : Comment } -> Encode.Value
encodeSingleComment res =
    Encode.object [ ( "comment", encodeComment res.comment ) ]


encodeComment : Comment -> Encode.Value
encodeComment c =
    Encode.object
        [ ( "id", Encode.int c.id )
        , ( "createdAt", Iso8601.encode c.createdAt )
        , ( "updatedAt", Iso8601.encode c.updatedAt )
        , ( "body", Encode.string c.body )
        , ( "author", encodeAuthor c.author )
        ]



-- Tags


tagsResponse : List String -> { tags : List String }
tagsResponse tags =
    { tags = tags }


encodeTags : { response | tags : List String } -> Encode.Value
encodeTags res =
    Encode.object [ ( "tags", Encode.list Encode.string res.tags ) ]



-- Respond


respondNoContent : Result (Server.Error Error) a -> Server.Response
respondNoContent =
    respondWith 204 (always Encode.null)


respondWith : Int -> (a -> Encode.Value) -> Result (Server.Error Error) a -> Server.Response
respondWith status toBody res =
    case res of
        Ok a ->
            Response.send status (toBody a)

        Err e ->
            case e of
                Server.RequestError re_ ->
                    case re_ of
                        Server.BodyError e_ ->
                            validationErrors (encodeBodyErrors e_)

                        Server.HeadersError e_ ->
                            Header.handleError validationErrors handleError e_

                        Server.ParamsError e_ ->
                            validationErrors (Param.encodeError e_)

                Server.HandlerError e_ ->
                    handleError e_


encodeBodyErrors : Decode.Error -> Encode.Value
encodeBodyErrors err =
    Encode.object [ ( "body", Encode.list identity (bodyErrors err []) ) ]


bodyErrors : Decode.Error -> List Encode.Value -> List Encode.Value
bodyErrors err xs =
    case err of
        Decode.Field field (Decode.Failure reason _) ->
            Encode.string (field ++ " " ++ reason) :: xs

        Decode.Field _ e ->
            bodyErrors e xs

        Decode.Index i (Decode.Failure reason _) ->
            Encode.string ("Problem at index " ++ String.fromInt i ++ " " ++ reason) :: xs

        Decode.Index _ e ->
            bodyErrors e xs

        Decode.OneOf errs ->
            List.concatMap (\x -> bodyErrors x xs) errs

        Decode.Failure reason _ ->
            Encode.string reason :: xs


handleError : Error -> Server.Response
handleError e =
    case e of
        Error.NotFound item ->
            error 404 item "not found"

        Error.Jwt _ ->
            error 401 "auth" "unauthorized"

        Error.Auth _ ->
            error 401 "auth" "unauthorized"

        Error.Password reason ->
            error 422 "password" reason

        Error.Pg (Pg.NotFound e_) ->
            error 404 "db" e_

        Error.Pg (Pg.AccessError e_) ->
            error 403 "db" ("forbidden: " ++ e_)

        Error.Pg e_ ->
            error 400 "db" (Pg.errorToString e_)

        Error.Server _ ->
            error 500 "error" "internal server error"


validationErrors : Encode.Value -> Response.Response
validationErrors =
    errors 422


error : Int -> String -> String -> Server.Response
error status reason message =
    errors status (Encode.object [ ( reason, Encode.list Encode.string [ message ] ) ])


errors : Int -> Encode.Value -> Response.Response
errors status errs =
    Response.send status (Encode.object [ ( "errors", errs ) ])
