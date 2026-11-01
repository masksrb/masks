import { isRefused, Refused, Unavailable } from "../errors.js";
import { type Handshake, originOf } from "../handshake.js";
import type { Issuer } from "../issuer.js";
import type { CredentialStore } from "./credentials.js";
import type { Masked } from "./masked.js";
import type { Privileges } from "./privileges.js";
import { provenance, wantsJSON } from "./requests.js";
import {
  errorResponse,
  escapeHTML,
  fromAnotherSite,
  json,
  page,
  redirect,
} from "./responses.js";
import { remember } from "./stores.js";

export interface HandshakeSite {
  origin: string;
  issuer: string;
  cookies: string[];
}

export interface HandshakeHost {
  readonly handshakePath: string;
  readonly credentials: CredentialStore;
  site(request: Request): Promise<HandshakeSite>;
  issuer(request: Request): Promise<Issuer>;
  handshake(request: Request): Promise<Handshake>;
  readonly privileges: Privileges;
  readonly manages?:
    | string
    | ((request: Request, masked: Masked) => boolean | Promise<boolean>);
  actor(request: Request): Promise<Masked>;
  signInURL(returnTo: string, privileges: string[]): string;
  steppedUp(request: Request, privileges: string[]): Promise<boolean>;
  remember(request: Request, state: string): Promise<string[]>;
  recall(
    request: Request,
    state: string,
  ): Promise<{ found: boolean; returnTo?: string; cookies: string[] }>;
  connected(
    request: Request,
    returnTo: string | undefined,
    cookies: string[],
  ): Promise<Response>;
  disconnected?(request: Request): Promise<void>;
}

const REMEMBERED_REGISTRATIONS = 1_000;
const REGISTRATION_TRUSTED = 60_000;

export class Handshakes {
  readonly #host: HandshakeHost;
  readonly #registeredAt = new Map<string, number>();

  constructor(host: HandshakeHost) {
    this.#host = host;
  }

  async configured(request: Request): Promise<boolean> {
    return !!(await this.#host.credentials.read(request))?.client_id;
  }

  async show(request: Request): Promise<Response> {
    if (!(await this.configured(request))) return this.#begin(request);

    const refused = await this.manager(request);
    if (refused) return refused;

    const site = await this.#host.site(request);

    return connectedPage(
      this.#host.handshakePath,
      site.issuer,
      Boolean(this.#host.credentials.clear),
      site.cookies,
    );
  }

  async create(request: Request): Promise<Response> {
    const site = await this.#host.site(request);

    const seen = provenance(request, site.origin);

    if (seen === "cross-site") {
      return errorResponse(
        request,
        403,
        "forbidden",
        "a handshake is only started from this app",
        site.cookies,
      );
    }

    if (seen === "unproven") return fromAnotherSite(request, site.cookies);

    if (await this.configured(request)) {
      const refused = await this.manager(request);
      if (refused) return refused;
    }

    return this.#begin(request);
  }

  async destroy(request: Request): Promise<Response> {
    const { handshakePath } = this.#host;
    const site = await this.#host.site(request);

    const seen = provenance(request, site.origin);

    if (seen === "cross-site") {
      return errorResponse(
        request,
        403,
        "forbidden",
        "a disconnect is only asked for from this app",
        site.cookies,
      );
    }

    if (seen === "unproven") return fromAnotherSite(request, site.cookies);

    if (!(await this.configured(request)))
      return redirect(handshakePath, site.cookies, 303);

    const refused = await this.manager(request);
    if (refused) return refused;

    if (!(await this.disconnect(request))) {
      return errorResponse(
        request,
        400,
        "invalid_request",
        "the credential store cannot forget this connection",
        site.cookies,
      );
    }

    await this.#host.disconnected?.(request);

    if (wantsJSON(request))
      return json(200, { connected: false }, site.cookies);

    return redirect(handshakePath, site.cookies, 303);
  }

  async callback(request: Request): Promise<Response> {
    const params = new URL(request.url).searchParams;
    const state = params.get("state") ?? "";
    const recalled = await this.#host.recall(request, state);
    const site = await this.#host.site(request);
    const cookies = () => [...site.cookies, ...recalled.cookies];

    if (!recalled.found) {
      return errorResponse(
        request,
        400,
        "invalid_state",
        "that connection request is not one this browser started, or it expired",
        cookies(),
      );
    }

    if (await this.configured(request)) {
      const refused = await this.manager(request);
      if (refused) return refused;
    }

    const { credentials } = this.#host;

    if (!credentials.write) {
      return errorResponse(
        request,
        500,
        "handshake_unsaved",
        "the credential store cannot save this connection; set credentials to a store that writes",
        cookies(),
      );
    }

    const handshake = await this.#host.handshake(request);
    const registration = await handshake.complete(params, state);

    await credentials.write(request, {
      client_id: registration.client_id,
      client_secret: registration.client_secret,
      registration_access_token: registration.registration_access_token,
      registration_client_uri: registration.registration_client_uri,
    });

    return this.#host.connected(request, recalled.returnTo, recalled.cookies);
  }

  async manager(request: Request): Promise<Response | undefined> {
    const host = this.#host;
    const site = await host.site(request);
    const masked = await host.actor(request);

    if (!masked.signedIn) {
      return redirect(
        host.signInURL(host.handshakePath, []),
        site.cookies,
        303,
      );
    }

    const { manages } = host;

    if (typeof manages === "function") {
      if ((await manages(request, masked)) === true) return undefined;
    } else if (typeof manages === "string") {
      const privilege = host.privileges.get(manages);

      if (masked.holds(privilege)) return undefined;

      const lacking = !privilege.scopes.every((scope) => masked.permits(scope));

      if (lacking && !(await host.steppedUp(request, [privilege.name]))) {
        return redirect(
          host.signInURL(host.handshakePath, [privilege.name]),
          site.cookies,
          303,
        );
      }
    }

    return errorResponse(
      request,
      403,
      "forbidden",
      "only somebody this app lets manage its connection can reconnect or disconnect it",
      site.cookies,
    );
  }

  async registered(request: Request): Promise<boolean> {
    const held = await this.#host.credentials.read(request);

    if (!held?.registration_client_uri || !held.registration_access_token)
      return true;

    try {
      await (await this.#host.issuer(request)).readRegistration(held);
      return true;
    } catch (error) {
      return !(
        error instanceof Refused && [401, 403, 404].includes(error.status ?? 0)
      );
    }
  }

  async stillRegistered(request: Request): Promise<boolean> {
    const held = await this.#host.credentials.read(request);

    if (!held?.client_id) return true;

    const { issuer } = await this.#host.site(request);
    const key = `${issuer} ${held.client_id}`;

    if ((this.#registeredAt.get(key) ?? 0) > Date.now() - REGISTRATION_TRUSTED)
      return true;

    if (await this.registered(request)) {
      remember(this.#registeredAt, key, Date.now(), REMEMBERED_REGISTRATIONS);
      return true;
    }

    this.#registeredAt.delete(key);
    await this.forget(request);

    return false;
  }

  async disconnect(request: Request): Promise<boolean> {
    const { credentials } = this.#host;

    if (!credentials.clear) return false;

    const held = await credentials.read(request);

    if (held?.registration_client_uri && held.registration_access_token) {
      try {
        await (await this.#host.issuer(request)).deleteRegistration(held);
      } catch (error) {
        if (!isRefused(error) || (error.status ?? 500) >= 500) {
          throw new Unavailable(
            "masks could not be reached to delete this app's registration",
            { cause: error },
          );
        }
      }
    }

    await credentials.clear(request);

    return true;
  }

  async forget(request: Request): Promise<boolean> {
    const { credentials } = this.#host;

    if (!credentials.clear) return false;

    try {
      await credentials.clear(request);
    } catch {
      return false;
    }

    return true;
  }

  async #begin(request: Request): Promise<Response> {
    const handshake = await this.#host.handshake(request);
    const started = handshake.start();
    const remembered = await this.#host.remember(request, started.state);
    const site = await this.#host.site(request);

    return redirect(started.url, [...site.cookies, ...remembered], 303);
  }
}

function connectedPage(
  handshakePath: string,
  issuer: string,
  disconnects: boolean,
  cookies: string[],
): Response {
  const path = escapeHTML(handshakePath);
  const target = originOf(issuer);

  return page(
    "This app is connected",
    `<p>Reconnecting replaces the credentials it holds with a fresh pair. It is how you rotate them, and how you move this app to another account. No secret passes through your browser.</p>
<p>The app stops working between the approval and the moment it picks the new credentials up.</p>
<form method="post" action="${path}"><button type="submit">Reconnect it</button></form>
${disconnects ? `<form method="post" action="${path}/disconnect"><button type="submit">Disconnect it</button></form>` : ""}`,
    cookies,
    target ? [target] : [],
  );
}
