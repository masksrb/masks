import type { JWK } from "jose";
import type { Client } from "./client.js";
import {
  ForeignError,
  InsecureError,
  InvalidTokenError,
  MasksError,
  redacted,
} from "./errors.js";
import { getJSON } from "./http.js";
import type { Key } from "./key.js";
import {
  type ClientMetadata,
  clientFor,
  deleteRegistration,
  type Registration,
  readRegistration,
  register,
  updateRegistration,
} from "./registration.js";

export const DISCOVERY_PATH = "/.well-known/openid-configuration";
export const RESOURCE_PATH = "/.well-known/oauth-protected-resource";

const KEYS_LIFETIME = 5 * 60 * 1000;
const KEYS_PATIENCE = 30 * 1000;

export interface Tenant {
  uuid?: string;
  subdomain?: string;
  name?: string;
}

export interface Metadata {
  issuer: string;
  tenant?: Tenant;
  authorization_endpoint?: string;
  token_endpoint?: string;
  userinfo_endpoint?: string;
  jwks_uri?: string;
  registration_endpoint?: string;
  device_authorization_endpoint?: string;
  enrollment_endpoint?: string;
  handshake_endpoint?: string;
  revocation_endpoint?: string;
  introspection_endpoint?: string;
  end_session_endpoint?: string;
  scopes_supported?: string[];
  grant_types_supported?: string[];
  token_endpoint_auth_methods_supported?: string[];
  dpop_signing_alg_values_supported?: string[];
  [field: string]: unknown;
}

export interface ResourceMetadata {
  resource: string;
  authorization_servers?: string[];
  scopes_supported?: string[];
  bearer_methods_supported?: string[];
  resource_name?: string;
  [field: string]: unknown;
}

export type { Options } from "./http.js";

import type { Options } from "./http.js";

const ENDPOINTS = [
  "authorization_endpoint",
  "token_endpoint",
  "userinfo_endpoint",
  "jwks_uri",
  "registration_endpoint",
  "device_authorization_endpoint",
  "enrollment_endpoint",
  "handshake_endpoint",
  "revocation_endpoint",
  "introspection_endpoint",
  "end_session_endpoint",
] as const;

export class Issuer {
  readonly url: string;
  readonly metadata: Metadata;
  readonly options: Options;
  #keys: JWK[] = [];
  #keysAt = 0;
  #fetching?: Promise<void>;

  private constructor(url: string, metadata: Metadata, options: Options) {
    this.url = url;
    this.metadata = metadata;
    this.options = options;
  }

  static async discover(
    issuer: string,
    options: Options = {},
  ): Promise<Issuer> {
    const named = issuer.replace(/\/+$/, "");

    check(named, options);

    const metadata = await getJSON<Metadata>(
      options,
      `${named}${DISCOVERY_PATH}`,
    );

    if (String(metadata.issuer ?? "").replace(/\/+$/, "") !== named) {
      throw new MasksError(
        "invalid_issuer",
        `${named} publishes a document naming ${JSON.stringify(metadata.issuer)}`,
      );
    }

    for (const name of ENDPOINTS) {
      const value = metadata[name];
      if (typeof value === "string" && value !== "") check(value, options);
    }

    return new Issuer(named, metadata, options);
  }

  get fetch(): typeof fetch {
    return this.options.fetch ?? globalThis.fetch;
  }

  endpoint(name: keyof Metadata & string): string {
    const value = this.metadata[name];

    if (typeof value !== "string" || value === "") {
      throw new MasksError(
        "invalid_issuer",
        `${this.url} publishes no ${name}`,
      );
    }

    return value;
  }

  sameOrigin(target: string): void {
    const held = new URL(target);

    if (held.origin !== new URL(this.url).origin) {
      throw new ForeignError(redacted(target));
    }
  }

  register(
    metadata: ClientMetadata,
    initialAccessToken?: string,
  ): Promise<Registration> {
    return register(this, metadata, initialAccessToken);
  }

  readRegistration(held: Registration): Promise<Registration> {
    return readRegistration(this, held);
  }

  updateRegistration(
    held: Registration,
    metadata: ClientMetadata,
  ): Promise<Registration> {
    return updateRegistration(this, held, metadata);
  }

  deleteRegistration(held: Registration): Promise<void> {
    return deleteRegistration(this, held);
  }

  client(held: Registration, key?: Key, dpop?: Key): Client {
    return clientFor(this, held, key, dpop);
  }

  async key(kid: string | undefined): Promise<JWK> {
    const fresh = Date.now() - this.#keysAt < KEYS_LIFETIME;
    const found = () =>
      this.#keys.find(
        (held) => held.kid === kid && held.use !== "enc" && !("d" in held),
      );

    if (kid && fresh && found()) return found() as JWK;

    if (Date.now() - this.#keysAt >= KEYS_PATIENCE) {
      this.#fetching ??= getJSON<{ keys?: JWK[] }>(
        this.options,
        this.endpoint("jwks_uri"),
      )
        .then((held) => {
          this.#keys = Array.isArray(held.keys) ? held.keys : [];
          this.#keysAt = Date.now();
        })
        .finally(() => {
          this.#fetching = undefined;
        });

      await this.#fetching;
    }

    const held = kid ? found() : undefined;

    if (!held) {
      throw new InvalidTokenError(
        `${this.url} publishes no key ${JSON.stringify(kid ?? null)}`,
      );
    }

    return held;
  }
}

export async function discoverResource(
  resource: string,
  options: Options = {},
): Promise<ResourceMetadata> {
  const named = resource.replace(/\/+$/, "");

  check(named, options);

  const parsed = new URL(named);
  const path = parsed.pathname === "/" ? "" : parsed.pathname;
  const document = `${parsed.origin}${RESOURCE_PATH}${path}`;
  const found = await getJSON<ResourceMetadata>(options, document);

  if (String(found.resource ?? "").replace(/\/+$/, "") !== named) {
    throw new MasksError(
      "invalid_resource",
      `${named} publishes metadata naming ${JSON.stringify(found.resource)}`,
    );
  }

  return found;
}

export function check(target: string, options: Options = {}): void {
  let parsed: URL;

  try {
    parsed = new URL(target);
  } catch {
    throw new Error(
      `masks: ${JSON.stringify(target)} is not an http or https URL`,
    );
  }

  if (parsed.protocol === "https:" && parsed.host !== "") return;

  if (parsed.protocol === "http:") {
    if (options.allowPlainHTTP || loopback(parsed.hostname)) return;

    throw new InsecureError(redacted(target));
  }

  throw new Error(
    `masks: ${JSON.stringify(target)} is not an http or https URL`,
  );
}

export function loopback(host: string): boolean {
  const held = host.replace(/^\[|\]$/g, "").toLowerCase();

  if (held === "localhost" || held.endsWith(".localhost")) return true;
  if (held === "::1") return true;

  return /^127(\.\d{1,3}){3}$/.test(held);
}
