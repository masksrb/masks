import { withCookies } from "./responses.js";

const SIZES = [32, 64, 128, 256, 512];
const MOST = 5 * 1024 * 1024;

export interface AvatarsLimit {
  bytes?: number;
}

export interface AvatarRequest {
  photo: string;
  issuer: string;
  authorization: string;
  size: string | null;
  fetch: typeof fetch;
  limit?: AvatarsLimit;
}

export async function avatarResponse(
  asked: AvatarRequest,
  cookies: string[],
): Promise<Response> {
  if (!asked.photo.startsWith(`${asked.issuer}/`)) return missing(cookies);

  const target = new URL(asked.photo);

  if (asked.size !== null) {
    const wanted = Number.parseInt(asked.size, 10) || 0;
    target.searchParams.set(
      "size",
      String(
        SIZES.find((allowed) => allowed >= wanted) ?? SIZES[SIZES.length - 1],
      ),
    );
  }

  let answer: Response;

  try {
    answer = await asked.fetch(target, {
      headers: { authorization: asked.authorization, accept: "image/*" },
      redirect: "manual",
    });
  } catch {
    return plain(502, cookies);
  }

  if (answer.status >= 300 && answer.status < 400) {
    await answer.body?.cancel();

    const location = answer.headers.get("location");

    if (!location) return missing(cookies);

    const next = new URL(location, target);

    if (
      next.protocol !== "https:" &&
      next.origin !== new URL(asked.issuer).origin
    ) {
      return missing(cookies);
    }

    return withCookies(
      new Response(null, {
        status: 302,
        headers: {
          location: next.toString(),
          "cache-control": "private, max-age=300",
        },
      }),
      cookies,
    );
  }

  const type = answer.headers.get("content-type") ?? "";

  if (
    answer.status !== 200 ||
    !/^image\/[a-z0-9.+-]+$/i.test(type.split(";")[0]?.trim() ?? "") ||
    !answer.body
  ) {
    await answer.body?.cancel();
    return missing(cookies);
  }

  const most = asked.limit?.bytes ?? MOST;

  if (Number(answer.headers.get("content-length") ?? "0") > most) {
    await answer.body.cancel();
    return plain(502, cookies);
  }

  let seen = 0;
  const capped = answer.body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        seen += chunk.byteLength;

        if (seen > most) {
          controller.error(
            new Error("masks: that avatar is larger than this app accepts"),
          );
          return;
        }

        controller.enqueue(chunk);
      },
    }),
  );

  return withCookies(
    new Response(capped, {
      status: 200,
      headers: {
        "content-type": type,
        "cache-control": "private, max-age=300",
        "content-security-policy": "default-src 'none'; sandbox",
        "x-content-type-options": "nosniff",
        "content-disposition": "inline",
      },
    }),
    cookies,
  );
}

function missing(cookies: string[]): Response {
  return plain(404, cookies);
}

function plain(status: number, cookies: string[]): Response {
  return withCookies(
    new Response(null, { status, headers: { "cache-control": "no-store" } }),
    cookies,
  );
}
