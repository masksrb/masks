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
              file.data.astro.frontmatter.json,
            );
          }
        };
      },
    ],
  },
  integrations: [
    starlight({
      title: "masks",
      customCss: ['src/styles/global.css'],
      social: {
        github: "https://github.com/masksrb/masks",
      },
      sidebar: [
        {
          label: "Getting started",
          items: [
            { label: "Introduction", slug: "intro" },
            { label: "Examples", slug: "intro" },
            { label: "Installation", items: [
              { label: "Docker container", slug: "guides/docker" },
              { label: "Rails engine", slug: "guides/rails" },
            ] },
            { label: "Concepts", items: [
              { label: "Clients", slug: "guides/clients" },
              { label: "Actors", slug: "guides/actors" },
              { label: "Policies", slug: "guides/policies" },
            ] },
            { label: "Guides", items: [
              { label: "Clients", slug: "guides/clients" },
              { label: "Actors", slug: "guides/actors" },
              { label: "Policies", slug: "guides/policies" },
            ] },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "TODO", slug: "intro" },
          ],
        },
        // {
          // label: "Guides",
          // items: [
            // { label: "", slug: "guides/intro" },
            // { label: "Signups & invites", slug: "guides/rails" },
            // { label: "Profile management", slug: "guides/rails" },
            // { label: "Privacy", slug: "guides/rails" },
          // ],
        // },
        // {
          // label: "Reference",
          // items: [
            // { label: "masks.yml", link: "reference/masks.yml" },
            // { label: "Clients", link: "reference/clients" },
            // { label: "Actors", link: "reference/actors" },
            // { label: "Providers", link: "reference/providers" },
            // { label: "Ruby API", link: "reference/ruby" },
            // { label: "GraphQL API", link: "reference/graphql" },
            // { label: "Command-line", link: "reference/cli" },
          // ],
        // },
        // { label: "Demo & examples", slug: "guides/demo" },
      ],
    }),
    svelte(),
    // GraphQL({
      // schema: "../doc/graphql/schema.graphql",
      // output: "../doc/graphql/schema.md",
      // linkPrefix: "/reference/graphql/",
    // }),
  ],

  vite: {
    plugins: [tailwindcss()],
  },
});
