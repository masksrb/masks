import { translator } from "./copy.js";

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
  const url = options.url ?? "/login";

  let auth = $state(initial);
  let loading = $state(false);
  let failed = $state(false);

  async function dispatch(method, body) {
    loading = true;
    failed = false;

    try {
      auth = await send(
        url,
        method,
        auth.rid ? { rid: auth.rid, ...body } : body,
      );

      if (auth.redirectTo) {
        window.location.assign(auth.redirectTo);
      }

      return auth;
    } catch {
      failed = true;

      return auth;
    } finally {
      loading = false;
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
  };
}
