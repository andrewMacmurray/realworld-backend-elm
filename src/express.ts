import express from "express";
import * as Api from "./api";

const api = Api.init();
const app = express();
app.use(express.json());

app.all("/*", (req, res) => {
  return api.handle(req).then((res_) => {
    res.set(res_.headers);
    res.status(res_.status);
    res.json(res_.body);
  });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`api started on ${PORT}`);
});
