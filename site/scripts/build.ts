import { cp, mkdir, rm } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const outdir = resolve(root, "dist");

await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });
const result = await Bun.build({
  entrypoints: [resolve(root, "src/index.html")],
  outdir,
  target: "browser",
  minify: true,
  naming: {
    entry: "[name].[ext]",
    asset: "assets/[name].[ext]"
  }
});
if (!result.success) throw new AggregateError(result.logs, "Site build failed");

// Demo rings and social metadata use fixed URLs that the HTML bundler cannot discover.
await cp(resolve(root, "public"), outdir, { recursive: true });
console.log(`Built Usage Rings into ${outdir}`);
