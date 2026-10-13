import {
  CLIENT_PATH,
  type ClientMetadataOptions,
  clientMetadata,
} from "./metadata.js";

export interface MasksViteOptions
  extends Omit<ClientMetadataOptions, "origin"> {
  origin?: string;
}

interface Served {
  url?: string;
  headers: { host?: string };
}

interface Answer {
  setHeader(name: string, value: string): void;
  end(body: string): void;
}

interface Bundling {
  environment?: { name?: string };
  error(message: string): never;
  emitFile(file: { type: "asset"; fileName: string; source: string }): string;
}

export interface MasksVitePlugin {
  name: string;
  configureServer(server: {
    middlewares: {
      use(
        handler: (request: Served, response: Answer, next: () => void) => void,
      ): void;
    };
  }): void;
  generateBundle(this: Bundling): void;
}

export function masks(options: MasksViteOptions): MasksVitePlugin {
  const document = (origin: string) =>
    `${JSON.stringify(clientMetadata({ ...options, origin }), null, 2)}\n`;

  return {
    name: "masks",

    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        if (request.url?.split("?")[0] !== CLIENT_PATH) return next();

        response.setHeader("Content-Type", "application/json");
        response.setHeader("Cache-Control", "no-cache");
        response.end(
          document(options.origin ?? `http://${request.headers.host}`),
        );
      });
    },

    generateBundle() {
      if (this.environment?.name === "ssr") return;

      const origin = options.origin ?? environment().MASKS_ORIGIN;

      if (!origin) {
        this.error(
          "masks: set origin, or MASKS_ORIGIN, to the site's public address, such as https://catalog.example.com",
        );
      }

      this.emitFile({
        type: "asset",
        fileName: CLIENT_PATH.slice(1),
        source: document(origin),
      });
    },
  };
}

function environment(): Record<string, string | undefined> {
  return (
    (globalThis as { process?: { env?: Record<string, string | undefined> } })
      .process?.env ?? {}
  );
}
