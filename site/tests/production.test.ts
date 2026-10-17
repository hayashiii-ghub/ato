import { expect, test } from "bun:test";
import { resolve } from "node:path";

const output = resolve(import.meta.dir, "../dist");

test("publishes canonical and social links at the product domain", async () => {
  const html = await Bun.file(resolve(output, "index.html")).text();
  expect(html).toContain('rel="canonical" href="https://ato.shigoto.dev"');
  expect(html).toContain('property="og:url" content="https://ato.shigoto.dev"');
  expect(html).not.toContain("hayashiii-gpt.chatgpt.site");
  expect(html).toContain("https://github.com/hayashiii-ghub/ato/releases/latest/download/usage-rings-macos.dmg");
  expect(await Bun.file(resolve(output, "sitemap.xml")).text()).toContain("https://ato.shigoto.dev/");
});

test("ships every local HTML asset in the static output", async () => {
  const html = await Bun.file(resolve(output, "index.html")).text();
  for (const match of html.matchAll(/(?:src|href)="([^"#]+)"/g)) {
    const value = match[1]!;
    const url = new URL(value, "https://ato.shigoto.dev");
    if (url.origin !== "https://ato.shigoto.dev" || url.pathname === "/") continue;
    expect(await Bun.file(resolve(output, `.${url.pathname}`)).exists(), value).toBe(true);
  }
});
