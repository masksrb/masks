// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

import svelte from "@astrojs/svelte";

// https://astro.build/config
export default defineConfig({
  integrations: [
    starlight({
      title: "masks",
      social: {
        github: "https://github.com/geiger-to/masks",
      },
      sidebar: [
        // Each item here is one entry in the navigation menu.
        {
          label: "Guides",
          items: [
            { label: "Introduction", slug: "guides/intro" },
            { label: "Self-hosting", slug: "guides/self-host" },
            { label: "Ruby on Rails", slug: "guides/rails" },
            { label: "Node/JS clients", slug: "guides/rails" },
            { label: "Backend APIs", slug: "guides/integration" },
            { label: "Mobile apps", slug: "guides/integration" },
          ],
        },
        {
          label: "Customization",
          items: [
            { label: "Overview", slug: "guides/self-host" },
            { label: "Frontend", slug: "guides/rails" },
            { label: "Clients", slug: "guides/clients" },
            { label: "Actors", slug: "guides/self-host" },
            { label: "Sessions", slug: "guides/rails" },
            { label: "Providers", slug: "guides/rails" },
            { label: "Privacy", slug: "guides/rails" },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "masks.yml", slug: "reference/masks-yml" },
            { label: "clients.yml", slug: "reference/clients-yml" },
          ],
        },
        {
          label: "Developers",
          collapsed: true,
          items: [
            { label: "Overview", slug: "guides/how-it-works" },
            { label: "Ruby/Rails ", slug: "guides/rails" },
            { label: "Javascript", slug: "guides/rails" },
            { label: "GraphQL", slug: "guides/rails" },
            { label: "HTTP", slug: "guides/rails" },
            { label: "CLI", slug: "guides/rails" },
            { label: "Testing", slug: "guides/rails" },
            { label: "Contribute", slug: "guides/rails" },
          ],
        },
        { label: "Examples", slug: "guides/rails" },
      ],
    }),
    svelte(),
  ],
});
