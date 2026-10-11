# masks for Python

`masks-client` connects a Python service or a machine to masks. It gets tokens
as a client and checks them as an API. Every call has a synchronous form and an
`async` one.

```sh
pip install masks-client
```

The package imports as `masks` and needs Python 3.10 or later.

| Covers | |
| --- | --- |
| Discovery | The issuer's document, checked against the address it was fetched from. |
| Registration | Redeeming an initial access token, then reading, updating, and deleting the client. |
| Client authentication | `client_secret_basic`, `client_secret_post`, `private_key_jwt`, and `none`. |
| Grants | Client credentials, refresh tokens, and the device flow. |
| DPoP | Tokens held to a key, and proofs on every request an `httpx` client sends. |
| Revocation | Access and refresh tokens. |
| Checking tokens | `at+jwt` access tokens, including DPoP-bound ones, in any framework or as ASGI middleware. |

Signing people in through a browser is left to an OpenID Connect library such
as [Authlib](https://docs.authlib.org). See
[Other languages](https://masks.pages.dev/guides/other-languages/#python).

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

Set `public_url` when a proxy sits in front of the API, since a proof names the
address the client used.

### ASGI and FastAPI

`masks.asgi.Middleware` checks every request with an `AsyncVerifier` and
answers `401` with `WWW-Authenticate` challenges when the check fails. The
claims are at `request.state.masks_claims`.

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
`request.headers`. Answer `401` when it raises `masks.InvalidToken`.

## Plain HTTP

Every URL is `https`, except on this machine: `localhost`, a `.localhost` name,
or a loopback address. `allow_plain_http=True` on `discover` lifts that for a
private network.
