import { defineWranglerConfig } from "wrangler/experimental-config";

export default defineWranglerConfig({
  assetsDirectory: "dist",
  dev: { ip: "0.0.0.0", port: 8796, inspectorPort: 9296 },
});
