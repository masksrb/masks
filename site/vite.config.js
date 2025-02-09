import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "tailwindcss";

export default defineConfig({
  plugins: [svelte(), tailwindcss()],
});
