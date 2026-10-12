const CHUNK = 3800;
const MOST_CHUNKS = 8;

export interface CookieOptions {
  secure: boolean;
  maxAge?: number;
}

export function parseCookies(
  header: string | null | undefined,
): Map<string, string> {
  const held = new Map<string, string>();

  for (const part of (header ?? "").split(";")) {
    const at = part.indexOf("=");
    if (at < 0) continue;

    const name = part.slice(0, at).trim();
    const value = part.slice(at + 1).trim();

    if (name && !held.has(name)) held.set(name, value);
  }

  return held;
}

export function serialize(
  name: string,
  value: string,
  options: CookieOptions,
): string {
  const parts = [`${name}=${value}`, "Path=/", "HttpOnly", "SameSite=Lax"];

  if (options.secure) parts.push("Secure");
  if (options.maxAge !== undefined) {
    parts.push(`Max-Age=${Math.max(0, Math.floor(options.maxAge))}`);
  }

  return parts.join("; ");
}

export function readChunked(
  cookies: Map<string, string>,
  name: string,
): string | undefined {
  const whole = cookies.get(name);
  if (whole !== undefined) return whole;

  let joined = "";

  for (let index = 0; index < MOST_CHUNKS; index++) {
    const part = cookies.get(`${name}.${index}`);
    if (part === undefined) break;

    joined += part;
  }

  return joined === "" ? undefined : joined;
}

export function writeChunked(
  cookies: Map<string, string>,
  name: string,
  value: string | undefined,
  options: CookieOptions,
): string[] {
  const written: string[] = [];
  const kept = new Set<string>();

  if (value !== undefined) {
    if (value.length <= CHUNK) {
      written.push(serialize(name, value, options));
      kept.add(name);
    } else {
      const count = Math.ceil(value.length / CHUNK);

      if (count > MOST_CHUNKS) {
        throw new Error(
          "masks: this session is too large for a cookie; use a session store",
        );
      }

      for (let index = 0; index < count; index++) {
        const chunk = `${name}.${index}`;
        written.push(
          serialize(
            chunk,
            value.slice(index * CHUNK, (index + 1) * CHUNK),
            options,
          ),
        );
        kept.add(chunk);
      }
    }
  }

  for (const held of cookies.keys()) {
    if ((held === name || held.startsWith(`${name}.`)) && !kept.has(held)) {
      written.push(serialize(held, "", { ...options, maxAge: 0 }));
    }
  }

  return written;
}

export function replaceCookies(
  header: string | null | undefined,
  written: string[],
): string {
  const held = parseCookies(header);

  for (const line of written) {
    const pair = line.split(";")[0] ?? "";
    const at = pair.indexOf("=");
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);

    if (/Max-Age=0(;|$)/.test(line)) held.delete(name);
    else held.set(name, value);
  }

  return [...held].map(([name, value]) => `${name}=${value}`).join("; ");
}
