import jwt from "jsonwebtoken";
import { env } from "./env";
import { Tasks } from "@andrewmacmurray/elm-concurrent-task";

export function tasks(): Tasks {
  return {
    "jwt:sign": signJwt,
    "jwt:verify": verifyJwt,
  };
}

interface JwtPayload {
  [key: string]: any;
}

function signJwt(payload: JwtPayload): string {
  return jwt.sign(payload, env.JWT_SECRET);
}

function verifyJwt(token: string): JwtPayload {
  return jwt.verify(token, env.JWT_SECRET);
}
