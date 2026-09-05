import { createBrowserClient } from "@masks/client";
import { callbackUri, clientId, forget, SCOPE } from "./pairing.js";

function detach(variables) {
  const files = new Map();

  const walk = (value, path) => {
    if (value instanceof Blob) {
      files.set(path, value);
      return null;
    }

    if (Array.isArray(value))
      return value.map((one, at) => walk(one, `${path}.${at}`));

    if (value?.constructor === Object) {
      return Object.fromEntries(
        Object.entries(value).map(([key, one]) => [
          key,
          walk(one, `${path}.${key}`),
        ]),
      );
    }

    return value;
  };

  return { held: walk(variables, "variables"), files };
}

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

    async signOut() {
      const held = build();

      state.identity = null;

      if (!held) return null;

      const idToken = held.tokens()?.id_token;
      const document = await held.discover().catch(() => null);

      held.logout();

      if (!document?.end_session_endpoint) return null;

      const query = new URLSearchParams({
        client_id: clientId(boot),
        post_logout_redirect_uri: `${location.origin}${boot.root}`,
      });

      if (idToken) query.set("id_token_hint", idToken);

      return `${document.end_session_endpoint}?${query}`;
    },

    unpair() {
      build()?.logout();
      forget(boot);
      client = null;
    },

    async query(document, variables = {}) {
      const { held, files } = detach(variables);
      const headers = {
        Accept: "application/json",
        Authorization: await authorization(),
      };
      let sent;

      if (files.size) {
        sent = new FormData();

        sent.append(
          "operations",
          JSON.stringify({ query: document, variables: held }),
        );
        sent.append(
          "map",
          JSON.stringify(
            Object.fromEntries(
              [...files.keys()].map((path, at) => [at, [path]]),
            ),
          ),
        );

        [...files.values()].forEach((file, at) => {
          sent.append(String(at), file);
        });
      } else {
        headers["Content-Type"] = "application/json";
        sent = JSON.stringify({ query: document, variables });
      }

      const response = await fetch(boot.graphql, {
        method: "POST",
        headers,
        body: sent,
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
