from __future__ import annotations

import base64
import json
import time
from collections.abc import Callable
from typing import Any

import httpx
import pytest

import masks
from masks.asgi import CLAIMS, Middleware

from .fake import AUDIENCE, ISSUER, Fake, FakeClient

TARGET = f"{AUDIENCE}/files"


def resource(verifier: masks.Verifier, seen: list[masks.Claims]) -> httpx.MockTransport:
    def handle(request: httpx.Request) -> httpx.Response:
        try:
            claims = verifier.authenticate(request.method, str(request.url), request.headers)
        except masks.InvalidToken as error:
            return httpx.Response(401, text=str(error))

        seen.append(claims)

        return httpx.Response(200, content=request.content)

    return httpx.MockTransport(handle)


def test_auth_signs_each_request_for_its_resource(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    seen: list[masks.Claims] = []
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())
    auth = signed.auth(signed.credentials_source(resource=[AUDIENCE]), AUDIENCE)

    with httpx.Client(auth=auth, transport=resource(verifier, seen)) as http:
        for body in ("one", "two"):
            response = http.post(f"{TARGET}?path=x", content=body)

            assert response.status_code == 200, response.text
            assert response.text == body

    assert [claims.subject for claims in seen] == ["signed", "signed"]


def test_auth_refuses_an_origin_it_was_not_given(signed: masks.Client) -> None:
    calls: list[httpx.Request] = []
    auth = signed.auth(signed.credentials_source(), AUDIENCE)

    with (
        httpx.Client(
            auth=auth, transport=httpx.MockTransport(lambda request: calls.append(request) or httpx.Response(200))
        ) as http,
        pytest.raises(masks.ForeignOrigin),
    ):
        http.get("https://elsewhere.example/files")

    assert calls == []


def test_a_redirect_to_another_origin_carries_no_token(signed: masks.Client) -> None:
    seen: dict[str, httpx.Request] = {}

    def handle(request: httpx.Request) -> httpx.Response:
        seen[request.url.host] = request

        if request.url.host == "files.example":
            return httpx.Response(302, headers={"Location": "https://elsewhere.example/stolen"})

        return httpx.Response(200)

    auth = signed.auth(signed.credentials_source(), AUDIENCE)

    with httpx.Client(auth=auth, transport=httpx.MockTransport(handle), follow_redirects=True) as http:
        http.get(TARGET)

    assert "Authorization" in seen["files.example"].headers
    assert "Authorization" not in seen["elsewhere.example"].headers


def test_auth_sends_a_bearer_token_when_the_token_is_not_held(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret", scope="files:read files:write"))
    client = masks.Client(issuer, "app", secret="secret", http=fake.http())
    seen: list[masks.Claims] = []
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())

    with httpx.Client(
        auth=client.auth(client.credentials_source(), AUDIENCE), transport=resource(verifier, seen)
    ) as http:
        assert http.get(TARGET).status_code == 200

    assert seen[0].has_scope("files:write")
    assert not seen[0].bound


def proof_claims(request: httpx.Request) -> dict[str, Any]:
    payload = request.headers["DPoP"].split(".")[1]

    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def test_auth_answers_a_resource_nonce_and_replays_the_body(signed: masks.Client) -> None:
    nonces: list[str] = []
    bodies: list[bytes] = []

    def handle(request: httpx.Request) -> httpx.Response:
        claims = proof_claims(request)
        nonces.append(claims.get("nonce", ""))
        bodies.append(request.content)

        if claims.get("nonce") != "server-nonce":
            return httpx.Response(
                401, headers={"DPoP-Nonce": "server-nonce", "WWW-Authenticate": 'DPoP error="use_dpop_nonce"'}
            )

        return httpx.Response(200)

    auth = signed.auth(signed.credentials_source(), AUDIENCE)

    with httpx.Client(auth=auth, transport=httpx.MockTransport(handle)) as http:
        assert http.post(TARGET, content=b"payload").status_code == 200
        assert nonces == ["", "server-nonce"]
        assert bodies[1] == b"payload"

        http.post(TARGET, content=b"later")

    assert nonces[2] == "server-nonce"


def bound_request(signed: masks.Client, method: str = "GET") -> tuple[masks.Token, dict[str, str]]:
    token = signed.client_credentials()
    assert signed.dpop is not None

    return token, {
        "Authorization": f"DPoP {token.access_token}",
        "DPoP": masks.proof(signed.dpop, method, TARGET, token.access_token),
    }


def test_a_verifier_refuses_a_replayed_proof(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())
    _, headers = bound_request(signed)

    verifier.authenticate("GET", TARGET, headers)

    with pytest.raises(masks.InvalidToken, match="already been used"):
        verifier.authenticate("GET", TARGET, headers)


MISUSES: dict[str, Callable[[masks.Client, masks.Token, dict[str, str]], tuple[str, str, list[tuple[str, str]]]]] = {
    "Bearer": lambda _, token, headers: (
        "GET",
        TARGET,
        [("Authorization", f"Bearer {token.access_token}"), ("DPoP", headers["DPoP"])],
    ),
    "no proof": lambda _, __, headers: ("GET", TARGET, [("Authorization", headers["Authorization"])]),
    "two proofs": lambda _, __, headers: ("GET", TARGET, [*headers.items(), ("DPoP", headers["DPoP"])]),
    "another method": lambda _, __, headers: ("DELETE", TARGET, list(headers.items())),
    "another URL": lambda _, __, headers: ("GET", f"{AUDIENCE}/other", list(headers.items())),
    "another key": lambda _, token, headers: (
        "GET",
        TARGET,
        [
            ("Authorization", headers["Authorization"]),
            ("DPoP", masks.proof(masks.Key.generate(), "GET", TARGET, token.access_token)),
        ],
    ),
    "another token": lambda client, _, headers: (
        "GET",
        TARGET,
        [
            ("Authorization", headers["Authorization"]),
            ("DPoP", masks.proof(client.dpop, "GET", TARGET, "something else")),
        ],
    ),
}


@pytest.mark.parametrize("misuse", MISUSES)
def test_a_verifier_refuses_misused_proofs(signed: masks.Client, issuer: masks.Issuer, fake: Fake, misuse: str) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())
    token, headers = bound_request(signed)
    method, url, presented = MISUSES[misuse](signed, token, headers)

    with pytest.raises(masks.InvalidToken):
        verifier.authenticate(method, url, presented)


def test_a_verifier_accepts_a_query_and_a_default_port(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())
    _, headers = bound_request(signed)

    verifier.authenticate("GET", "https://FILES.example:443/files?page=2", headers)


def test_a_verifier_reads_its_public_url(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, public_url=AUDIENCE, http=fake.http())
    _, headers = bound_request(signed)

    verifier.authenticate("GET", "http://10.0.0.4:8080/files", headers)


def test_a_stale_proof_is_refused(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())
    token = signed.client_credentials()
    assert signed.dpop is not None
    stale = signed.dpop.sign(
        "dpop+jwt",
        {
            "jti": "old",
            "htm": "GET",
            "htu": TARGET,
            "iat": int(time.time()) - 600,
            "ath": masks.dpop.token_hash(token.access_token),
        },
        embed=True,
    )

    with pytest.raises(masks.InvalidToken, match="just now"):
        verifier.authenticate("GET", TARGET, {"Authorization": f"DPoP {token.access_token}", "DPoP": stale})


def good_claims() -> dict[str, Any]:
    now = int(time.time())

    return {"iss": ISSUER, "sub": "ada", "aud": AUDIENCE, "jti": "1", "exp": now + 3600, "iat": now}


def changed(name: str, value: Any) -> dict[str, Any]:
    held = good_claims()

    if value is None:
        del held[name]
    else:
        held[name] = value

    return held


def test_a_verifier_checks_the_token_itself(fake: Fake, issuer: masks.Issuer) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())

    assert verifier.verify(fake.issue(good_claims())).subject == "ada"

    refused = {
        "another audience": fake.issue(changed("aud", "https://other.example")),
        "another issuer": fake.issue(changed("iss", "https://other.example")),
        "expired": fake.issue(changed("exp", int(time.time()) - 3600)),
        "no jti": fake.issue(changed("jti", None)),
        "an ID token": fake.issue(good_claims(), typ="JWT"),
        "an unknown key": fake.issue(good_claims(), kid="rotated-away"),
        "not a JWT": "nonsense",
        "another key": masks.Key.generate().sign("at+jwt", good_claims(), embed=False),
    }

    for name, token in refused.items():
        with pytest.raises(masks.InvalidToken):
            verifier.verify(token)
            pytest.fail(f"{name} was accepted")


def test_an_unknown_key_refetches_the_keys_at_most_once_in_a_while(fake: Fake, issuer: masks.Issuer) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())
    verifier.verify(fake.issue(good_claims()))

    for _ in range(5):
        with pytest.raises(masks.InvalidToken):
            verifier.verify(fake.issue(good_claims(), kid="unknown"))

    assert fake.jwks_fetches == 1


@pytest.mark.anyio
async def test_the_async_client_signs_in_and_calls_an_api(fake: Fake, issuer: masks.Issuer) -> None:
    key, dpop = masks.Key.generate(), masks.Key.generate()
    fake.add("async", FakeClient(method="private_key_jwt", jwks=key.jwks(), scope="files:read"))
    seen: list[masks.Claims] = []
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http())

    async with masks.AsyncClient(issuer, "async", key=key, dpop=dpop, http=fake.async_http()) as client:
        token = await client.client_credentials()
        assert token.bound

        sync_resource = resource(verifier, seen)

        async def handle(request: httpx.Request) -> httpx.Response:
            await request.aread()
            return sync_resource.handle_request(request)

        auth = client.auth(client.credentials_source(), AUDIENCE)

        async with httpx.AsyncClient(auth=auth, transport=httpx.MockTransport(handle)) as http:
            response = await http.post(TARGET, content=b"async")

        assert response.status_code == 200, response.text
        assert seen[0].thumbprint == dpop.thumbprint

        await client.revoke(token.access_token, "access_token")

    assert fake.revoked == [token.access_token]


@pytest.mark.anyio
@pytest.mark.usefixtures("quick_devices")
async def test_the_async_device_flow(fake: Fake, issuer: masks.Issuer) -> None:
    fake.pending = 2
    fake.add("tv", FakeClient(method="none"))

    async with masks.AsyncClient(issuer, "tv", http=fake.async_http()) as client:
        token = await client.await_device(await client.device_authorization())

    assert token.access_token


@pytest.mark.anyio
async def test_the_async_registration(fake: Fake, issuer: masks.Issuer) -> None:
    fake.initial["one-time"] = "enrolled"

    async with fake.async_http() as http:
        registration = await masks.AsyncClient.register(
            issuer, masks.ClientMetadata(scope="files:read"), "one-time", http=http
        )

    assert registration.client_id == "enrolled"


@pytest.mark.anyio
async def test_async_discovery(fake: Fake) -> None:
    async with fake.async_http() as http:
        found = await masks.adiscover(ISSUER, http=http)

    assert found.metadata.token_endpoint == f"{ISSUER}/token"


async def call(
    app: Any, headers: list[tuple[bytes, bytes]], method: str = "GET"
) -> tuple[dict[str, Any], dict[str, Any]]:
    sent: list[dict[str, Any]] = []
    scope = {
        "type": "http",
        "method": method,
        "scheme": "https",
        "path": "/files",
        "raw_path": b"/files",
        "query_string": b"",
        "headers": [(b"host", b"files.example"), *headers],
        "server": ("files.example", 443),
    }

    async def receive() -> dict[str, Any]:
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message: dict[str, Any]) -> None:
        sent.append(message)

    await app(scope, receive, send)

    return scope, sent[0]


@pytest.mark.anyio
async def test_the_asgi_middleware(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    async def app(scope: Any, _: Any, send: Any) -> None:
        await send({"type": "http.response.start", "status": 200, "headers": []})

    middleware = Middleware(app, masks.AsyncVerifier(issuer, AUDIENCE, http=fake.async_http()))
    _, headers = bound_request(signed)

    scope, started = await call(
        middleware, [(name.lower().encode(), value.encode()) for name, value in headers.items()]
    )

    assert started["status"] == 200
    assert scope[CLAIMS].subject == "signed"
    assert scope["state"]["masks_claims"].subject == "signed"

    _, refused = await call(middleware, [])

    assert refused["status"] == 401
    assert len([name for name, _ in refused["headers"] if name == b"www-authenticate"]) == 2


class Remembering:
    def __init__(self, answer: object = True) -> None:
        self.answer = answer
        self.asked: list[tuple[str, int]] = []

    def first(self, key: str, expires_in: int) -> Any:
        self.asked.append((key, expires_in))

        if isinstance(self.answer, Exception):
            raise self.answer

        return self.answer


class AsyncRemembering(Remembering):
    async def first(self, key: str, expires_in: int) -> Any:
        return super().first(key, expires_in)


def test_a_verifier_asks_its_replay_store_about_each_proof(
    signed: masks.Client, issuer: masks.Issuer, fake: Fake
) -> None:
    store = Remembering()
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http(), replay=store)
    _, headers = bound_request(signed)

    verifier.authenticate("GET", TARGET, headers)

    jti = proof_claims(httpx.Request("GET", TARGET, headers=headers))["jti"]
    assert store.asked == [(f"{signed.dpop.thumbprint}:{jti}", 120)]


def test_a_bearer_token_never_reaches_the_replay_store(fake: Fake, issuer: masks.Issuer) -> None:
    store = Remembering()
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret"))
    token = masks.Client(issuer, "app", secret="secret", http=fake.http()).client_credentials()

    masks.Verifier(issuer, AUDIENCE, http=fake.http(), replay=store).authenticate(
        "GET", TARGET, {"Authorization": f"Bearer {token.access_token}"}
    )

    assert store.asked == []


@pytest.mark.parametrize(
    ("answer", "said"),
    [
        (False, "already been used"),
        (1, "something other than true or false"),
        (None, "something other than true or false"),
        (ConnectionError("redis is down"), "could not say"),
    ],
)
def test_a_replay_store_refuses_unless_it_answers_true(
    signed: masks.Client, issuer: masks.Issuer, fake: Fake, answer: object, said: str
) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http(), replay=Remembering(answer))
    _, headers = bound_request(signed)

    with pytest.raises(masks.InvalidToken, match=said):
        verifier.authenticate("GET", TARGET, headers)


def test_a_synchronous_verifier_refuses_an_async_store(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    verifier = masks.Verifier(issuer, AUDIENCE, http=fake.http(), replay=AsyncRemembering())
    _, headers = bound_request(signed)

    with pytest.raises(masks.InvalidToken, match="something other than true or false"):
        verifier.authenticate("GET", TARGET, headers)


def test_verifiers_can_share_a_replay_store(signed: masks.Client, issuer: masks.Issuer, fake: Fake) -> None:
    store = masks.MemoryReplayStore()
    _, headers = bound_request(signed)

    masks.Verifier(issuer, AUDIENCE, http=fake.http(), replay=store).authenticate("GET", TARGET, headers)

    with pytest.raises(masks.InvalidToken, match="already been used"):
        masks.Verifier(issuer, AUDIENCE, http=fake.http(), replay=store).authenticate("GET", TARGET, headers)


def test_the_memory_store_forgets_a_proof_once_it_expires(monkeypatch: pytest.MonkeyPatch) -> None:
    now = [1000.0]
    monkeypatch.setattr(masks.replay.time, "monotonic", lambda: now[0])
    store = masks.MemoryReplayStore()

    assert store.first("key", 120)
    assert not store.first("key", 120)

    now[0] += 119
    assert not store.first("key", 120)

    now[0] += 2
    assert store.first("key", 120)
    assert list(store._held) == ["key"]


@pytest.mark.anyio
@pytest.mark.parametrize("store", [AsyncRemembering, Remembering])
async def test_an_async_verifier_awaits_its_replay_store(
    signed: masks.Client, issuer: masks.Issuer, fake: Fake, store: type[Remembering]
) -> None:
    held = store()
    verifier = masks.AsyncVerifier(issuer, AUDIENCE, http=fake.async_http(), replay=held)
    _, headers = bound_request(signed)

    claims = await verifier.authenticate("GET", TARGET, headers)

    assert claims.subject == "signed"
    assert len(held.asked) == 1


@pytest.mark.anyio
async def test_the_asgi_middleware_refuses_when_the_replay_store_fails(
    signed: masks.Client, issuer: masks.Issuer, fake: Fake
) -> None:
    async def app(scope: Any, _: Any, send: Any) -> None:
        await send({"type": "http.response.start", "status": 200, "headers": []})

    verifier = masks.AsyncVerifier(
        issuer, AUDIENCE, http=fake.async_http(), replay=AsyncRemembering(TimeoutError("no answer"))
    )
    _, headers = bound_request(signed)

    _, refused = await call(
        Middleware(app, verifier), [(name.lower().encode(), value.encode()) for name, value in headers.items()]
    )

    assert refused["status"] == 401
