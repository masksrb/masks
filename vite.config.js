import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";
import FullReload from "vite-plugin-full-reload";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "tailwindcss";

export default defineConfig({
  plugins: [
    RubyPlugin(),
    FullReload(["config/routes.rb", "app/views/**/*"]),
    svelte(),
    tailwindcss(),
  ],
});
