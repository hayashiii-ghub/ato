import { resolve } from "node:path";
import homepage from "../src/index.html";

const preview = process.argv.includes("--preview");
const root = resolve(import.meta.dir, "..");
const directory = resolve(root, preview ? "dist" : "public");
const routes: Record<string, Response> = {};

for await (const path of new Bun.Glob("**/*").scan({ cwd: directory, onlyFiles: true })) {
  routes[`/${path}`] = new Response(Bun.file(resolve(directory, path)));
}

const server = Bun.serve({
  hostname: "127.0.0.1",
  port: Number(process.env.SITE_PORT ?? 4387),
  development: !preview,
  routes: {
    ...routes,
    "/": preview ? new Response(Bun.file(resolve(directory, "index.html"))) : homepage
  },
  fetch: () => new Response("Not found", { status: 404 })
});

console.log(`ato ${preview ? "preview" : "dev"}: ${server.url}`);
