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

test("publishes adaptive favicons with PNG and ICO fallbacks", async () => {
  const html = await Bun.file(resolve(output, "index.html")).text();
  const icons = [...html.matchAll(/<link\b[^>]*rel="icon"[^>]*>/g)].map(([link]) => ({
    href: link.match(/href="([^"]+)"/)?.[1],
    type: link.match(/type="([^"]+)"/)?.[1],
    sizes: link.match(/sizes="([^"]+)"/)?.[1],
    media: link.match(/media="([^"]+)"/)?.[1]
  }));
  expect(icons).toEqual([
    expect.objectContaining({ href: expect.stringMatching(/\/favicon-[a-z0-9]+\.ico$/i), sizes: "16x16 32x32 48x48" }),
    expect.objectContaining({ href: expect.stringMatching(/\/favicon-32-[a-z0-9]+\.png$/i), type: "image/png", media: "(prefers-color-scheme: light)" }),
    expect.objectContaining({ href: expect.stringMatching(/\/favicon-32-dark-[a-z0-9]+\.png$/i), type: "image/png", media: "(prefers-color-scheme: dark)" }),
    expect.objectContaining({ href: expect.stringMatching(/\/favicon-[a-z0-9]+\.svg$/i), type: "image/svg+xml", sizes: "any" })
  ]);
  for (const asset of ["favicon.ico", "assets/favicon.svg", "assets/favicon-32.png", "assets/favicon-32-dark.png", "assets/AppIcon.png", "assets/AppIcon-dark.png", "assets/apple-touch-icon.png"]) {
    expect(await Bun.file(resolve(output, asset)).exists(), asset).toBe(true);
  }
});

test("keeps the adaptive favicon aligned with the native icon geometry", async () => {
  const native = await Bun.file(resolve(import.meta.dir, "../../Assets/AppIcon.svg")).text();
  const favicon = await Bun.file(resolve(output, "assets/favicon.svg")).text();
  const geometry = (svg: string) => svg.match(/\b(?:viewBox|cx|cy|r|d|stroke-width|stroke-linecap|stroke-dasharray|transform)="[^"]*"/g);
  expect(geometry(native)).not.toBeNull();
  expect(geometry(favicon)).toEqual(geometry(native));
  expect(favicon).toMatch(/@media\s*\(prefers-color-scheme:\s*dark\)/);
});
