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
    logo: { src: "./src/assets/masks.svg", alt: "" },
    favicon: "/favicon.svg",
    head: [{ tag: "link", attrs: { rel: "apple-touch-icon", href: "/apple-touch-icon.png" } }],
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
      {
        label: "Get started",
        items: [
          { label: "Overview", slug: "index" },
          { label: "Quickstart", slug: "quickstart" },
          { label: "Core concepts", slug: "guides/core-concepts" },
          { label: "Demo", slug: "demo", badge: { text: "todo", variant: "caution" } },
        ],
      },
      {
        label: "Run masks",
        items: [
          { label: "Self-hosting", slug: "guides/self-hosting" },
          { label: "Manage", slug: "guides/manage" },
          { label: "Security", slug: "guides/security" },
          { label: "Themes", slug: "guides/themes" },
        ],
      },
      {
        label: "Sign people in",
        items: [
          { label: "Features", slug: "guides/features" },
          { label: "Organizations", slug: "guides/organizations" },
          { label: "Single sign-on and SAML", slug: "guides/sso-saml" },
          { label: "LDAP", slug: "guides/ldap" },
          { label: "Enterprise", slug: "guides/enterprise" },
        ],
      },
      {
        label: "Connect your apps",
        items: [
          { label: "Connecting via SDK", slug: "guides/connecting-via-sdk" },
          { label: "Rails apps", slug: "guides/rails" },
          { label: "Other languages", slug: "guides/other-languages" },
          { label: "Forward authentication", slug: "guides/forward-auth" },
        ],
      },
      {
        label: "Send events",
        items: [
          { label: "Event streams", slug: "guides/event-streams" },
          { label: "Shared signals", slug: "guides/shared-signals" },
        ],
      },
      {
        label: "Reference",
        items: [
          { label: "OpenID Connect and OAuth", slug: "reference/specs" },
          { label: "Environment variables", slug: "reference/environment" },
          { label: "Manage API", slug: "reference/manage" },
          { label: "Manage API explorer", slug: "reference/explorer" },
          { label: "@masks/client", slug: "reference/browser" },
          { label: "Masks::Client", slug: "reference/ruby" },
          { label: "Masks::Rails", slug: "reference/rails" },
          {
            label: "Ruby API docs",
            link: "/api/ruby/",
            attrs: { target: "_blank" },
            badge: { text: "sdoc", variant: "note" },
          },
          { label: "Style guide", slug: "reference/style-guide" },
        ],
      },
    ],
  }), react(), staticIndex],
});