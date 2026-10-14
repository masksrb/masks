import { wantsJSON } from "./requests.js";

export function headersWith(
  cookies: string[],
  extra: Record<string, string> = {},
): Headers {
  const headers = new Headers(extra);

  for (const cookie of cookies) headers.append("set-cookie", cookie);

  return headers;
}

export function redirect(
  location: string,
  cookies: string[],
  status = 302,
): Response {
  return new Response(null, {
    status,
    headers: headersWith(cookies, { location, "cache-control": "no-store" }),
  });
}

export function json(
  status: number,
  body: unknown,
  cookies: string[],
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: headersWith(cookies, {
      "content-type": "application/json",
      "cache-control": "no-store",
      ...extra,
    }),
  });
}

export function text(
  status: number,
  body: string,
  cookies: string[],
): Response {
  return new Response(body, {
    status,
    headers: headersWith(cookies, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    }),
  });
}

export function errorResponse(
  request: Request,
  status: number,
  code: string,
  description: string,
  cookies: string[] = [],
  asJSON = false,
): Response {
  if (asJSON || wantsJSON(request)) {
    return json(
      status,
      { error: code, error_description: description },
      cookies,
    );
  }

  return text(status, `${code}: ${description}`, cookies);
}

export function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (found) => `&#${found.charCodeAt(0)};`);
}

export function page(
  title: string,
  body: string,
  cookies: string[],
  formTargets: string[],
): Response {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHTML(title)}</title><style>body{font-family:system-ui,sans-serif;max-width:36rem;margin:4rem auto;padding:0 1rem;line-height:1.5}form{display:inline-block;margin-right:.5rem}</style></head><body><h1>${escapeHTML(title)}</h1>${body}</body></html>`,
    {
      status: 200,
      headers: headersWith(cookies, {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "content-security-policy": `default-src 'none'; style-src 'unsafe-inline'; form-action ${["'self'", ...formTargets].join(" ")}; frame-ancestors 'none'`,
        "x-frame-options": "DENY",
        "x-content-type-options": "nosniff",
      }),
    },
  );
}

export function signOutPage(
  action: string,
  carried: Record<string, string>,
  cookies: string[],
): Response {
  const hidden = Object.entries(carried)
    .map(
      ([name, value]) =>
        `<input type="hidden" name="${escapeHTML(name)}" value="${escapeHTML(value)}">`,
    )
    .join("");

  return page(
    "Sign out",
    `<p>Select Sign out to finish signing out.</p><form method="post" action="${escapeHTML(action)}">${hidden}<button type="submit">Sign out</button></form>`,
    cookies,
    [],
  );
}

export function withCookies(response: Response, cookies: string[]): Response {
  if (cookies.length === 0) return response;

  try {
    for (const cookie of cookies) response.headers.append("set-cookie", cookie);

    return response;
  } catch {
    const copy = new Response(response.body, response);

    for (const cookie of cookies) copy.headers.append("set-cookie", cookie);

    return copy;
  }
}
