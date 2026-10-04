import { translator } from "./copy.js";
import { root } from "./root.js";

const UNNAVIGABLE = new Set([
  "javascript:",
  "data:",
  "vbscript:",
  "file:",
  "blob:",
]);

const navigable = (location) => {
  if (typeof location !== "string" || location === "") return false;

  try {
    return !UNNAVIGABLE.has(new URL(location, window.location.href).protocol);
  } catch {
    return false;
  }
};

const csrf = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? "";

async function send(url, method, body) {
  const response = await fetch(url, {
    method,
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrf(),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok && response.status !== 422 && response.status !== 429) {
    throw new Error(`login failed: ${response.status}`);
  }

  return response.json();
}

export function createLogin(initial, options = {}) {
  const url = options.url ?? `${root}/login`;

  let auth = $state(initial);
  let loading = $state(false);
  let failed = $state(false);
  let last = null;

  async function dispatch(method, body, { quiet = false } = {}) {
    if (quiet && loading) return auth;

    if (!quiet) {
      loading = true;
      failed = false;
      last = [method, body];
    }

    try {
      const held = await send(
        url,
        method,
        auth.rid ? { rid: auth.rid, ...body } : body,
      );

      if (quiet && loading) return auth;

      auth = held;

      if (navigable(auth.redirectTo)) {
        window.location.assign(auth.redirectTo);
      }

      return auth;
    } catch {
      if (!quiet) failed = true;

      return auth;
    } finally {
      if (!quiet) loading = false;
    }
  }

  const t = translator(() => auth.copy);

  return {
    t,
    get auth() {
      return auth;
    },
    get loading() {
      return loading;
    },
    get failed() {
      return failed;
    },
    get prompt() {
      return auth.prompt;
    },
    get backupCodes() {
      return auth.backupCodes;
    },
    get rememberable() {
      return auth.rememberable;
    },
    get consent() {
      return auth.consent;
    },
    get client() {
      return auth.client;
    },
    get actor() {
      return auth.actor;
    },
    warns(key) {
      return (auth.warnings ?? []).includes(key);
    },
    submit(event, updates = {}) {
      return dispatch("POST", { event, ...updates });
    },
    startOver() {
      return dispatch("DELETE");
    },
    poll(event, updates = {}) {
      return dispatch("POST", { event, ...updates }, { quiet: true });
    },
    retry() {
      return last ? dispatch(...last) : Promise.resolve(auth);
    },
  };
}
