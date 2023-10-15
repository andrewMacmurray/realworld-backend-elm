import type { VercelRequest, VercelResponse } from "@vercel/node";
import * as utils from "./ts/utils";
import * as Api from "./api";

const api = Api.init();

export function handler(req: VercelRequest, res: VercelResponse) {
  return api.handle(toRequest(req)).then((res_) => {
    setHeaders(res_, res);
    res.status(res_.status);
    res.json(res_.body);
  });
}

function setHeaders(res_: Api.Response, res: VercelResponse): void {
  for (const header in res_.headers) {
    res.setHeader(header, res_.headers[header]);
  }
}

function toRequest(req: VercelRequest): Api.Request {
  const url = new URL(req.url || "", `http://${req.headers.host}`);
  return {
    path: url.pathname,
    method: req.method!,
    body: req.body,
    query: utils.flatten(req.query),
    headers: utils.flatten(req.headers),
  };
}
