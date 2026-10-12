import { Masks, memoryCredentials } from "../dist/index.js";
import { Fake } from "./fake.js";

export const APP = "http://app.localhost:3000";
export const SECRET = "a-test-secret-that-is-long-enough-123456";

export class Browser {
  jar = new Map();
  history = [];

  constructor(handler, origin = APP) {
    this.handler = handler;
    this.origin = origin;
  }

  cookieHeader() {
    return [...this.jar].map(([name, value]) => `${name}=${value}`).join("; ");
  }

  keep(response) {
    for (const line of response.headers.getSetCookie()) {
      const [pair] = line.split(";");
      const at = pair.indexOf("=");
      const name = pair.slice(0, at);
      const value = pair.slice(at + 1);

      if (/Max-Age=0(;|$)/.test(line)) this.jar.delete(name);
      else this.jar.set(name, value);
    }
  }

  request(path, init = {}) {
    const url = new URL(path, this.origin);
    const headers = new Headers(init.headers ?? {});

    if (!headers.has("accept")) headers.set("accept", "text/html");
    if (this.jar.size > 0) headers.set("cookie", this.cookieHeader());

    return new Request(url, { ...init, headers });
  }

  async fetch(path, init = {}) {
    const response = await this.handler(this.request(path, init));
    this.keep(response);
    this.history.push([init.method ?? "GET", path, response.status]);

    return response;
  }

  async follow(path, init = {}, limit = 10) {
    let response = await this.fetch(path, init);

    for (let hop = 0; hop < limit; hop++) {
      const location = response.headers.get("location");

      if (!location || response.status < 300 || response.status >= 400) {
        return response;
      }

      const next = new URL(location, this.origin);

      if (next.origin !== this.origin) return response;

      response = await this.fetch(`${next.pathname}${next.search}`);
    }

    return response;
  }
}

export async function setup(options = {}, closers = []) {
  const fake = await Fake.start();
  closers.push(fake.close);

  const credentials =
    options.credentials ??
    (options.connected === false
      ? memoryCredentials()
      : await registered(fake));

  const masks = new Masks({
    issuer: fake.url,
    resource: options.resource ?? APP,
    secret: SECRET,
    credentials,
    name: "Catalog",
    ...options.masks,
  });

  const handler = async (request) =>
    (await masks.handle(request)) ??
    (await (options.app ?? page)(masks, request));

  return {
    fake,
    masks,
    credentials,
    browser: new Browser(handler, options.resource ?? APP),
  };
}

async function registered(fake) {
  fake.add("app", { secret: "s3cret", method: "client_secret_basic" });

  return memoryCredentials({ client_id: "app", client_secret: "s3cret" });
}

async function page(masks, request) {
  const masked = await masks.peek(request);

  return Response.json({
    path: new URL(request.url).pathname,
    signed_in: masked.signedIn,
  });
}

export async function signIn(setup, options = {}, path = "/auth") {
  const { fake, browser } = setup;
  const started = await browser.follow(path);
  const location = started.headers.get("location");

  if (!location?.startsWith(fake.url)) {
    throw new Error(
      `expected a redirect to masks, got ${started.status} ${location}`,
    );
  }

  const back = new URL(fake.authorize(location, options));

  return browser.follow(`${back.pathname}${back.search}`);
}
