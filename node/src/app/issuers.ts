import { Issuer } from "../issuer.js";
import { remember } from "./stores.js";

const LIFETIME = 3600_000;
const FIRST_BACKOFF = 5_000;
const LONGEST_BACKOFF = 60_000;
const REMEMBERED = 1_000;

type Options = Parameters<typeof Issuer.discover>[1];

interface Held {
  good?: Issuer;
  at: number;
  pending?: Promise<Issuer>;
  failure?: unknown;
  retryAt: number;
  backoff: number;
}

export class IssuerCache {
  readonly #held = new Map<string, Held>();
  readonly #options: () => Options;

  constructor(options: () => Options) {
    this.#options = options;
  }

  async get(url: string): Promise<Issuer> {
    const held = this.#entry(url);
    const now = Date.now();

    if (held.good) {
      if (now - held.at >= LIFETIME && !held.pending && now >= held.retryAt) {
        this.#discover(url, held).catch(() => {});
      }

      return held.good;
    }

    if (held.pending) return held.pending;
    if (held.failure !== undefined && now < held.retryAt) throw held.failure;

    return this.#discover(url, held);
  }

  #entry(url: string): Held {
    const found = this.#held.get(url);

    if (found) return found;

    const created: Held = { at: 0, retryAt: 0, backoff: FIRST_BACKOFF };

    remember(this.#held, url, created, REMEMBERED);

    return created;
  }

  #discover(url: string, held: Held): Promise<Issuer> {
    const pending = Issuer.discover(url, this.#options()).then(
      (issuer) => {
        issuer.keepKeysOf(held.good);
        Object.assign(held, {
          good: issuer,
          at: Date.now(),
          pending: undefined,
          failure: undefined,
          retryAt: 0,
          backoff: FIRST_BACKOFF,
        });

        return issuer;
      },
      (error: unknown) => {
        Object.assign(held, {
          pending: undefined,
          failure: error,
          retryAt: Date.now() + held.backoff,
          backoff: Math.min(held.backoff * 2, LONGEST_BACKOFF),
        });

        throw error;
      },
    );

    held.pending = pending;

    return pending;
  }
}
