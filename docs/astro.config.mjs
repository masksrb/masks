// @ts-check
import { defineConfig, passthroughImageService } from "astro/config";
import starlight from "@astrojs/starlight";

import react from "@astrojs/react";

// The RDoc site under public/api/ is plain files. Cloudflare Pages resolves a
// directory to its index.html; `astro dev` does not, so /api/ruby/ 404s only
// while developing. Do it here so the published URL and the local one match.
const staticIndex = {
  name: "masks:static-index",
  hooks: {
    "astro:server:setup"({ server }) {
      server.middlewares.use((request, _response, next) => {
        const [path, query] = (request.url ?? "").split("?");

        if (path.startsWith("/api/") && !path.split("/").pop().includes(".")) {
          const directory = path.endsWith("/") ? path : `${path}/`;

          request.url = `${directory}index.html${query ? `?${query}` : ""}`;
        }

        next();
      });
    },
  },
};

const clientPort = Number(process.env.DEV_CLIENT_PORT) || undefined;
const allowedHosts = process.env.DEV_ALLOWED_HOSTS?.split(",").filter(Boolean);

export default defineConfig({
  // Where it is published. DOCS_SITE overrides it for a preview deploy; without
  // either, @astrojs/sitemap silently emits nothing and canonical URLs are absent.
  site: process.env.DOCS_SITE || "https://masks.pages.dev",
  image: { service: passthroughImageService() },
  server: allowedHosts ? { host: true, allowedHosts } : {},
  vite: clientPort
    ? {
        server: {
          allowedHosts,
          ws: { clientPort },
          watch: { usePolling: true, interval: 300 },
        },
      }
    : {},
  integrations: [starlight({
    title: "masks",
    description:
      "Self-hosted auth for the open web, with a signing key for every tenant.",
    customCss: ["./src/styles/global.css"],
    social: [
      {
        icon: "github",
        label: "GitHub",
        href: "https://github.com/masksrb/masks",
      },
    ],
    sidebar: [
      { label: "Overview", slug: "index" },
      { label: "Quickstart", slug: "quickstart", badge: { text: "todo", variant: "caution" } },
      { label: "Demo", slug: "demo", badge: { text: "todo", variant: "caution" } },
      {
        label: "Concepts",
        items: [
          { label: "Tenants", slug: "concepts/tenants" },
          { label: "Actors", slug: "concepts/actors" },
          { label: "Clients", slug: "concepts/clients" },
          { label: "Pushed requests", slug: "concepts/pushing" },
          { label: "Device sign-in", slug: "concepts/device-grant" },
          { label: "Scopes", slug: "concepts/scopes" },
          { label: "Namespaces", slug: "concepts/namespaces" },
          { label: "Sessions and devices", slug: "concepts/sessions" },
          { label: "Signing keys", slug: "concepts/keys" },
        ],
      },
      {
        label: "Reference",
        items: [
          { label: "GraphQL", slug: "reference/manage" },
          { label: "Explorer", slug: "reference/explorer" },
          { label: "@masks/client", slug: "reference/browser" },
          { label: "Masks::Client", slug: "reference/ruby" },
          { label: "Masks::Rails", slug: "reference/rails" },
          {
            label: "Masks::Client",
            link: "/api/ruby/",
            attrs: { target: "_blank" },
            badge: { text: "sdoc", variant: "note" },
          },
          { label: "Design", slug: "reference/design" },
        ],
      },
    ],
  }), react(), staticIndex],
});