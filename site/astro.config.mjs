import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

const site = process.env.SITE_URL || "https://pines-ios-ai.netlify.app";

export default defineConfig({
  site,
  integrations: [sitemap()],
  output: "static",
  vite: {
    server: {
      fs: {
        allow: [".."],
      },
    },
  },
});
