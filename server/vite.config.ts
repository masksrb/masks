import tailwindcss from "@tailwindcss/vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";

const clientPort = Number(process.env.DEV_CLIENT_PORT) || undefined;
const allowedHosts = process.env.DEV_ALLOWED_HOSTS?.split(",").filter(Boolean);

export default defineConfig({
  plugins: [tailwindcss(), svelte(), RubyPlugin()],
  server: clientPort
    ? {
        allowedHosts,
        ws: { clientPort },
        watch: { usePolling: true, interval: 300 },
      }
    : undefined,
});
