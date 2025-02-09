// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import svelte from "@astrojs/svelte";
import tailwindcss from "@tailwindcss/vite";
import GraphQL from "astro-graphql-plugin";
import fs from "fs";

let loadSettingJSON = async (f) => {
  const contents = await fs.promises.readFile(`../doc/settings/${f}`, "utf-8");

  return JSON.parse(contents);
};

// https://astro.build/config
export default defineConfig({
  markdown: {
    remarkPlugins: [
      function addJSONPlugin() {
        return async (tree, file) => {
          if (file.data.astro.frontmatter.json) {
            file.data.astro.frontmatter.json = await loadSettingJSON(
              file.data.astro.frontmatter.json
            );
          }
        };
      },
    ],
  },
  integrations: [
    starlight({
      title: "masks",
      social: {
        github: "https://github.com/masksrb/masks",
      },
      sidebar: [
        // Each item here is one entry in the navigation menu.
        {
          label: "Get started",
          items: [
            { label: "Introduction", slug: "guides/intro" },
            { label: "Self-hosting", slug: "guides/self-host" },
            { label: "Ruby & Rails", slug: "guides/rails" },
          ],
        },
        {
          label: "Guides",
          items: [
            { label: "Single sign-in", slug: "guides/rails" },
            { label: "Signups & invites", slug: "guides/rails" },
            { label: "Profile management", slug: "guides/rails" },
            { label: "Privacy", slug: "guides/rails" },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "masks.yml", link: "reference/masks.yml" },
            { label: "Clients", link: "reference/clients" },
            { label: "Actors", link: "reference/actors" },
            { label: "Providers", link: "reference/providers" },
            { label: "Ruby API", link: "reference/ruby" },
            { label: "GraphQL API", link: "reference/graphql" },
            { label: "Command-line", link: "reference/cli" },
          ],
        },
        { label: "Demo & examples", slug: "guides/demo" },
      ],
    }),
    svelte(),
    GraphQL({
      schema: "../doc/graphql/schema.graphql",
      output: "../doc/graphql/schema.md",
      linkPrefix: "/reference/graphql/",
    }),
  ],

  vite: {
    plugins: [tailwindcss()],
  },
});
