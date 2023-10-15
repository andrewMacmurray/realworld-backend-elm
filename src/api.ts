import { Elm } from "../elm/Main.elm";
import * as ConcurrentTask from "@andrewmacmurray/elm-concurrent-task";
import * as Jwt from "./ts/jwt";
import * as Env from "./ts/env";
import * as Db from "./ts/db";
import * as BCrypt from "./ts/bcrypt";

// Request / Response

export interface Request {
  headers: { [key: string]: string };
  method: string;
  query: { [key: string]: string };
  path: string;
  body: string;
}

export interface Response {
  status: number;
  headers: { [key: string]: string };
  body: any;
}

export interface Api {
  handle: (Request) => Promise<Response>;
}

// Api Program

export function init(): Api {
  Env.validate();

  const { ports } = Elm.Main.init({ flags: null });

  ConcurrentTask.register({
    tasks: {
      ...Jwt.tasks(),
      ...Db.tasks(),
      ...BCrypt.tasks(),
    },
    ports: {
      send: ports.send,
      receive: ports.receive,
    },
  });

  ports.respond.subscribe(({ resolve, response }) => {
    resolve(response);
  });

  function handle(request: Request): Promise<Response> {
    return new Promise((resolve) => ports.onRequest.send({ resolve, request }));
  }

  return { handle };
}
