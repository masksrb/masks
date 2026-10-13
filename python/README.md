# masks for Python

`masks-client` connects a Python web app, service, or machine to masks. It signs
people in, gets tokens as a client, and checks them as an API. Every call has a synchronous form and an
`async` one.

```sh
pip install "masks-client @ git+https://github.com/masksrb/masks@python-v0.1.0#subdirectory=python"
```

The package installs from its release tag and is not on PyPI yet. It imports as
`masks` and needs Python 3.10 or later.

| Covers | |
| --- | --- |
| Web apps | FastAPI, Django, and Flask: the handshake, sign-in, sessions, and privileges. |
| Discovery | The issuer's document, checked against the address it was fetched from. |
| Registration | Redeeming an initial access token, then reading, updating, and deleting the client. |
| Enrollment | An app asking for initial access tokens for its own machines, and unenrolling them. |
| Client authentication | `client_secret_basic`, `client_secret_post`, `private_key_jwt`, and `none`. |
| Grants | Client credentials, refresh tokens, the device flow, and token exchange. |
| DPoP | Tokens held to a key, and proofs on every request an `httpx` client sends. |
| Revocation | Access and refresh tokens. |
| Introspection | Asking the issuer whether a token is still active. |
| Checking tokens | `at+jwt` access tokens, including DPoP-bound ones, in any framework or as ASGI middleware. |

See [Python apps](https://masks.pages.dev/reference/python/) for the walkthrough and
[masks-client](https://masks.pages.dev/reference/python/client/) for every setting and
call.

## Signing people in to a web app

`masks.fastapi`, `masks.django`, and `masks.flask` add sign-in to a web app.
Install the extra for your framework, such as `masks-client[fastapi]`.

```python
import os
from typing import Annotated

from fastapi import Depends, FastAPI
from masks.fastapi import Config, Masks, Person

auth = Masks(Config(
    issuer=os.environ["MASKS_ISSUER"],
    resource="https://app.example.com",
    name="Catalog",
    secret=os.environ["SESSION_SECRET"],
))

app = FastAPI()
auth.install(app)


@app.get("/settings")
async def settings(person: Annotated[Person, Depends(auth.require())]):
    return {"name": person.name}
```

To connect the app:

1. Set `MASKS_ISSUER` to your masks tenant.
2. Start the app.
3. Open `/auth/handshake` and approve the app in masks.

People then sign in at `/auth` and sign out at `/auth/logout`. The session is a
sealed cookie. Django and Flask work the same way. See
[Django](https://masks.pages.dev/reference/python/django/) and
[Flask](https://masks.pages.dev/reference/python/flask/).

An app that runs as several processes sets `store` to one they share, such as
`masks.web.RedisStore`. The processes then refresh each token once, and a
logout from masks reaches all of them.

## The handshake

The handshake connects an app to masks with no client ID or secret to copy.

1. The browser goes to masks, where a manager approves the app.
2. masks sends the browser back with a one-time token.
3. The app redeems the token with masks directly and saves the client it gets
   back. The secret never passes through the browser.

The web integrations run the handshake at `/auth/handshake` and save the client
in `masks.json`. Any other app uses `masks.Handshake`.

```python
handshake = masks.Handshake(
    issuer,
    name="Catalog",
    resource="https://app.example.com",
    redirect_uris=["https://app.example.com/callback"],
    return_to="https://app.example.com/handshake/callback",
)
started = handshake.start()
```

Keep `started.state` in the browser's session and send the browser to
`started.url`. When masks sends it back to `return_to`, finish the handshake:

```python
registration = handshake.complete(request.query_params, state)
```

`complete` checks the state and the issuer, then registers the client. Save
`registration.client_id` and `registration.client_secret`. Every address in a
handshake must share the resource's origin.

## The code flow

The code flow signs a person in through masks with PKCE. The web integrations
run it at `/auth`. Any other app uses the client.

```python
client = masks.Client(issuer, client_id, secret=client_secret)
started = client.start("https://app.example.com/callback", resource=["https://app.example.com"])
session["sign_in"] = started.to_dict()
```

Send the browser to `started.url`. When masks sends it back to the callback,
finish the sign-in:

```python
started = masks.AuthorizationRequest.from_dict(session.pop("sign_in"))
signed_in = client.complete(started, request.query_params)
```

`complete` checks the state and the issuer, redeems the code, and checks the ID
token. `signed_in.token` holds the tokens and `signed_in.claims` holds who signed
in. `started` holds the PKCE verifier, so keep it where only this browser's
session can reach it.

## A machine signs in as itself

A machine keeps two P-256 keys. One signs its client assertions and the other
holds its tokens, so a token copied off the machine is useless without the key.

```python
import json
import masks

key = masks.Key.generate()
dpop = masks.Key.generate()

saved = json.dumps({"key": key.to_jwk(), "dpop": dpop.to_jwk()})
key = masks.Key.from_jwk(json.loads(saved)["key"])
```

`to_jwk()` writes the private key, so keep the file readable only by the
machine's service user. `key.jwks()` is the public half to register.

```python
issuer = masks.discover("https://auth.example.com")

client = masks.Client(issuer, client_id, key=key, dpop=dpop)
token = client.client_credentials(scope=["files:read"], resource=["https://files.example.com"])
```

The client authenticates with `client_secret_basic` when `secret` is set and
with `private_key_jwt` when `key` is. Pass `method` to choose another. When
`dpop` is set, a token that comes back unbound is refused.

## Enrolling with an initial access token

A manager approves the client in masks, and masks gives out an initial access
token for it. The machine redeems the token once and keeps what comes back.

```python
registration = masks.Client.register(issuer, masks.ClientMetadata(), initial_access_token)
client = masks.Client.from_registration(issuer, registration, key=key, dpop=dpop)
```

`read_registration`, `update_registration`, and `delete_registration` manage
the client with its registration access token. They send that token only to the
issuer's own origin.

## Enrolling machines as an app

An approved app that has claimed a namespace enrolls machines of its own, such
as an agent it installs on each computer. It asks the issuer's
`enrollment_endpoint` for an initial access token and hands the token to the
machine, which registers with it as above.

```python
app = masks.Client(issuer, app_id, secret=app_secret)

enrollment = app.enroll(scope=["xixo:agent"], client_name="nas", expires_in=900)
enrollment.initial_access_token
enrollment.expires_at
```

The app authenticates the way it does at the token endpoint. Every scope must
fall under one of the app's namespaces. `expires_in` is between 60 and 3600
seconds and defaults to 15 minutes. The token is spent the first time a machine
registers with it.

```python
app.unenroll(machine_client_id)
```

`unenroll` archives the machine and revokes every token it holds. Unenrolling
it again succeeds as well. A client the app did not enroll raises `masks.Error`
with `status` 404.

## Calling an API

`client.auth` returns an `httpx.Auth` that fetches and reuses tokens and signs
each request. It sends tokens only to the origins it is given, and `httpx`
drops the token when a redirect leaves that origin.

```python
import httpx

source = client.credentials_source(scope=["files:read"], resource=["https://files.example.com"])

with httpx.Client(auth=client.auth(source, "https://files.example.com")) as api:
    response = api.get("https://files.example.com/files")
```

A held token goes out as `Authorization: DPoP` with a fresh proof, and a server
that asks for a DPoP nonce is answered once. `refresh_source` renews a token
with its refresh token and hands each rotated token to `keep` to be saved.

## Exchanging a token

`exchange` trades a token for a new one under RFC 8693. A service that receives
a caller's access token exchanges it for a token to another API, acting on the
caller's behalf.

```python
token = client.exchange(
    subject_token,
    scope=["files:read"],
    resource=["https://files.example.com"],
    requested_lifetime=300,
)
```

The subject is an access token unless `subject_token_type` says
`masks.ID_TOKEN_TYPE`. `actor_token` names another party in the token's `act`
claim. The new token lasts no longer than the subject token. When the client
has a `dpop` key the new token is held to it, and a subject token held to a key
is exchanged only with a proof from that same key.

`requested_token_type=masks.UPSTREAM_ACCESS_TOKEN_TYPE` with a connection's id
in `audience` releases the access token masks holds for that connection through
a delegation. That token is a Bearer token from the provider, so it comes back
unbound with `issued_token_type` naming the upstream type.

## Async

`masks.AsyncClient` has the same methods as `masks.Client`, awaited, and
`masks.adiscover` discovers an issuer.

```python
issuer = await masks.adiscover("https://auth.example.com")

async with masks.AsyncClient(issuer, client_id, key=key, dpop=dpop) as client:
    source = client.credentials_source(resource=["https://files.example.com"])

    async with httpx.AsyncClient(auth=client.auth(source, "https://files.example.com")) as api:
        response = await api.get("https://files.example.com/files")
```

## The device flow

A machine with no browser shows a code that a person approves on another
device.

```python
device = client.device_authorization(scope=["openid", "offline_access"])
print(f"Open {device.verification_uri} and enter {device.user_code}")

token = client.await_device(device)
```

`await_device` polls at the interval masks names, slows down when asked, and
stops when the code expires. The synchronous form takes a `timeout` in seconds,
and the async form stops when its task is cancelled.

## Checking access tokens

`masks.Verifier` checks a token from any framework. Pass the method, the URL
the client used, and the request's headers.

```python
verifier = masks.Verifier(issuer, "https://files.example.com", public_url="https://files.example.com")

claims = verifier.authenticate(request.method, request.url, request.headers)
claims.has_scope("files:read")
```

The verifier checks the signature against the issuer's published keys, the
`at+jwt` type, the issuer, the audience, and the expiry. A DPoP-bound token
needs a proof signed by its key, made for this method and URL, made in the last
minute, and not seen before. A failed check raises `masks.InvalidToken`.

When the verifier cannot reach the issuer's keys, or its replay store fails, it
raises `masks.Unavailable`. The token may still be good, so answer `503` and
let the client try again with the same token.

Set `public_url` when a proxy sits in front of the API, since a proof names the
address the client used.

### Replayed proofs

A verifier keeps the proofs it has seen in the process's memory. An API that
runs in several processes passes `replay` an object whose `first(key,
expires_in)` answers `True` only the first time it sees a key across every
process, and `False` after that, for `expires_in` seconds.

```python
class RedisReplay:
    def __init__(self, redis):
        self.redis = redis

    def first(self, key, expires_in):
        return bool(self.redis.set(f"dpop:{key}", 1, nx=True, ex=expires_in))


verifier = masks.Verifier(issuer, "https://files.example.com", replay=RedisReplay(redis))
```

`AsyncVerifier` also takes a store whose `first` is a coroutine, and
`Verifier` raises `TypeError` when given one. An answer of `False` raises
`masks.InvalidToken`. When the store raises or answers anything other than
`True` or `False`, the verifier raises `masks.Unavailable` from the store's
error. `masks.MemoryReplayStore` is the default, and one instance can be shared
between verifiers in the same process.

### Introspection

A verifier that checks the JWT sees a revoked token as valid until it expires.
`introspect` asks the issuer.

```python
found = client.introspect(token, "access_token")
found.active and found.has_scope("files:read")
```

The issuer answers `active` only to the client the token was issued to, or to
an approved client whose resources include one of the token's audiences. A
token that is not active has no scopes. An answer that names another issuer
raises `masks.Error`.

### ASGI and FastAPI

`masks.asgi.Middleware` checks every request with an `AsyncVerifier` and
answers `401` with `WWW-Authenticate` challenges when the check fails. It
answers `503` with no challenge when the verifier raises `masks.Unavailable`.
The claims are at `request.state.masks_claims`.

```python
from fastapi import Depends, FastAPI, HTTPException, Request
from masks.asgi import Middleware

verifier = masks.AsyncVerifier(issuer, "https://files.example.com", public_url="https://files.example.com")

app = FastAPI()
app.add_middleware(Middleware, verifier=verifier)


def reading(request: Request) -> masks.Claims:
    claims = request.state.masks_claims

    if not claims.has_scope("files:read"):
        raise HTTPException(403)

    return claims


@app.get("/files")
async def files(claims: masks.Claims = Depends(reading)):
    return {"for": claims.subject}
```

### Django and Flask

Call `Verifier.authenticate` in a view decorator or a `before_request` hook.
In Django, pass `request.method`, `request.build_absolute_uri()`, and
`request.headers`. In Flask, pass `request.method`, `request.url`, and
`request.headers`. Answer `401` when it raises `masks.InvalidToken`, and `503`
when it raises `masks.Unavailable`.

## Plain HTTP

Every URL is `https`, except on this machine: `localhost`, a `.localhost` name,
or a loopback address. `allow_plain_http=True` on `discover` lifts that for a
private network.
