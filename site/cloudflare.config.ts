import { defineConfig } from "cf/config";

export default defineConfig(({ mode }) => {
  if (mode !== undefined && mode !== "preview" && mode !== "production") {
    throw new Error(`Unsupported Cloudflare mode: ${mode}`);
  }

  return {
    accountId: "7e0d344d3920f4fa34ccd3b3c4e2a0c7",
    worker: {
      name: mode === "production" ? "ato-site" : "ato-site-preview",
      ...(mode === "production" ? { domains: ["ato.shigoto.dev"] } : {}),
      compatibilityDate: "2026-11-09",
      workersDev: true,
      observability: { enabled: true },
    },
  };
});
