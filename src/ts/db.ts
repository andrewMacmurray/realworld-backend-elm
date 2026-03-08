import { Pool, PoolClient, QueryResult } from "pg";
import pgTypes from "pg-types";
import * as vercel from "@vercel/postgres";
import { env } from "./env";
import { Tasks } from "@andrewmacmurray/elm-concurrent-task";

const pool = createPool()

export function tasks(): Tasks {
  return {
    "db:query": query,
  };
}

function query(options: { query: string }): Promise<QueryResult<any>> {
  return pool.query({ text: options.query, types: { getTypeParser } })
}

function getTypeParser(id: pgTypes.TypeId, format?: pgTypes.TypeFormat) {
  return (val: any) => {
    switch (id) {
      // Allow Elm to decode dates as strings rather than a JS Date object
      case pgTypes.builtins.TIMESTAMP:
        return val.replace(" ", "T");
      default:
        return pgTypes.getTypeParser(id, format)(val);
    }
  };
}

function createPool(): Pool {
  const connectionString = env.POSTGRES_URL;
  return env.NODE_ENV === "production"
    ? vercel.createPool({ connectionString })
    : new Pool({ connectionString });
}
