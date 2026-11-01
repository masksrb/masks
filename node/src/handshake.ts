import { constantEqual } from "./client.js";
import { Refused } from "./errors.js";
import type { Issuer } from "./issuer.js";
import { random } from "./key.js";
import type { Registration } from "./registration.js";
import { untrailed } from "./slashes.js";

export const HANDSHAKE_PATH = "/handshake";
export const HANDSHAKE_GRANT_TYPES = ["authorization_code", "refresh_token"];
export const HANDSHAKE_AUTH_METHOD = "client_secret_basic";

export interface HandshakeOptions {
  name: string;
  resource: string;
  redirectURIs: string[];
  returnTo: string;
  scope?: string[];
  backchannelLogoutURI?: string;
  postLogoutRedirectUri?: string;
}

export interface HandshakeStart {
  url: string;
  state: string;
}

export class Handshake {
  readonly issuer: Issuer;
  readonly name: string;
  readonly resource: string;
  readonly redirectURIs: string[];
  readonly returnTo: string;
  readonly scope: string[];
  readonly backchannelLogoutURI?: string;
  readonly postLogoutRedirectUri?: string;

  constructor(issuer: Issuer, options: HandshakeOptions) {
    this.issuer = issuer;
    this.name = String(options.name ?? "");
    this.resource = String(options.resource ?? "");
    this.redirectURIs = (options.redirectURIs ?? []).map(String);
    this.returnTo = String(options.returnTo ?? "");
    this.scope = (options.scope ?? ["openid", "profile", "email"])
      .flatMap((value) => String(value).split(/\s+/))
      .filter(Boolean);
    this.backchannelLogoutURI =
      issuer.metadata.backchannel_logout_supported === true
        ? options.backchannelLogoutURI
        : undefined;
    this.postLogoutRedirectUri = options.postLogoutRedirectUri;

    const origin = originOf(this.resource);

    if (!origin) {
      throw new Error(
        "masks: a handshake names its resource as an absolute http or https URL",
      );
    }

    const elsewhere = [
      this.returnTo,
      ...this.redirectURIs,
      ...(this.backchannelLogoutURI ? [this.backchannelLogoutURI] : []),
      ...(this.postLogoutRedirectUri ? [this.postLogoutRedirectUri] : []),
    ].filter((uri) => originOf(uri) !== origin);

    if (elsewhere.length > 0) {
      throw new Error(
        `masks: everything a handshake names shares the origin ${origin}: ${elsewhere.join(", ")}`,
      );
    }

    if (this.redirectURIs.length === 0) {
      throw new Error("masks: a handshake names at least one redirect URI");
    }

    if (this.scope.length === 0) {
      throw new Error("masks: a handshake names at least one scope");
    }
  }

  get endpoint(): string {
    const advertised = this.issuer.metadata.handshake_endpoint;

    return typeof advertised === "string" && advertised !== ""
      ? advertised
      : `${this.issuer.url}${HANDSHAKE_PATH}`;
  }

  start(state: string = random(32)): HandshakeStart {
    const url = new URL(this.endpoint);
    const query = url.searchParams;

    query.append("client_name", this.name);
    query.append("resource", this.resource);
    query.append("scope", this.scope.join(" "));
    query.append("return_to", this.returnTo);
    query.append("state", state);

    if (this.backchannelLogoutURI) {
      query.append("backchannel_logout_uri", this.backchannelLogoutURI);
    }

    if (this.postLogoutRedirectUri) {
      query.append("post_logout_redirect_uri", this.postLogoutRedirectUri);
    }

    for (const uri of this.redirectURIs) query.append("redirect_uris", uri);

    return { url: url.toString(), state };
  }

  async complete(
    returned: URLSearchParams | URL | Record<string, string | undefined>,
    state: string,
  ): Promise<Registration> {
    const params =
      returned instanceof URLSearchParams
        ? returned
        : returned instanceof URL
          ? returned.searchParams
          : new URLSearchParams(
              Object.entries(returned).filter(
                (pair): pair is [string, string] => typeof pair[1] === "string",
              ),
            );

    const error = params.get("error");

    if (error) {
      throw new Refused(error, params.get("error_description") ?? undefined);
    }

    if (!constantEqual(params.get("state") ?? "", state ?? "")) {
      throw Refused.of("state_mismatch");
    }

    const named = params.get("iss");

    if (named && untrailed(named) !== this.issuer.url) {
      throw new Refused(
        "invalid_issuer",
        `that came back from ${named}, and this app shakes hands with ${this.issuer.url}`,
      );
    }

    return this.redeem(params.get("initial_access_token") ?? "");
  }

  redeem(token: string): Promise<Registration> {
    if (!token) {
      throw new Refused(
        "invalid_request",
        "the handshake came back without a token",
      );
    }

    return this.issuer.register(
      {
        client_name: this.name,
        redirect_uris: this.redirectURIs,
        grant_types: HANDSHAKE_GRANT_TYPES,
        scope: this.scope.join(" "),
        token_endpoint_auth_method: HANDSHAKE_AUTH_METHOD,
        ...(this.backchannelLogoutURI
          ? { backchannel_logout_uri: this.backchannelLogoutURI }
          : {}),
      },
      token,
    );
  }
}

export function originOf(value: string): string | undefined {
  try {
    const url = new URL(value);

    if (url.protocol !== "https:" && url.protocol !== "http:") return undefined;
    if (url.hash) return undefined;

    return url.origin;
  } catch {
    return undefined;
  }
}
