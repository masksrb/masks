import type { Client } from "../client.js";
import {
  type Connection as DelegatedConnection,
  DelegationRefused,
  Delegations,
  pendingFor,
} from "../delegations.js";
import { MasksError } from "../errors.js";
import { Core, type MasksOptions } from "./core.js";
import { check, guard, type Outcome, protect, refuse } from "./guard.js";
import type { Masked } from "./masked.js";
import type { Privileges } from "./privileges.js";
import { redirect } from "./responses.js";
import { handle } from "./routes.js";
import { claim, FLOW_LIFETIME, keep, now } from "./session.js";

export { DEFAULT_SCOPE, type MasksOptions } from "./core.js";
export type { Outcome } from "./guard.js";
export type { HeldTokens, SessionData } from "./session.js";

export interface Connection {
  connected: boolean;
  client_id?: string;
  issuer?: string;
}

export class Masks {
  readonly #core: Core;

  static from(source: Masks | MasksOptions | { masks: Masks }): Masks {
    if (source instanceof Masks) return source;
    if ("masks" in source && source.masks instanceof Masks) return source.masks;

    return new Masks(source as MasksOptions);
  }

  constructor(options: MasksOptions = {}) {
    this.#core = new Core(options);
  }

  get privileges(): Privileges {
    return this.#core.privileges;
  }

  get basePath(): string {
    return this.#core.basePath;
  }

  get scope(): string[] {
    return this.#core.scope;
  }

  get maxAge(): number {
    return this.#core.maxAge;
  }

  get logoutPath(): string {
    return this.#core.logoutPath;
  }

  get handshakePath(): string {
    return this.#core.handshakePath;
  }

  loginURL(
    asked: {
      returnTo?: string;
      organization?: string;
      privilege?: string | string[];
    } = {},
  ): string {
    return this.#core.loginURL(asked);
  }

  owns(pathname: string): boolean {
    return this.#core.owns(pathname);
  }

  handle(request: Request): Promise<Response | undefined> {
    return handle(this.#core, request, () => this.metadata(request));
  }

  async peek(request: Request): Promise<Masked> {
    const core = this.#core;
    const visit = await core.visit(request);
    const session = await core.sessions.read(visit);

    return core.masked(visit, session?.data);
  }

  async masked(
    request: Request,
  ): Promise<{ masked: Masked; cookies: string[] }> {
    const core = this.#core;
    const visit = await core.visit(request);
    const data = await core.current(visit);

    return { masked: core.masked(visit, data), cookies: visit.handOut() };
  }

  require(request: Request, ...names: string[]): Promise<Outcome> {
    return check(this.#core, request, { privileges: names });
  }

  check(
    request: Request,
    asked: { privileges?: string[]; refresh?: boolean; returnTo?: string } = {},
  ): Promise<Outcome> {
    return check(this.#core, request, asked);
  }

  protect(request: Request, ...names: string[]): Promise<Outcome> {
    return protect(this.#core, request, names);
  }

  guard(request: Request, ...names: string[]): Promise<Outcome> {
    return guard(this.#core, request, names);
  }

  async metadata(request: Request): Promise<Record<string, unknown>> {
    const visit = await this.#core.visit(request);
    const scopes = this.#core.options.resourceScopes ?? [];
    const answer: Record<string, unknown> = {
      resource: visit.resource,
      authorization_servers: [visit.issuerURL],
      bearer_methods_supported: ["header"],
      dpop_signing_alg_values_supported: [
        "ES256",
        "ES384",
        "ES512",
        "PS256",
        "PS384",
        "PS512",
        "RS256",
      ],
    };

    if (scopes.length > 0) answer.scopes_supported = scopes;

    return answer;
  }

  async connection(request: Request): Promise<Connection> {
    const visit = await this.#core.visit(request);
    const held = await this.#core.credentials.read(request);

    return held?.client_id
      ? { connected: true, client_id: held.client_id, issuer: visit.issuerURL }
      : { connected: false, issuer: visit.issuerURL };
  }

  registered(request: Request): Promise<boolean> {
    return this.#core.registered(request);
  }

  disconnect(request: Request): Promise<boolean> {
    return this.#core.disconnect(request);
  }

  async client(request: Request): Promise<Client | undefined> {
    return this.#core.client(await this.#core.visit(request));
  }

  async delegations(request: Request): Promise<Delegations> {
    const core = this.#core;
    const visit = await core.visit(request);
    const client = await core.client(visit);
    const back = core.delegationReturn(visit);

    if (!back) {
      throw new Error(
        "masks: set delegations to the path a provider connection comes back to",
      );
    }

    if (!client)
      throw new MasksError(
        "handshake_required",
        "this app has not shaken hands with masks",
      );

    return new Delegations(client, back);
  }

  async startDelegation(
    request: Request,
    provider: string,
    asked: { prompt?: string; maxAge?: number } = {},
  ): Promise<Response> {
    const core = this.#core;
    const visit = await core.visit(request);
    const masked = core.masked(visit, await core.current(visit));

    if (!masked.signedIn || !masked.subject) {
      return refuse(core, visit, "login_required");
    }

    const started = await (await this.delegations(request)).start({
      provider,
      ...asked,
    });
    const flow = await core.sessions.readFlow(visit);

    flow.delegations = keep(
      flow.delegations,
      started.state,
      pendingFor(started, masked.subject, now() + FLOW_LIFETIME),
    );
    await core.sessions.writeFlow(visit, flow);

    return redirect(started.url, visit.out);
  }

  async finishDelegation(
    request: Request,
  ): Promise<{ connection: DelegatedConnection; cookies: string[] }> {
    const core = this.#core;
    const visit = await core.visit(request);
    const flow = await core.sessions.readFlow(visit);
    const state = visit.url.searchParams.get("state") ?? "";
    const pending = claim(flow.delegations, state);

    if (!pending) {
      throw new DelegationRefused(
        "invalid_state",
        "that connection was not started by this browser, or it expired",
      );
    }

    await core.sessions.writeFlow(visit, flow);

    const masked = core.masked(visit, await core.current(visit));
    const connection = await (await this.delegations(request)).finishFor(
      visit.url.searchParams,
      state,
      pending,
      masked.signedIn ? masked.subject : undefined,
    );

    return { connection, cookies: visit.handOut() };
  }
}
