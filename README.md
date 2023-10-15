# ![RealWorld Backend in Elm](https://cloud.githubusercontent.com/assets/556934/25448178/3e7dc5c0-2a7d-11e7-8069-06da5169dae6.png)

> [Elm](http://elm-lang.org) codebase containing real world examples (CRUD, auth, advanced patterns, etc) that adheres to the [RealWorld](https://github.com/gothinkster/realworld-example-apps) spec and API.

### [Demo](https://realworld-backend-elm.vercel.app/)&nbsp;&nbsp;&nbsp;&nbsp;[RealWorld](https://github.com/gothinkster/realworld)

This codebase was created to demonstrate a fully fledged fullstack application built with [Elm](http://elm-lang.org) including CRUD operations, authentication, routing, pagination, and more.

For more information on how this works with other frontends/backends, head over to the [RealWorld](https://github.com/gothinkster/realworld) repo.

## What?

We have a few frontend Elm implementations of the [RealWorld App Spec](https://main--realworld-docs.netlify.app/docs/intro), let's make a **backend** one!

See a [full stack Elm version](https://realworld-backend-elm.vercel.app/) here! (It's [rtfeldman/elm-spa-example](https://github.com/rtfeldman/elm-spa-example) connected up to this api as the backend).

## How it works

### The Elm API

- The api is an Elm worker running on NodeJS, and uses [elm-concurrent-task](https://package.elm-lang.org/packages/andrewMacmurray/elm-concurrent-task/latest/) to interop with a few JS libraries and a Postgres database.
- All of the business logic can be found in [Routes.elm](https://github.com/andrewMacmurray/realworld-backend-elm/blob/main/src/elm/Routes.elm) and in [Domain](https://github.com/andrewMacmurray/realworld-backend-elm/tree/main/src/elm/Domain) modules.
- Each endpoint handler is a `ConcurrentTask` which handles a thin layer of interop with some JS libraries (`bcryptjs`, `jsonwebtoken` and `node-pg`).
- All of the code in [Lib](./src/elm/Lib/) is pretty generic and could more or less be extracted out into separate packages as is (For [JWT](https://github.com/andrewMacmurray/realworld-backend-elm/blob/main/src/elm/Lib/Crypto/Jwt.elm), [Bcrypt](https://github.com/andrewMacmurray/realworld-backend-elm/blob/main/src/elm/Lib/Crypto/BCrypt.elm), [Postgres](https://github.com/andrewMacmurray/realworld-backend-elm/blob/main/src/elm/Lib/Database/Postgres.elm) and an [Http Server](https://github.com/andrewMacmurray/realworld-backend-elm/blob/main/src/elm/Lib/Http/Server.elm)).

### Deployment

- The api is deployed as a single [vercel serverless function](https://vercel.com/docs/functions/serverless-functions).
- Storage is backed by [vercel postgres](https://vercel.com/docs/storage/vercel-postgres).

## Run Locally

Make sure you have `NodeJS` and `Postgres` installed.

Install dependencies with:

```bash
npm install
```

### Database Setup

Create a postgres database with:

```sql
CREATE DATABASE realworld_api
```

Run the schema migration with:

```bash
psql -d realworld_api -a -f ./db/migrations/v1_initial_schema.up.sql
```

### Running the api

Add the following environment variables:

```bash
export POSTGRES_URL=postgresql://localhost/realworld_api
export JWT_SECRET=sUpErSecReTjWtSecreT123456
export PORT=3000
```

Run the api in dev mode with:

```bash
npm start
```

This starts the api with a single express endpoint.

Import the [Postman Collection](./integration/Conduit.postman_collection.json) to try out interacting with the api.
