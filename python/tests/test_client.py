from __future__ import annotations

import json
import time

import httpx
import pytest

import masks

from .fake import AUDIENCE, ISSUER, Fake, FakeClient


def test_discovery_refuses_a_document_naming_another_issuer(fake: Fake) -> None:
    fake.issuer = "https://elsewhere.example"

    with pytest.raises(masks.Error) as raised, fake.http() as http:
        masks.discover(ISSUER, http=http)

    assert raised.value.code == "invalid_issuer"


def test_discovery_reads_the_tenant(issuer: masks.Issuer) -> None:
    assert issuer.url == ISSUER
    assert issuer.metadata.tenant.subdomain == "fake"


@pytest.mark.parametrize(
    "allowed", ["https://id.example", "http://127.0.0.1:3000", "http://masks.localhost:12345", "http://[::1]:80"]
)
def test_plain_http_is_allowed_on_this_machine(allowed: str) -> None:
    masks.flows.check(allowed)


@pytest.mark.parametrize("refused", ["http://id.example", "http://10.0.0.4", "ftp://id.example", "id.example"])
def test_plain_http_is_refused_elsewhere(refused: str) -> None:
    with pytest.raises(masks.InsecureURL):
        masks.flows.check(refused)


def test_allow_plain_http_lifts_the_rule() -> None:
    masks.flows.check("http://10.0.0.4", allow_plain_http=True)


@pytest.mark.parametrize("method", [masks.CLIENT_SECRET_BASIC, masks.CLIENT_SECRET_POST])
def test_client_credentials_with_a_secret(fake: Fake, issuer: masks.Issuer, method: masks.AuthMethod) -> None:
    fake.add("machine", FakeClient(method=method, secret="s3cr:et/+ x", scope="files:read"))

    with masks.Client(issuer, "machine", secret="s3cr:et/+ x", method=method, http=fake.http()) as client:
        token = client.client_credentials()

    assert not token.bound
    assert token.scope == "files:read"
    assert token.valid()


def test_a_wrong_secret_is_an_invalid_client(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("machine", FakeClient(method="client_secret_basic", secret="right"))

    with pytest.raises(masks.Error) as raised:
        masks.Client(issuer, "machine", secret="wrong", http=fake.http()).client_credentials()

    assert raised.value.code == "invalid_client"
    assert raised.value.status == 401
    assert masks.has_code(raised.value, "invalid_client")


def test_a_private_key_jwt_client_gets_a_token_held_to_its_key(
    signed: masks.Client, issuer: masks.Issuer, fake: Fake
) -> None:
    token = signed.client_credentials(scope=["files:read"], resource=[AUDIENCE])

    assert token.bound

    claims = masks.Verifier(issuer, AUDIENCE, http=fake.http()).verify(token.access_token)

    assert claims.bound
    assert claims.thumbprint == signed.dpop.thumbprint
    assert claims.subject == "signed"


def test_each_assertion_is_used_once(signed: masks.Client) -> None:
    for _ in range(3):
        signed.client_credentials()


def test_a_token_endpoint_nonce_is_answered_once(signed: masks.Client, fake: Fake) -> None:
    fake.nonce = "fresh-nonce"

    assert signed.client_credentials().bound


def test_a_bearer_answer_to_a_dpop_client_is_refused(issuer: masks.Issuer) -> None:
    def handle(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"access_token": "plain", "token_type": "Bearer", "expires_in": 60})

    client = masks.Client(
        issuer,
        "machine",
        secret="secret",
        dpop=masks.Key.generate(),
        http=httpx.Client(transport=httpx.MockTransport(handle)),
    )

    with pytest.raises(masks.Error) as raised:
        client.client_credentials()

    assert raised.value.code == "invalid_dpop_proof"


@pytest.mark.usefixtures("quick_devices")
def test_the_device_flow_waits_for_approval(fake: Fake, issuer: masks.Issuer) -> None:
    fake.pending = 3
    fake.add("tv", FakeClient(method="none", scope="openid"))
    client = masks.Client(issuer, "tv", http=fake.http())

    device = client.device_authorization(scope=["openid"])

    assert device.user_code == "ABCD EFGH"

    token = client.await_device(device)

    assert token.access_token
    assert fake.pending == 0


@pytest.mark.usefixtures("quick_devices")
def test_the_device_flow_stops_at_its_timeout(fake: Fake, issuer: masks.Issuer) -> None:
    fake.pending = 1000
    fake.add("tv", FakeClient(method="none"))
    client = masks.Client(issuer, "tv", http=fake.http())

    with pytest.raises(TimeoutError):
        client.await_device(client.device_authorization(), timeout=0.1)


def test_the_device_flow_stops_when_the_code_expires(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("tv", FakeClient(method="none"))
    client = masks.Client(issuer, "tv", http=fake.http())
    device = client.device_authorization()
    device.expires_at = time.time() - 1

    with pytest.raises(masks.Error) as raised:
        client.await_device(device)

    assert raised.value.code == "expired_token"


def test_a_refresh_source_keeps_each_rotated_token(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret"))
    client = masks.Client(issuer, "app", secret="secret", http=fake.http())

    first = client.client_credentials()
    first.expires_at = time.time() - 60
    kept: list[masks.Token] = []

    source = client.refresh_source(first, keep=kept.append)
    renewed = source.token()

    assert source.token() is renewed
    assert len(kept) == 1
    assert renewed.refresh_token != first.refresh_token

    with pytest.raises(masks.Error) as raised:
        client.refresh(first.refresh_token or "")

    assert raised.value.code == "invalid_grant"


def test_revocation_sends_the_token(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret"))

    masks.Client(issuer, "app", secret="secret", http=fake.http()).revoke("a-token", "refresh_token")

    assert fake.revoked == ["a-token"]


def test_registration_with_an_initial_access_token(fake: Fake, issuer: masks.Issuer) -> None:
    fake.initial["one-time"] = "enrolled"
    key = masks.Key.generate()

    registration = masks.Client.register(
        issuer,
        masks.ClientMetadata(
            client_name="A machine",
            grant_types=[masks.GRANT_CLIENT_CREDENTIALS],
            token_endpoint_auth_method=masks.PRIVATE_KEY_JWT,
            jwks=key.jwks(),
            scope="files:read",
        ),
        "one-time",
        http=fake.http(),
    )

    with pytest.raises(masks.Error) as raised:
        masks.Client.register(issuer, masks.ClientMetadata(), "one-time", http=fake.http())

    assert raised.value.code == "invalid_token"

    client = masks.Client.from_registration(issuer, registration, key=key, http=fake.http())
    read = client.read_registration(registration)

    assert read.registration_access_token == registration.registration_access_token
    assert read.token_endpoint_auth_method == masks.PRIVATE_KEY_JWT

    updated = client.update_registration(read, masks.ClientMetadata(scope="files:read files:write"))

    assert client.client_credentials().scope == "files:read files:write"

    client.delete_registration(updated)

    with pytest.raises(masks.Error) as raised:
        client.read_registration(updated)

    assert raised.value.code == "invalid_token"


def test_a_registration_uri_on_another_origin_never_sees_the_token(fake: Fake, issuer: masks.Issuer) -> None:
    fake.initial["one-time"] = "enrolled"
    fake.foreign_uri = True

    with pytest.raises(masks.ForeignOrigin):
        masks.Client.register(issuer, masks.ClientMetadata(), "one-time", http=fake.http())

    held = masks.Registration(
        client_id="x",
        registration_access_token="secret",
        registration_client_uri="https://elsewhere.example/register/x",
    )
    before = len(fake.seen)

    with pytest.raises(masks.ForeignOrigin):
        masks.Client(issuer, "x", http=fake.http()).read_registration(held)

    assert len(fake.seen) == before


def test_keys_survive_json() -> None:
    key = masks.Key.generate()
    encoded = json.dumps(key.to_jwk())

    assert '"d":' in encoded
    assert '"d":' not in json.dumps(key.public_jwk())
    assert '"d":' not in json.dumps(key.jwks())
    assert masks.Key.from_jwk(encoded).thumbprint == key.thumbprint

    with pytest.raises(ValueError):
        masks.Key.from_jwk(key.public_jwk())


def test_resource_discovery_finds_the_issuer() -> None:
    def handle(request: httpx.Request) -> httpx.Response:
        if request.url.path != "/.well-known/oauth-protected-resource":
            return httpx.Response(404)

        return httpx.Response(200, json={"resource": AUDIENCE, "authorization_servers": [ISSUER]})

    with httpx.Client(transport=httpx.MockTransport(handle)) as http:
        found = masks.discover_resource(AUDIENCE, http=http)

    assert found.authorization_servers == [ISSUER]


def test_resource_discovery_refuses_metadata_naming_another_resource() -> None:
    def handle(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"resource": "https://other.example"})

    with pytest.raises(masks.Error), httpx.Client(transport=httpx.MockTransport(handle)) as http:
        masks.discover_resource(AUDIENCE, http=http)


def test_an_answer_past_the_read_limit_is_refused(issuer: masks.Issuer) -> None:
    def handle(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"x" * (masks.errors.READ_LIMIT + 1))

    client = masks.Client(issuer, "app", secret="s", http=httpx.Client(transport=httpx.MockTransport(handle)))

    with pytest.raises(masks.Error) as raised:
        client.client_credentials()

    assert "more than" in raised.value.description
