import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { type NextRequest, NextResponse } from "next/server";
import { replaceCookies } from "./app/cookies.js";
import type { Masked } from "./app/masked.js";
import {
  localPath,
  Masks,
  type MasksOptions,
  PATH_HEADER,
} from "./app/masks.js";
import { ForbiddenError } from "./claims.js";

export { PATH_HEADER };

type RouteContext = { params?: Promise<Record<string, string | string[]>> };

export type MaskedHandler<C extends RouteContext = RouteContext> = (
  request: NextRequest,
  context: C & { masked: Masked },
) => Response | Promise<Response>;

export interface MasksNextOptions extends MasksOptions {
  masks?: Masks;
  protect?: (string | RegExp)[];
}

export interface MasksNext {
  masks: Masks;
  handlers: {
    GET: (request: Request) => Promise<Response>;
    POST: (request: Request) => Promise<Response>;
    DELETE: (request: Request) => Promise<Response>;
  };
  auth: () => Promise<Masked | null>;
  requireAuth: (...privileges: string[]) => Promise<Masked>;
  withMasks: <C extends RouteContext>(
    handler: MaskedHandler<C>,
    ...privileges: string[]
  ) => (request: NextRequest, context: C) => Promise<Response>;
  proxy: (request: Request) => Promise<Response>;
}

export function masksNext(options: MasksNextOptions = {}): MasksNext {
  const masks = Masks.from(options);

  const handle = async (request: Request) =>
    (await masks.handle(request)) ?? new Response("not found", { status: 404 });

  const current = async (): Promise<Request> => {
    const held = await headers();
    const jar = await cookies();
    const path = localPath(held.get(PATH_HEADER)) ?? "/";
    const host = held.get("host") ?? "localhost";
    const forwarded = new Headers();

    for (const [name, value] of held) forwarded.set(name, value);
    forwarded.set(
      "cookie",
      jar
        .getAll()
        .map(({ name, value }) => `${name}=${value}`)
        .join("; "),
    );

    forwarded.set("accept", "text/html");
    forwarded.delete("x-requested-with");

    return new Request(new URL(path, `https://${host}`), {
      headers: forwarded,
    });
  };

  return {
    masks,
    handlers: { GET: handle, POST: handle, DELETE: handle },
    async auth() {
      const masked = await masks.peek(await current());

      return masked.signedIn ? masked : null;
    },

    async requireAuth(...privileges: string[]) {
      const request = await current();
      const outcome = await masks.check(request, {
        privileges,
        refresh: false,
      });

      if (!outcome.response) return outcome.masked;

      const location = outcome.response.headers.get("location");

      if (location) redirect(location);

      throw (
        outcome.error ??
        new ForbiddenError("insufficient_scope", "this request is refused")
      );
    },

    withMasks<C extends RouteContext>(
      handler: MaskedHandler<C>,
      ...privileges: string[]
    ) {
      return async (request: NextRequest, context: C) => {
        const outcome = await masks.guard(request, ...privileges);

        if (outcome.response) return outcome.response;

        const answer = await handler(request, {
          ...(context ?? ({} as C)),
          masked: outcome.masked,
        });

        return withCookies(answer, outcome.cookies);
      };
    },

    async proxy(request: Request) {
      const url = new URL(request.url);
      const forwarded = new Headers(request.headers);

      forwarded.set(PATH_HEADER, `${url.pathname}${url.search}`);

      if (masks.owns(url.pathname)) {
        return NextResponse.next({ request: { headers: forwarded } });
      }

      const guarded = (options.protect ?? []).some((pattern) =>
        typeof pattern === "string"
          ? url.pathname === pattern ||
            url.pathname.startsWith(`${pattern.replace(/\/+$/, "")}/`)
          : pattern.test(url.pathname),
      );

      let written: string[];

      if (guarded) {
        const outcome = await masks.guard(request);

        if (outcome.response) return absolute(outcome.response, url);

        written = outcome.cookies;
      } else {
        try {
          written = (await masks.masked(request)).cookies;
        } catch {
          written = [];
        }
      }

      if (written.length > 0) {
        forwarded.set(
          "cookie",
          replaceCookies(request.headers.get("cookie"), written),
        );
      }

      const response = NextResponse.next({
        request: { headers: forwarded },
      });

      for (const cookie of written) {
        response.headers.append("set-cookie", cookie);
      }

      return response;
    },
  };
}

function absolute(response: Response, url: URL): Response {
  const location = response.headers.get("location");

  if (!location) return response;

  const headers = new Headers(response.headers);

  headers.set("location", new URL(location, url).toString());

  return new Response(response.body, { status: response.status, headers });
}

function withCookies(response: Response, written: string[]): Response {
  if (written.length === 0) return response;

  let answer = response;

  try {
    for (const cookie of written) answer.headers.append("set-cookie", cookie);
  } catch {
    answer = new Response(response.body, response);
    for (const cookie of written) answer.headers.append("set-cookie", cookie);
  }

  return answer;
}

export { Masked } from "./app/masked.js";
export { Masks, type MasksOptions } from "./app/masks.js";
