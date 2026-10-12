const SWEEP_EVERY = 1000;

export interface ReplayStore {
  first(key: string, expiresIn: number): boolean | Promise<boolean>;
}

export class MemoryReplayStore implements ReplayStore {
  readonly #held = new Map<string, number>();
  #swept = 0;

  first(key: string, expiresIn: number): boolean {
    const now = Date.now();

    if (now - this.#swept > SWEEP_EVERY) {
      this.#swept = now;

      for (const [held, until] of this.#held) {
        if (until < now) this.#held.delete(held);
      }
    }

    const until = this.#held.get(key);

    if (until !== undefined && until >= now) return false;

    this.#held.set(key, now + expiresIn * 1000);

    return true;
  }
}
