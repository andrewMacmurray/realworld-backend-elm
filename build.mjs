import * as esbuild from "esbuild";
import ElmPlugin from "esbuild-plugin-elm";

esbuild.build({
  entryPoints: [`src/vercel.ts`],
  bundle: true,
  minify: true,
  outfile: `dist/vercel.js`,
  platform: "node",
  plugins: [ElmPlugin({})],
});
