# @masks/node

`@masks/node` connects a server to masks. It gets tokens as a client and checks
them as an API. It runs on Node 20 and later, in Next.js route handlers and
middleware on the edge runtime, on Bun, and on Deno, since it uses only `fetch`
and Web Crypto.

```sh
npm install @masks/node
```

| Covers | |
| --- | --- |
| Discovery | The issuer's document, checked against the address it was fetched from. |
| Registration | Redeeming an initial access token, then reading, updating, and deleting the client. |
| Client authentication | `client_secret_basic`, `client_secret_post`, `private_key_jwt`, and `none`. |
| Grants | Client credentials, refresh tokens, and the device flow. |
| DPoP | Tokens held to a key, and proofs on every request a signed `fetch` sends. |
| Revocation | Access and refresh tokens. |
| Checking tokens | `at+jwt` access tokens, including DPoP-bound ones, from a `Request` or a Node request. |

Signing people in through a browser is left to
[openid-client](https://github.com/panva/openid-client) or
[Auth.js](https://authjs.dev). See
[Other languages](https://masks.pages.dev/guides/other-languages/#node).

## A server signs in as itself

A server keeps two P-256 keys. One signs its client assertions and the other
holds its tokens, so a token copied off the server is useless without the key.

```ts
import { Client, Issuer, Key } from "@masks/node";

const key = await Key.generate();
const dpop = await Key.generate();

const saved = JSON.stringify({ key, dpop });
```

`JSON.stringify` writes the private keys, so keep them in a secret store or a
file only the service can read. `Key.import` reads one back, and `key.jwks()` is
the public half to register.

```ts
const issuer = await Issuer.discover("https://auth.example.com");

const client = new Client({ issuer, id: clientId, key, dpop });

const asked = { scope: ["files:read"], resource: ["https://files.example.com"] };
const token = await client.clientCredentials(asked);
```

`client.method` is `client_secret_basic` when `secret` is set and
`private_key_jwt` when `key` is, unless `method` names another. When `dpop` is
set, a token that comes back unbound is refused.

## Enrolling with an initial access token

A manager approves the client in masks, and masks gives out an initial access
token for it. The server redeems the token once and keeps what comes back.

```ts
const registration = await issuer.register({}, initialAccessToken);
const client = issuer.client(registration, key, dpop);
```

`readRegistration`, `updateRegistration`, and `deleteRegistration` manage the
client with its registration access token. They send that token only to the
issuer's own origin.

## Calling an API

`client.fetch` returns a `fetch` that fetches and reuses tokens and signs each
request. It sends tokens only to the origins it is given. A redirect comes back
to the caller, and following it through the same `fetch` checks its origin
again.

```ts
const source = client.credentialsSource(asked);
const api = client.fetch(source, ["https://files.example.com"]);

const response = await api("https://files.example.com/files");
```

A held token goes out as `Authorization: DPoP` with a fresh proof, and a server
that asks for a DPoP nonce is answered once. Concurrent callers share one token
request. `client.refreshSource` renews a token with its refresh token and hands
each rotated token to a callback to be saved.

## The device flow

A server with no browser shows a code that a person approves on another device.

```ts
const device = await client.deviceAuthorization({ scope: ["openid", "offline_access"] });
console.log(`Open ${device.verification_uri} and enter ${device.user_code}`);

const token = await client.awaitDevice(device, { signal: AbortSignal.timeout(600_000) });
```

`awaitDevice` polls at the interval masks names, slows down when asked, and
stops when the code expires or the signal aborts.

## Checking access tokens

```ts
import { hasScope, Verifier } from "@masks/node";

const verifier = new Verifier(issuer, "https://files.example.com", {
  publicURL: "https://files.example.com",
});
```

In a Next.js route handler:

```ts
export async function GET(request: Request) {
  try {
    const claims = await verifier.authenticate(request);

    if (!hasScope(claims, "files:read")) return new Response(null, { status: 403 });

    return Response.json({ files: await filesFor(claims.sub) });
  } catch (error) {
    return verifier.challenge(error);
  }
}
```

In a Node `http` server, or Express:

```ts
try {
  const claims = await verifier.authenticateNode(request);
} catch (error) {
  response.writeHead(401, { "www-authenticate": verifier.challengeHeaders(error) });
  response.end();
}
```

The verifier checks the signature against the issuer's published keys, the
`at+jwt` type, the issuer, the audience, and the expiry. A DPoP-bound token
needs a proof signed by its key, made for this method and URL, made in the last
minute, and not seen before. A failure is an `InvalidTokenError`.

Set `publicURL` when a proxy sits in front of the API, since a proof names the
address the client used. The replay cache lives in the process, so each
instance of a scaled-out API keeps its own.

## Plain HTTP

Every URL is `https`, except on this machine: `localhost`, a `.localhost` name,
or a loopback address. `allowPlainHTTP: true` in the options to
`Issuer.discover` lifts that for a private network.
