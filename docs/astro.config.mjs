// @ts-check
import { defineConfig, passthroughImageService } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: process.env.DOCS_SITE,
  image: { service: passthroughImageService() },
  integrations: [
    starlight({
      title: "masks",
      description:
        "A standalone OIDC provider with per-tenant signing keys, a client gem, and a Rails engine.",
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
          label: "Start here",
          items: [
            { label: "What masks is", slug: "index" },
            { label: "Running it", slug: "start/running" },
            { label: "The four pieces", slug: "start/pieces" },
          ],
        },
        {
          label: "Concepts",
          items: [
            { label: "Tenancy", slug: "concepts/tenancy" },
            { label: "Signing keys", slug: "concepts/keys" },
            { label: "Policies", slug: "concepts/policies" },
            { label: "Tokens and audiences", slug: "concepts/tokens" },
            { label: "Hardening", slug: "concepts/hardening" },
          ],
        },
        {
          label: "Guides",
          items: [
            { label: "Connect an app", slug: "guides/handshake" },
            { label: "Sign a Rails app in", slug: "guides/rails" },
            { label: "Sign an SPA in", slug: "guides/spa" },
            { label: "Verify a token", slug: "guides/verifying" },
            { label: "Register a connector", slug: "guides/connectors" },
            { label: "Narrow a token", slug: "guides/exchange" },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "Endpoints", slug: "reference/endpoints" },
            { label: "Configuration", slug: "reference/configuration" },
            { label: "Models", slug: "reference/models" },
            { label: "Conformance", slug: "reference/conformance" },
          ],
        },
      ],
    }),
  ],
});
