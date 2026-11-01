from __future__ import annotations

import json
import time

import httpx
import pytest

import masks

from .fake import AUDIENCE, ISSUER, Fake, FakeClient


def test_discovery_refuses_a_document_naming_another_issuer(fake: Fake) -> None:
    fake.issuer = "https://elsewhere.example"

    with pytest.raises(masks.Refused) as raised, fake.http() as http:
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
    with pytest.raises(masks.Insecure):
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

    with pytest.raises(masks.Refused) as raised:
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

    with pytest.raises(masks.Refused) as raised:
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

    with pytest.raises(masks.Refused) as raised:
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

    with pytest.raises(masks.Refused) as raised:
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

    with pytest.raises(masks.Refused) as raised:
        masks.Client.register(issuer, masks.ClientMetadata(), "one-time", http=fake.http())

    assert raised.value.code == "invalid_token"

    client = masks.Client.from_registration(issuer, registration, key=key, http=fake.http())
    read = client.read_registration(registration)

    assert read.registration_access_token == registration.registration_access_token
    assert read.token_endpoint_auth_method == masks.PRIVATE_KEY_JWT

    updated = client.update_registration(read, masks.ClientMetadata(scope="files:read files:write"))

    assert client.client_credentials().scope == "files:read files:write"

    client.delete_registration(updated)

    with pytest.raises(masks.Refused) as raised:
        client.read_registration(updated)

    assert raised.value.code == "invalid_token"


def test_a_registration_uri_on_another_origin_never_sees_the_token(fake: Fake, issuer: masks.Issuer) -> None:
    fake.initial["one-time"] = "enrolled"
    fake.foreign_uri = True

    with pytest.raises(masks.Foreign):
        masks.Client.register(issuer, masks.ClientMetadata(), "one-time", http=fake.http())

    held = masks.Registration(
        client_id="x",
        registration_access_token="secret",
        registration_client_uri="https://elsewhere.example/register/x",
    )
    before = len(fake.seen)

    with pytest.raises(masks.Foreign):
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

    with pytest.raises(masks.Refused), httpx.Client(transport=httpx.MockTransport(handle)) as http:
        masks.discover_resource(AUDIENCE, http=http)


def test_an_answer_past_the_read_limit_is_refused(issuer: masks.Issuer) -> None:
    def handle(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"x" * (masks.errors.READ_LIMIT + 1))

    client = masks.Client(issuer, "app", secret="s", http=httpx.Client(transport=httpx.MockTransport(handle)))

    with pytest.raises(masks.Refused) as raised:
        client.client_credentials()

    assert "more than" in raised.value.description


def test_discovery_reads_the_enrollment_endpoint(issuer: masks.Issuer) -> None:
    assert issuer.metadata.enrollment_endpoint == f"{ISSUER}/enrollments"


@pytest.fixture
def app(fake: Fake, issuer: masks.Issuer) -> masks.Client:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret", namespace="xixo"))

    return masks.Client(issuer, "app", secret="secret", http=fake.http())


def test_an_app_enrolls_a_machine_that_registers_with_the_token(
    app: masks.Client, fake: Fake, issuer: masks.Issuer
) -> None:
    enrollment = app.enroll(scope=["xixo:agent"], client_name="nas", expires_in=900)

    assert enrollment.scopes == ["xixo:agent"]
    assert enrollment.expires_in == 900
    assert enrollment.expires_at is not None and enrollment.expires_at > time.time()
    assert enrollment.initial_access_token not in repr(enrollment)

    sent = fake.seen[-1]
    assert sent.headers["Authorization"].startswith("Basic ")
    assert "DPoP" not in sent.headers
    assert fake.pairs == [("scope", "xixo:agent"), ("client_name", "nas"), ("expires_in", "900")]

    key = masks.Key.generate()
    registration = masks.Client.register(
        issuer,
        masks.ClientMetadata(client_name="nas", token_endpoint_auth_method=masks.PRIVATE_KEY_JWT, jwks=key.jwks()),
        enrollment.initial_access_token,
        http=fake.http(),
    )

    assert fake.enrolled[registration.client_id] == "app"


def test_a_scope_given_as_a_string_is_sent_whole(app: masks.Client, fake: Fake) -> None:
    app.enroll(scope="xixo:agent xixo:files")

    assert fake.pairs == [("scope", "xixo:agent xixo:files")]


def test_an_enrollment_the_server_refuses_raises(app: masks.Client) -> None:
    with pytest.raises(masks.Refused) as raised:
        app.enroll(scope=["masks:manage"])

    assert raised.value.code == "invalid_request"
    assert raised.value.status == 400

    with pytest.raises(masks.Refused):
        app.enroll(scope=["xixo:agent"], expires_in=7200)


@pytest.mark.parametrize("expires_in", [0, -5, True])
def test_an_enrollment_asks_for_a_lifetime_above_zero(app: masks.Client, expires_in: int) -> None:
    with pytest.raises(ValueError):
        app.enroll(scope=["xixo:agent"], expires_in=expires_in)


def test_an_enrollment_names_its_scopes(app: masks.Client, fake: Fake) -> None:
    before = len(fake.seen)

    with pytest.raises(ValueError):
        app.enroll(scope=[])

    assert len(fake.seen) == before


def test_an_answer_without_an_initial_access_token_is_refused(issuer: masks.Issuer) -> None:
    def handle(_: httpx.Request) -> httpx.Response:
        return httpx.Response(201, json={"expires_in": 900, "scope": "xixo:agent"})

    client = masks.Client(issuer, "app", secret="s", http=httpx.Client(transport=httpx.MockTransport(handle)))

    with pytest.raises(masks.Refused) as raised:
        client.enroll(scope=["xixo:agent"])

    assert raised.value.code == "server_error"


def test_an_issuer_without_enrollment_refuses_before_sending(fake: Fake) -> None:
    held = masks.Issuer(url=ISSUER, metadata=masks.Metadata(issuer=ISSUER, token_endpoint=f"{ISSUER}/token"))
    client = masks.Client(held, "app", secret="secret", http=fake.http())

    with pytest.raises(masks.Refused) as raised:
        client.enroll(scope=["xixo:agent"])

    assert raised.value.code == "invalid_issuer"
    assert fake.seen == []


def test_a_private_key_jwt_app_enrolls_and_unenrolls(fake: Fake, issuer: masks.Issuer) -> None:
    key = masks.Key.generate()
    fake.add("signed-app", FakeClient(method="private_key_jwt", jwks=key.jwks(), namespace="xixo"))
    client = masks.Client(issuer, "signed-app", key=key, dpop=masks.Key.generate(), http=fake.http())

    client.enroll(scope=["xixo:agent"])
    client.unenroll("machine-1")

    assert fake.unenrolled == ["machine-1"]
    assert "DPoP" not in fake.seen[-1].headers


def test_an_app_unenrolls_only_its_own_machines(app: masks.Client, fake: Fake, issuer: masks.Issuer) -> None:
    app.enroll(scope=["xixo:agent"])
    app.unenroll("machine-1")

    sent = fake.seen[-1]
    assert sent.method == "DELETE"
    assert sent.url == f"{ISSUER}/enrollments/machine-1"
    assert sent.headers["Authorization"].startswith("Basic ")
    assert fake.unenrolled == ["machine-1"]

    app.unenroll("machine-1")

    fake.add("other", FakeClient(method="client_secret_post", secret="other", namespace="xixo"))
    other = masks.Client(issuer, "other", secret="other", method=masks.CLIENT_SECRET_POST, http=fake.http())

    with pytest.raises(masks.Refused) as raised:
        other.unenroll("machine-1")

    assert raised.value.status == 404
    assert fake.unenrolled == ["machine-1", "machine-1"]


def test_unenrolling_escapes_the_client_id(app: masks.Client, fake: Fake) -> None:
    with pytest.raises(masks.Refused):
        app.unenroll("a/../../token?x=1")

    assert fake.seen[-1].url.raw_path == b"/enrollments/a%2F..%2F..%2Ftoken%3Fx%3D1"


@pytest.mark.parametrize("client_id", ["", ".", ".."])
def test_unenrolling_needs_a_client_id(app: masks.Client, fake: Fake, client_id: str) -> None:
    with pytest.raises(ValueError):
        app.unenroll(client_id)

    assert fake.seen[1:] == []


def test_introspection_describes_a_live_token(signed: masks.Client, app: masks.Client) -> None:
    token = signed.client_credentials(scope=["files:read"])
    found = app.introspect(token.access_token, "access_token")

    assert found.active
    assert found.client_id == "signed"
    assert found.subject == "signed"
    assert found.audience == [AUDIENCE]
    assert found.issuer == ISSUER
    assert found.has_scope("files:read")
    assert found.bound
    assert found.thumbprint == signed.dpop.thumbprint
    assert found.tenant is not None and found.tenant.subdomain == "fake"
    assert found.raw["asked_by"] == "app"


def test_introspection_reports_an_inactive_token(app: masks.Client, fake: Fake) -> None:
    token = app.client_credentials()
    app.revoke(token.access_token)

    found = app.introspect(token.access_token)

    assert not found.active
    assert found.scopes == []
    assert not found.has_scope("files:read")
    assert app.introspect("nonsense").active is False


def test_introspection_refuses_a_token_from_another_issuer(app: masks.Client, fake: Fake) -> None:
    fake.introspected_issuer = "https://elsewhere.example"

    with pytest.raises(masks.Refused) as raised:
        app.introspect(app.client_credentials().access_token)

    assert raised.value.code == "invalid_issuer"


def test_introspection_authenticates_the_client(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret"))

    with pytest.raises(masks.Refused) as raised:
        masks.Client(issuer, "app", secret="wrong", http=fake.http()).introspect("token")

    assert raised.value.code == "invalid_client"


def test_an_exchange_acts_on_behalf_of_the_subject(app: masks.Client, fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("caller", FakeClient(method="client_secret_basic", secret="caller", scope="files:read files:write"))
    subject = masks.Client(issuer, "caller", secret="caller", http=fake.http()).client_credentials()

    exchanged = app.exchange(
        subject.access_token,
        scope=["files:read"],
        resource=["https://other.example"],
        audience=["https://other.example"],
        requested_lifetime=120,
    )

    assert exchanged.issued_token_type == masks.ACCESS_TOKEN_TYPE
    assert exchanged.scope == "files:read"
    assert exchanged.expires_in == 120
    assert exchanged.refresh_token is None

    claims = masks.Verifier(issuer, "https://other.example", http=fake.http()).verify(exchanged.access_token)

    assert claims.subject == "caller"
    assert claims.act == {"sub": "app"}
    assert fake.exchanged[-1]["grant_type"] == masks.GRANT_TOKEN_EXCHANGE
    assert fake.exchanged[-1]["subject_token_type"] == masks.ACCESS_TOKEN_TYPE
    assert "actor_token" not in fake.exchanged[-1]
    assert "requested_token_type" not in fake.exchanged[-1]


def test_an_exchange_names_an_actor(app: masks.Client, signed: masks.Client) -> None:
    subject = app.client_credentials()
    actor = signed.client_credentials()

    exchanged = app.exchange(subject.access_token, actor_token=actor.access_token)
    claims = masks.Verifier(app.issuer, AUDIENCE, http=app.http).verify(exchanged.access_token)

    assert claims.act == {"sub": "signed", "client_id": "signed"}


def test_an_exchange_holds_the_new_token_to_the_same_key(signed: masks.Client, fake: Fake) -> None:
    fake.nonce = "fresh-nonce"
    subject = signed.client_credentials()

    exchanged = signed.exchange(subject.access_token, scope=["files:read"])

    assert exchanged.bound
    assert fake.seen[-1].headers["DPoP"]

    claims = masks.Verifier(signed.issuer, AUDIENCE, http=fake.http()).verify(exchanged.access_token)

    assert claims.thumbprint == signed.dpop.thumbprint


def test_an_exchange_of_a_held_token_without_its_key_is_refused(signed: masks.Client, app: masks.Client) -> None:
    subject = signed.client_credentials()

    with pytest.raises(masks.Refused) as raised:
        app.exchange(subject.access_token)

    assert raised.value.code == "invalid_grant"


def test_an_upstream_token_comes_back_as_a_bearer_token(signed: masks.Client) -> None:
    subject = signed.client_credentials()

    upstream = signed.exchange(
        subject.access_token,
        requested_token_type=masks.UPSTREAM_ACCESS_TOKEN_TYPE,
        audience=["0b0c4b6e-6f86-4a3f-9d43-0d6f0c2b1a77"],
    )

    assert upstream.access_token == "upstream-token"
    assert not upstream.bound
    assert upstream.issued_token_type == masks.UPSTREAM_ACCESS_TOKEN_TYPE


def test_an_exchange_answered_with_an_unheld_access_token_is_refused(issuer: masks.Issuer) -> None:
    def handle(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "access_token": "plain",
                "issued_token_type": masks.UPSTREAM_ACCESS_TOKEN_TYPE,
                "token_type": "Bearer",
            },
        )

    client = masks.Client(
        issuer, "app", secret="s", dpop=masks.Key.generate(), http=httpx.Client(transport=httpx.MockTransport(handle))
    )

    with pytest.raises(masks.Refused) as raised:
        client.exchange("subject")

    assert raised.value.code == "invalid_dpop_proof"


@pytest.mark.parametrize("lifetime", [0, -1])
def test_an_exchange_asks_for_a_lifetime_above_zero(app: masks.Client, lifetime: int) -> None:
    with pytest.raises(ValueError):
        app.exchange("subject", requested_lifetime=lifetime)


def test_an_exchange_needs_a_subject_token(app: masks.Client) -> None:
    with pytest.raises(ValueError):
        app.exchange("")


@pytest.mark.anyio
async def test_the_async_client_enrolls_introspects_and_exchanges(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret", namespace="xixo", scope="xixo:read"))

    async with masks.AsyncClient(issuer, "app", secret="secret", http=fake.async_http()) as client:
        enrollment = await client.enroll(scope=["xixo:agent"], client_name="nas")
        await client.unenroll("machine-1")

        token = await client.client_credentials()
        found = await client.introspect(token.access_token)
        exchanged = await client.exchange(token.access_token, scope=["xixo:read"])

    assert enrollment.scopes == ["xixo:agent"]
    assert fake.unenrolled == ["machine-1"]
    assert found.active and found.has_scope("xixo:read")
    assert exchanged.issued_token_type == masks.ACCESS_TOKEN_TYPE
