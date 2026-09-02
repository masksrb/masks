import { createBrowserClient } from "@masks/client";
import { callbackUri, clientId, forget, SCOPE } from "./pairing.js";

export function createApi(boot) {
  const state = $state({
    ready: false,
    identity: null,
    failure: null,
  });

  let client = null;

  const build = () => {
    const held = clientId(boot);

    if (!held) return null;

    client ||= createBrowserClient({
      issuer: boot.issuer,
      clientId: held,
      redirectUri: callbackUri(boot),
      scope: SCOPE,
      resource: boot.resource,
    });

    return client;
  };

  const authorization = async () => {
    const held = build();

    if (!held) throw new Error("this browser has no client registered");

    if (held.expired(30)) await held.refresh();

    return held.authorization();
  };

  return {
    state,

    paired() {
      return Boolean(clientId(boot));
    },

    signedIn() {
      return Boolean(build()?.accessToken());
    },

    async authorize(returnTo) {
      await build().authorize({ returnTo });
    },

    async callback() {
      const answer = await build().callback();

      state.identity = answer.identity;
      state.ready = true;

      return answer;
    },

    signOut() {
      build()?.logout();
      state.identity = null;
    },

    unpair() {
      build()?.logout();
      forget(boot);
      client = null;
    },

    async query(document, variables = {}) {
      const response = await fetch(boot.graphql, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          Authorization: await authorization(),
        },
        body: JSON.stringify({ query: document, variables }),
      });

      const body = await response.json().catch(() => ({}));

      if (response.status === 401 || response.status === 403) {
        throw new Error(body.error_description || body.error || "refused");
      }

      if (body.errors?.length) {
        throw new Error(body.errors.map((one) => one.message).join("; "));
      }

      return body.data;
    },
  };
}
