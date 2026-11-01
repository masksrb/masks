import { failure, Unavailable } from "../errors.js";
import type { LogoutToken } from "../idtoken.js";
import { keyed, type Store } from "./stores.js";

const LOGOUT_MEMORY = 600;
const LOGOUT_LEEWAY = 120;

export async function acceptLogout(
  store: Store,
  issuer: string,
  logout: LogoutToken,
  lifetime: number,
): Promise<boolean> {
  const once = await keyed("logout", issuer, String(logout.jti ?? ""));
  const memory = Math.max(
    LOGOUT_MEMORY,
    logout.exp - Math.floor(Date.now() / 1000) + LOGOUT_LEEWAY,
  );

  try {
    if ((await store.add(once, "1", memory)) !== true) return false;
  } catch (error) {
    throw unreachable(error);
  }

  const [kind, value] = logout.sid
    ? ["sid", logout.sid]
    : ["sub", String(logout.sub ?? "")];
  const at = Math.max(Number(logout.iat) || 0, Math.floor(Date.now() / 1000));

  try {
    await store.set(
      await keyed("departed", issuer, kind, value),
      String(at),
      lifetime,
    );
  } catch (error) {
    try {
      await store.delete(once);
    } catch {}

    throw unreachable(error);
  }

  return true;
}

export async function departed(
  store: Store,
  issuer: string,
  held: { sid?: unknown; sub?: unknown },
  since: number,
): Promise<boolean> {
  let ended: (string | undefined)[];

  try {
    ended = await Promise.all(
      (["sid", "sub"] as const)
        .filter((name) => typeof held[name] === "string" && held[name] !== "")
        .map(async (name) =>
          store.get(
            await keyed("departed", issuer, name, held[name] as string),
          ),
        ),
    );
  } catch (error) {
    throw unreachable(error);
  }

  return ended.some((at) => at !== undefined && Number(at) >= since);
}

function unreachable(error: unknown): Unavailable {
  return new Unavailable(failure("store_unreachable").description, {
    cause: error,
  });
}
