import { defineCollection } from "astro:content";
import { docsLoader } from "@astrojs/starlight/loaders";
import { docsSchema } from "@astrojs/starlight/schema";
import { glob } from "astro/loaders";

export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
  ruby: defineCollection({
    loader: glob({
      pattern: "**/*.md",
      base: "../doc/ruby/",
      generateId: ({ entry }) => entry.replace(/\.md/, ".html"),
    }),
  }),
  graphql: defineCollection({
    loader: glob({
      pattern: "**/*.md",
      base: "../doc/graphql/schema.md/",
      generateId: ({ entry }) => entry.replace(/\.md/, ""),
    }),
  }),
  reference: defineCollection({
    loader: glob({
      pattern: "**/*.mdx",
      base: "src/reference",
      generateId: ({ entry }) => entry.replace(/\.mdx/, ""),
    }),
  }),
};
