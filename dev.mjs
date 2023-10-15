import * as esbuild from "esbuild";
import ElmPlugin from "esbuild-plugin-elm";
import start from "@es-exec/esbuild-plugin-start";

esbuild
  .context({
    entryPoints: [`src/express.ts`],
    bundle: true,
    outfile: `dist/express.js`,
    platform: "node",
    plugins: [ElmPlugin({}), start({ script: `node ./dist/express.js` })],
  })
  .then((ctx) => ctx.watch());
