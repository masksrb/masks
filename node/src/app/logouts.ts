import { UnavailableError } from "../errors.js";
import type { LogoutToken } from "../idtoken.js";
import type { ReplayStore } from "../replay.js";
import type { LogoutStore } from "./stores.js";

const LOGOUT_MEMORY = 3600;

export async function firstLogout(
  replay: ReplayStore,
  issuer: string,
  logout: LogoutToken,
): Promise<boolean> {
  try {
    return (
      (await replay.first(`${issuer} logout ${logout.jti}`, LOGOUT_MEMORY)) ===
      true
    );
  } catch (error) {
    throw new UnavailableError("the replay store could not be reached", {
      cause: error,
    });
  }
}

export async function recordLogout(
  logouts: LogoutStore,
  issuer: string,
  logout: LogoutToken,
  lifetime: number,
): Promise<void> {
  const key = logout.sid
    ? `sid ${logout.sid}`
    : logout.sub && `sub ${logout.sub}`;

  if (!key) return;

  const at = Math.max(Number(logout.iat) || 0, Math.floor(Date.now() / 1000));

  await logouts.record(`${issuer} ${key}`, at, lifetime);
}

export async function loggedOut(
  logouts: LogoutStore,
  issuer: string,
  held: { sid?: unknown; sub?: unknown },
  since: number,
): Promise<boolean> {
  const ended = await Promise.all(
    (["sid", "sub"] as const)
      .filter((name) => typeof held[name] === "string" && held[name] !== "")
      .map((name) => logouts.since(`${issuer} ${name} ${held[name]}`)),
  );

  return ended.some((at) => at !== undefined && at >= since);
}
