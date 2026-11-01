import { constantEqual, type Token } from "../client.js";
import type { PendingDelegation } from "../delegations.js";
import { failure, Unavailable } from "../errors.js";
import { random } from "../key.js";
import {
  mergeCookies,
  parseCookies,
  readChunked,
  writeChunked,
} from "./cookies.js";
import { departed } from "./logouts.js";
import type { Sealer } from "./seal.js";
import { keyed, type Store } from "./stores.js";

export interface HeldTokens {
  access_token: string;
  token_type: string;
  refresh_token?: string;
  scope: string;
  expires_at?: number;
}

export interface SessionData {
  issuer?: string;
  tokens?: HeldTokens;
  identity?: Record<string, unknown>;
  signedInAt?: number;
  expiresAt?: number;
}

export interface Pending {
  verifier: string;
  nonce?: string;
  returnTo?: string;
  redirectURI: string;
  resource?: string[];
  until: number;
}

export interface FlowData {
  requests?: Record<string, Pending>;
  handshakes?: Record<string, { until: number; returnTo?: string }>;
  logouts?: Record<string, { until: number }>;
  delegations?: Record<string, PendingDelegation>;
  steppedUp?: { privileges: string[]; at: number };
  restartedAt?: number;
}

export const FLOW_LIFETIME = 3600;

const IDENTITY = [
  "sub",
  "sid",
  "name",
  "preferred_username",
  "email",
  "email_verified",
  "tenant",
  "picture",
  "masks:avatars",
  "org",
  "orgs",
];
const FLOW_LIMIT = 5;
const REFRESH_LEEWAY = 30;
const SESSION_PURPOSE = "session";
const STORED_PURPOSE = "stored session";
const FLOW_PURPOSE = "flow";

export class Visit {
  readonly request: Request;
  readonly url: URL;
  readonly cookies: Map<string, string>;
  readonly out: string[] = [];
  readonly handed = new Set<string>();
  origin = "";
  resource = "";
  secure = false;
  issuerURL = "";
  session?: { id?: string; data: SessionData } | null;
  flow?: FlowData;

  constructor(request: Request) {
    this.request = request;
    this.url = new URL(request.url);
    this.cookies = parseCookies(request.headers.get("cookie"));
  }

  handOut(): string[] {
    const fresh = this.out.filter((line) => !this.handed.has(line));

    for (const line of fresh) this.handed.add(line);

    return fresh;
  }

  setCookies(written: string[]): void {
    this.out.splice(0, Infinity, ...mergeCookies(this.out, written));
  }
}

export interface SessionOptions {
  seal: () => Sealer;
  sessions?: Store;
  store: Store;
  maxAge: number;
}

export class Sessions {
  readonly #options: SessionOptions;

  constructor(options: SessionOptions) {
    this.#options = options;
  }

  async read(
    visit: Visit,
  ): Promise<{ id?: string; data: SessionData } | undefined> {
    if (visit.session !== undefined) return visit.session ?? undefined;

    visit.session = null;

    const sealed = await this.#options.seal().unseal<{
      id?: string;
      data?: SessionData;
      until: number;
    }>(SESSION_PURPOSE, readChunked(visit.cookies, sessionCookie(visit)));

    if (!sealed || !(sealed.until > now())) return undefined;

    const data = sealed.id
      ? await this.#stored(sealed.id)
      : this.#options.sessions
        ? undefined
        : sealed.data;

    if (!data || (data.expiresAt ?? 0) < now()) return undefined;

    visit.session = { id: sealed.id, data };

    if (
      data.issuer !== visit.issuerURL ||
      (await departed(
        this.#options.store,
        visit.issuerURL,
        data.identity ?? {},
        data.signedInAt ?? 0,
      ))
    ) {
      await this.forget(visit);

      return undefined;
    }

    return visit.session;
  }

  async write(visit: Visit, data: SessionData, rotate: boolean): Promise<void> {
    if (visit.session === undefined) await this.read(visit);

    const store = this.#options.sessions;
    const seal = this.#options.seal();
    const until = data.expiresAt ?? now() + this.#options.maxAge;
    const previous = visit.session?.id;
    let sealed: string;

    if (store) {
      const id = rotate || !previous ? random(32) : previous;

      await Promise.all([
        store.set(
          await keyed("session", id),
          await seal.seal(STORED_PURPOSE, { id, data }),
          Math.max(1, until - now()),
        ),
        previous && previous !== id
          ? keyed("session", previous).then((key) => store.delete(key))
          : undefined,
      ]);

      sealed = await seal.seal(SESSION_PURPOSE, { id, until });
      visit.session = { id, data };
    } else {
      sealed = await seal.seal(SESSION_PURPOSE, { data, until });
      visit.session = { data };
    }

    visit.setCookies(
      writeChunked(visit.cookies, sessionCookie(visit), sealed, {
        secure: visit.secure,
        maxAge: Math.max(1, until - now()),
      }),
    );
  }

  async forget(visit: Visit): Promise<void> {
    const id = visit.session?.id;
    const store = this.#options.sessions;

    if (id && store) await store.delete(await keyed("session", id));

    visit.session = null;

    visit.setCookies(
      writeChunked(visit.cookies, sessionCookie(visit), undefined, {
        secure: visit.secure,
      }),
    );
  }

  async readFlow(visit: Visit): Promise<FlowData> {
    if (visit.flow) return visit.flow;

    const sealed = await this.#options
      .seal()
      .unseal<{ flow: FlowData; until: number }>(
        FLOW_PURPOSE,
        visit.cookies.get(flowCookie(visit)),
      );

    visit.flow = sealed && sealed.until > now() ? sealed.flow : {};

    return visit.flow;
  }

  async writeFlow(visit: Visit, flow: FlowData): Promise<void> {
    visit.flow = flow;

    const sealed = await this.#options.seal().seal(FLOW_PURPOSE, {
      flow,
      until: now() + FLOW_LIFETIME,
    });

    visit.setCookies(
      writeChunked(visit.cookies, flowCookie(visit), sealed, {
        secure: visit.secure,
        maxAge: FLOW_LIFETIME,
      }),
    );
  }

  async #stored(id: string): Promise<SessionData | undefined> {
    const store = this.#options.sessions;

    if (!store) return undefined;

    let held: string | undefined;

    try {
      held = await store.get(await keyed("session", id));
    } catch (error) {
      throw new Unavailable(failure("store_unreachable").description, {
        cause: error,
      });
    }

    const opened = await this.#options
      .seal()
      .unseal<{ id: string; data: SessionData }>(STORED_PURPOSE, held);

    return opened?.id === id ? opened.data : undefined;
  }
}

function sessionCookie(visit: Visit): string {
  return visit.secure ? "__Host-masks" : "masks";
}

function flowCookie(visit: Visit): string {
  return visit.secure ? "__Host-masks-flow" : "masks-flow";
}

export function now(): number {
  return Math.floor(Date.now() / 1000);
}

export function fresh(tokens: { expires_at?: number }): boolean {
  return !tokens.expires_at || tokens.expires_at - now() > REFRESH_LEEWAY;
}

export function held(token: Token): HeldTokens {
  return {
    access_token: token.access_token,
    token_type: token.token_type || "Bearer",
    refresh_token: token.refresh_token,
    scope: token.scope ?? "",
    expires_at: token.expires_at,
  };
}

export function pick(claims: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    IDENTITY.filter(
      (name) => claims[name] !== undefined && claims[name] !== null,
    ).map((name) => [name, claims[name]]),
  );
}

export function keep<T extends { until: number }>(
  held: Record<string, T> | undefined,
  id: string,
  entry: T,
): Record<string, T> {
  const live = Object.entries(held ?? {}).filter(
    ([, value]) => value?.until > now(),
  );

  return Object.fromEntries(
    [...live, [id, entry] as [string, T]].slice(-FLOW_LIMIT),
  );
}

export function claim<T extends { until: number }>(
  held: Record<string, T> | undefined,
  id: string,
): T | undefined {
  if (!held || !id) return undefined;

  const match = Object.keys(held).find((key) => constantEqual(key, id));

  if (!match) return undefined;

  const found = held[match];
  delete held[match];

  return found && found.until > now() ? found : undefined;
}
