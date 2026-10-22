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

test("declares one fixed favicon and keeps matching legacy paths", async () => {
  const html = await Bun.file(resolve(output, "index.html")).text();
  const icons = [...html.matchAll(/<link\b[^>]*rel="icon"[^>]*>/g)].map(([link]) => ({
    href: link.match(/href="([^"]+)"/)?.[1],
    type: link.match(/type="([^"]+)"/)?.[1],
    sizes: link.match(/sizes="([^"]+)"/)?.[1],
    media: link.match(/media="([^"]+)"/)?.[1]
  }));
  expect(icons).toEqual([
    { href: expect.stringMatching(/\/favicon-32-[a-z0-9]+\.png$/i), type: "image/png", sizes: "32x32", media: undefined }
  ]);
  for (const asset of ["favicon.ico", "assets/favicon.svg", "assets/favicon-32.png", "assets/favicon-32-dark.png", "assets/AppIcon.png", "assets/AppIcon-dark.png", "assets/apple-touch-icon.png"]) {
    expect(await Bun.file(resolve(output, asset)).exists(), asset).toBe(true);
  }
  expect(await Bun.file(resolve(output, "assets/favicon-32-dark.png")).bytes())
    .toEqual(await Bun.file(resolve(output, "assets/favicon-32.png")).bytes());
  const ico = await Bun.file(resolve(output, "favicon.ico")).bytes();
  const directory = new DataView(ico.buffer, ico.byteOffset, ico.byteLength);
  expect(directory.getUint16(0, true)).toBe(0);
  expect(directory.getUint16(2, true)).toBe(1);
  expect(directory.getUint16(4, true)).toBe(3);
  for (const [index, size] of [16, 32, 48].entries()) {
    const entry = 6 + index * 16;
    expect([ico[entry], ico[entry + 1]]).toEqual([size, size]);
    const length = directory.getUint32(entry + 8, true);
    const offset = directory.getUint32(entry + 12, true);
    expect(offset + length).toBeLessThanOrEqual(ico.length);
    if (size === 32) expect(ico.slice(offset, offset + length))
      .toEqual(await Bun.file(resolve(output, "assets/favicon-32.png")).bytes());
  }
});

test("keeps native geometry inside a circular dark favicon background", async () => {
  const native = await Bun.file(resolve(import.meta.dir, "../../Assets/AppIcon.svg")).text();
  const favicon = await Bun.file(resolve(output, "assets/favicon.svg")).text();
  const geometry = (svg: string) => svg.match(/\b(?:viewBox|cx|cy|r|d|stroke-width|stroke-linecap|stroke-dasharray|transform)="[^"]*"/g);
  const background = favicon.match(/<circle\b[^>]*id="background"[^>]*>/)?.[0] ?? "";
  const track = native.match(/<circle\b[^>]*id="track"[^>]*>/)?.[0] ?? "";
  const attribute = (shape: string, name: string) => Number(shape.match(new RegExp(`\\b${name}="([^"]+)"`))?.[1]);
  const artwork = favicon.replace(/<circle\b[^>]*id="background"[^>]*(?:\/>|>\s*<\/circle>)/, "");
  expect(geometry(native)).not.toBeNull();
  expect(geometry(artwork)).toEqual(geometry(native));
  expect(favicon).not.toContain("@media");
  expect(favicon).not.toContain("<rect");
  expect(background).toContain('fill="#000"');
  expect(attribute(background, "cx")).toBe(attribute(track, "cx"));
  expect(attribute(background, "cy")).toBe(attribute(track, "cy"));
  expect(attribute(background, "r")).toBe(attribute(track, "r") + attribute(track, "stroke-width") / 2);
  expect(favicon).toMatch(/<path\b[^>]*id="question"[^>]*fill="rgb\(255\.0+,255\.0+,255\.0+\)"/);
});
