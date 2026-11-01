// @ts-check
import { defineConfig, passthroughImageService } from "astro/config";
import starlight from "@astrojs/starlight";

import react from "@astrojs/react";
import starlightLinksValidator from "starlight-links-validator";

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
  redirects: {
    "/reference/explorer": "/reference/manage/#explorer",
    "/quickstart": "/build/quickstart/",
    "/demo": "/build/demo/",
    "/guides/connecting-via-sdk": "/build/connecting-via-sdk/",
    "/guides/core-concepts": "/build/core-concepts/",
    "/guides/enterprise": "/build/enterprise/",
    "/guides/event-streams": "/build/event-streams/",
    "/guides/features": "/build/features/",
    "/guides/forward-auth": "/build/forward-auth/",
    "/guides/ldap": "/build/ldap/",
    "/guides/manage": "/build/manage/",
    "/guides/organizations": "/build/organizations/",
    "/guides/security": "/build/security/",
    "/guides/self-hosting": "/build/self-hosting/",
    "/guides/shared-signals": "/build/shared-signals/",
    "/guides/sso-saml": "/build/sso-saml/",
    "/guides/themes": "/build/themes/",
  },
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
    plugins: process.env.CHECK_LINKS
      ? [starlightLinksValidator({ errorOnRelativeLinks: false, exclude: ["/api/**"] })]
      : [],
    social: [
      {
        icon: "github",
        label: "GitHub",
        href: "https://github.com/masksrb/masks",
      },
    ],
    sidebar: [
      {
        label: "Use masks",
        items: [
          { label: "Overview", slug: "use" },
          { label: "What masks is", slug: "use/what-masks-is" },
          { label: "Run masks in one container", slug: "use/run-masks" },
          { label: "Set up your first account", slug: "use/first-account" },
          { label: "Invite and approve people", slug: "use/invite-people" },
          { label: "Signing in", slug: "use/signing-in" },
          { label: "Your account page", slug: "use/your-account" },
          { label: "Connect an app from the known list", slug: "use/connect-an-app" },
          { label: "Organizations", slug: "use/organizations" },
          { label: "Keep masks healthy", slug: "use/keep-masks-healthy" },
        ],
      },
      {
        label: "Build with masks",
        items: [
          { label: "Overview", slug: "build" },
          { label: "Quickstart", slug: "build/quickstart" },
          { label: "Core concepts", slug: "build/core-concepts" },
          { label: "Demo", slug: "build/demo", badge: { text: "todo", variant: "caution" } },
          { label: "Self-hosting", slug: "build/self-hosting" },
          { label: "Manage", slug: "build/manage" },
          { label: "Security", slug: "build/security" },
          { label: "Themes", slug: "build/themes" },
          { label: "Features", slug: "build/features" },
          { label: "Organizations", slug: "build/organizations" },
          { label: "Single sign-on and SAML", slug: "build/sso-saml" },
          { label: "LDAP", slug: "build/ldap" },
          { label: "Enterprise", slug: "build/enterprise" },
          { label: "Connecting via SDK", slug: "build/connecting-via-sdk" },
          { label: "Forward authentication", slug: "build/forward-auth" },
          { label: "Event streams", slug: "build/event-streams" },
          { label: "Shared signals", slug: "build/shared-signals" },
          {
            label: "Reference",
            items: [
              { label: "OpenID Connect and OAuth", slug: "reference/specs" },
              { label: "Environment variables", slug: "reference/environment" },
              { label: "Errors", slug: "reference/errors" },
              { label: "Manage API", slug: "reference/manage" },
              {
                label: "JavaScript",
                collapsed: true,
                items: [
                  { label: "Overview", slug: "reference/javascript" },
                  { label: "Next.js", slug: "reference/javascript/nextjs" },
                  { label: "Auth.js", slug: "reference/javascript/authjs" },
                  { label: "Express and Hono", slug: "reference/javascript/express-and-hono" },
                  { label: "Static sites", slug: "reference/javascript/static" },
                  { label: "@masks/server", slug: "reference/javascript/server" },
                  { label: "@masks/client", slug: "reference/javascript/client" },
                ],
              },
              {
                label: "Python",
                collapsed: true,
                items: [
                  { label: "Overview", slug: "reference/python" },
                  { label: "FastAPI", slug: "reference/python/fastapi" },
                  { label: "Django", slug: "reference/python/django" },
                  { label: "Flask", slug: "reference/python/flask" },
                  { label: "masks-client", slug: "reference/python/client" },
                ],
              },
              {
                label: "Go",
                collapsed: true,
                items: [{ label: "Overview", slug: "reference/go" }],
              },
              {
                label: "Ruby",
                collapsed: true,
                items: [
                  { label: "Overview", slug: "reference/ruby" },
                  { label: "Server mode", slug: "reference/ruby/server-mode" },
                  { label: "Engine mode", slug: "reference/ruby/engine-mode" },
                  { label: "Masks::Client", slug: "reference/ruby/client" },
                  { label: "Masks::Rails", slug: "reference/ruby/rails" },
                  {
                    label: "Ruby API docs",
                    link: "/api/ruby/",
                    attrs: { target: "_blank" },
                    badge: { text: "sdoc", variant: "note" },
                  },
                ],
              },
              { label: "Style guide", slug: "reference/style-guide" },
            ],
          },
        ],
      },
    ],
  }), react(), staticIndex],
});