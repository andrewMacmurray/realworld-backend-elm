import { Tasks } from "@andrewmacmurray/elm-concurrent-task";
import bcrypt from "bcryptjs";

export function tasks(): Tasks {
  return {
    "bcrypt:hash": hash,
    "bcrypt:compare": compare,
  };
}

function hash(options: {
  saltRounds: number;
  password: string;
}): Promise<string> {
  return bcrypt.hash(options.password, options.saltRounds);
}

function compare(options: {
  plaintext: string;
  hashed: string;
}): Promise<boolean> {
  return bcrypt.compare(options.plaintext, options.hashed);
}
