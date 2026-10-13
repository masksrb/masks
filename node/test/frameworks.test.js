import assert from "node:assert/strict";
import { createServer } from "node:http";
import { after, test } from "node:test";
import express from "express";
import { Hono } from "hono";
import {
  requireAuth as expressRequireAuth,
  masksExpress,
} from "../dist/express.js";
import { requireAuth as honoRequireAuth, masksHono } from "../dist/hono.js";
import { masksNext } from "../dist/next.js";
import { APP, Browser, setup, signIn } from "./browser.js";

const closers = [];

after(async () => {
  for (const close of closers) await close();
});

test("Next.js route handlers run the sign-in", async () => {
  const held = await setup({}, closers);
  const next = masksNext({ masks: held.masks });
  const browser = new Browser(async (request) => {
    const handler = next.handlers[request.method];

    return held.masks.owns(new URL(request.url).pathname)
      ? handler(request)
      : Response.json({ signed_in: (await held.masks.peek(request)).signedIn });
  });

  const done = await signIn({ ...held, browser });
  assert.deepEqual(await done.json(), { signed_in: true });

  const missing = await next.handlers.GET(new Request(`${APP}/auth/nowhere`));
  assert.equal(missing.status, 404);

  const metadata = await next.handlers.GET(
    new Request(`${APP}/.well-known/oauth-protected-resource`),
  );
  assert.equal((await metadata.json()).resource, APP);
});

test("withMasks guards a route handler by session or bearer token", async () => {
  const held = await setup(
    { masks: { privileges: { read: ["catalog:read"] } } },
    closers,
  );
  const next = masksNext({ masks: held.masks });
  await signIn(held);

  const GET = next.withMasks(async (_request, { masked, params }) =>
    Response.json({ subject: masked.subject, id: (await params).id }),
  );
  const answer = await GET(held.browser.request("/api/things/1"), {
    params: Promise.resolve({ id: "1" }),
  });
  assert.deepEqual(await answer.json(), { subject: "ada", id: "1" });

  const READ = next.withMasks(() => Response.json({ ok: true }), "read");
  const refused = await READ(
    new Request(`${APP}/api/things`, {
      headers: { accept: "application/json" },
    }),
    {},
  );
  assert.equal(refused.status, 401);
  assert.match(refused.headers.get("www-authenticate"), /resource_metadata/);

  const token = await held.fake.accessToken("ada", "catalog:read", undefined, {
    aud: APP,
  });
  const allowed = await READ(
    new Request(`${APP}/api/things`, {
      headers: { authorization: `Bearer ${token}` },
    }),
    {},
  );
  assert.deepEqual(await allowed.json(), { ok: true });

  const redirected = next.withMasks(() => Response.redirect(`${APP}/x`, 302));
  held.fake.lifetime = 5;
  await signIn(held);
  held.fake.lifetime = 3600;
  const refreshed = await redirected(held.browser.request("/go"), {});
  assert.equal(refreshed.status, 302);
  assert.ok(refreshed.headers.getSetCookie().length > 0);
});

test("the Next.js proxy refreshes the session and hands it to the page", async () => {
  const held = await setup({}, closers);
  const { proxy } = masksNext({ masks: held.masks, protect: ["/dashboard"] });
  held.fake.lifetime = 5;
  await signIn(held);
  held.fake.lifetime = 3600;

  const response = await proxy(held.browser.request("/reports?year=1"));

  assert.equal(response.headers.get("x-middleware-next"), "1");
  assert.equal(
    response.headers.get("x-middleware-request-x-masks-path"),
    "/reports?year=1",
  );

  const written = response.headers.getSetCookie();
  assert.ok(written.some((line) => line.startsWith("masks=")));

  const forwarded = response.headers.get("x-middleware-request-cookie");
  const sealed = written
    .find((line) => line.startsWith("masks="))
    .split(";")[0]
    .slice("masks=".length);
  assert.ok(forwarded.includes(sealed));

  const signedOut = new Browser(held.browser.handler);
  const guarded = await proxy(signedOut.request("/dashboard/settings"));
  assert.equal(guarded.status, 302);
  assert.equal(
    guarded.headers.get("location"),
    `${APP}/auth?return_to=%2Fdashboard%2Fsettings`,
  );

  const open = await proxy(signedOut.request("/about"));
  assert.equal(open.headers.get("x-middleware-next"), "1");

  const own = await proxy(signedOut.request("/auth/callback?code=x"));
  assert.equal(own.headers.get("x-middleware-next"), "1");
  assert.equal(own.headers.getSetCookie().length, 0);
});

test("a server component without fresh tokens is sent through the refresh route", async () => {
  const held = await setup({}, closers);
  held.fake.lifetime = 5;
  await signIn(held);

  const outcome = await held.masks.check(held.browser.request("/reports"), {
    refresh: false,
  });
  assert.equal(
    outcome.response.headers.get("location"),
    "/auth/refresh?return_to=%2Freports",
  );

  held.fake.lifetime = 3600;
  const back = await held.browser.fetch("/auth/refresh?return_to=%2Freports");
  assert.equal(back.headers.get("location"), "/reports");
  assert.ok(
    (await held.masks.check(held.browser.request("/r"), { refresh: false }))
      .masked,
  );
});

async function serve(handler) {
  const server = createServer(handler);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  closers.push(() => new Promise((resolve) => server.close(resolve)));

  return `http://127.0.0.1:${server.address().port}`;
}

function viaHTTP(base) {
  return async (request) => {
    const url = new URL(request.url);
    const answer = await fetch(`${base}${url.pathname}${url.search}`, {
      method: request.method,
      headers: request.headers,
      body: request.method === "GET" ? undefined : await request.text(),
      redirect: "manual",
    });

    return answer;
  };
}

test("Express mounts the routes, keeps the session, and guards by privilege", async () => {
  const held = await setup(
    {
      masks: {
        privileges: { admin: ["catalog:admin"], read: ["catalog:read"] },
      },
    },
    closers,
  );
  const app = express();

  app.use(express.urlencoded({ extended: false }));
  app.use(masksExpress({ masks: held.masks }));
  app.get("/", (request, response) => {
    response.json({ signed_in: request.masked?.signedIn ?? false });
  });
  app.get("/admin", expressRequireAuth("admin"), (_request, response) => {
    response.json({ admin: true });
  });
  app.get("/api/catalog", expressRequireAuth("read"), (request, response) => {
    response.json({ subject: request.masked.subject });
  });
  app.post("/echo", expressRequireAuth(), (request, response) => {
    response.json({ body: request.body });
  });

  const base = await serve(app);
  const browser = new Browser(viaHTTP(base), APP);
  const done = await signIn({ ...held, browser });

  assert.deepEqual(await done.json(), { signed_in: true });

  const admin = await browser.fetch("/admin");
  assert.equal(admin.status, 302);
  assert.match(admin.headers.get("location"), /privilege=admin/);

  const echoed = await browser.fetch("/echo", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: "a=1",
  });
  assert.deepEqual(await echoed.json(), { body: { a: "1" } });

  const token = await held.fake.accessToken("ada", "catalog:read", undefined, {
    aud: APP,
  });
  const api = await fetch(`${base}/api/catalog`, {
    headers: { authorization: `Bearer ${token}` },
  });
  assert.deepEqual(await api.json(), { subject: "ada" });

  const backchannel = await fetch(`${base}/auth/logout/backchannel`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      logout_token: await held.fake.logoutToken({ aud: "app", sub: "ada" }),
    }),
  });
  assert.equal(backchannel.status, 200);
});

test("Hono mounts the routes, keeps the session, and guards by privilege", async () => {
  const held = await setup(
    { masks: { privileges: { admin: ["catalog:admin"] } } },
    closers,
  );
  const app = new Hono();

  app.use(masksHono({ masks: held.masks }));
  app.get("/", (context) =>
    context.json({ signed_in: context.get("masked").signedIn }),
  );
  app.get("/admin", honoRequireAuth("admin"), (context) =>
    context.json({ admin: true }),
  );
  app.get("/me", honoRequireAuth(), (context) =>
    context.json({ subject: context.get("masked").subject }),
  );

  const browser = new Browser((request) => app.fetch(request), APP);
  const done = await signIn({ ...held, browser });

  assert.deepEqual(await done.json(), { signed_in: true });
  assert.deepEqual(await (await browser.fetch("/me")).json(), {
    subject: "ada",
  });

  const admin = await browser.fetch("/admin", {
    headers: { accept: "application/json" },
  });
  assert.equal(admin.status, 403);
  assert.equal((await admin.json()).error, "privilege_required");

  held.fake.lifetime = 5;
  await signIn({ ...held, browser });
  held.fake.lifetime = 3600;

  const refreshed = await browser.fetch("/");
  assert.ok(
    refreshed.headers.getSetCookie().some((line) => line.startsWith("masks=")),
  );
});

test("a guarded Express or Hono request refreshes an expired session once and sets its cookie once", async () => {
  for (const framework of ["express", "hono"]) {
    const held = await setup({}, closers);
    let handler;

    if (framework === "express") {
      const app = express();

      app.use(masksExpress({ masks: held.masks }));
      app.get("/me", expressRequireAuth(), (request, response) => {
        response.json({ subject: request.masked.subject });
      });
      handler = viaHTTP(await serve(app));
    } else {
      const app = new Hono();

      app.use(masksHono({ masks: held.masks }));
      app.get("/me", honoRequireAuth(), (context) =>
        context.json({ subject: context.get("masked").subject }),
      );
      handler = (request) => app.fetch(request);
    }

    const browser = new Browser(handler, APP);

    held.fake.lifetime = 5;
    await signIn({ ...held, browser });
    held.fake.lifetime = 3600;

    const before = held.fake.tokenRequests.length;
    const me = await browser.fetch("/me");
    const sessions = me.headers
      .getSetCookie()
      .filter((line) => line.startsWith("masks="));

    assert.deepEqual(await me.json(), { subject: "ada" }, framework);
    assert.equal(sessions.length, 1, framework);
    assert.deepEqual(
      held.fake.tokenRequests.slice(before),
      ["refresh_token"],
      framework,
    );
  }
});

test("Express streams the avatar, and cuts off one larger than the app accepts", async () => {
  const held = await setup({ masks: { avatars: { bytes: 16 } } }, closers);
  const app = express();

  app.use(masksExpress({ masks: held.masks }));

  const browser = new Browser(viaHTTP(await serve(app)), APP);

  await signIn({ ...held, browser });

  const photo = await browser.fetch("/auth/avatar");
  assert.equal(photo.status, 200);
  assert.equal(await photo.text(), "png-bytes");

  held.fake.avatarBody = Buffer.alloc(4096);
  await assert.rejects(async () => {
    const large = await browser.fetch("/auth/avatar");

    await large.arrayBuffer();
  });
});

test("a Hono refusal reaches app.onError, and requireAuth needs the middleware", async () => {
  const held = await setup({}, closers);
  const app = new Hono();

  app.onError((error, context) =>
    context.json({ status: error.getResponse?.().status }, 418),
  );
  app.get("/bare", honoRequireAuth(), (context) => context.text("never"));
  app.use(masksHono({ masks: held.masks }));
  app.get("/me", honoRequireAuth(), (context) => context.text("never"));

  const refused = await app.fetch(
    new Request(`${APP}/me`, { headers: { accept: "application/json" } }),
  );
  assert.equal(refused.status, 418);
  assert.deepEqual(await refused.json(), { status: 401 });

  const bare = await app.fetch(new Request(`${APP}/bare`));
  assert.equal(bare.status, 418);
});

test("Express requireAuth without masksExpress is an error", async () => {
  const app = express();

  app.get("/me", expressRequireAuth(), (_request, response) =>
    response.send("never"),
  );
  app.use((error, _request, response, _next) =>
    response.status(500).json({ message: error.message }),
  );

  const server = app.listen(0);
  closers.push(() => new Promise((resolve) => server.close(resolve)));
  const answer = await fetch(`http://127.0.0.1:${server.address().port}/me`);

  assert.equal(answer.status, 500);
  assert.match(
    (await answer.json()).message,
    /masksExpress before requireAuth/,
  );
});
