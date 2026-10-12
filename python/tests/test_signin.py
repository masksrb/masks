from __future__ import annotations

import time
from typing import Any
from urllib.parse import parse_qs, parse_qsl, urlsplit

import httpx
import pytest

import masks

from .fake import ISSUER, Fake, FakeClient

APP = "https://app.example"
CALLBACK = f"{APP}/auth/callback"


@pytest.fixture
def web(fake: Fake, issuer: masks.Issuer) -> masks.Client:
    fake.add("web", FakeClient(method="client_secret_basic", secret="secret"))

    return masks.Client(issuer, "web", secret="secret", http=fake.http())


def returned(url: str) -> dict[str, str]:
    return dict(parse_qsl(urlsplit(url).query))


def test_start_builds_a_pkce_request(web: masks.Client) -> None:
    started = web.start(CALLBACK, organization="Acme", resource=["https://files.example"], max_age=300)
    query = parse_qs(urlsplit(started.url).query)

    assert started.url.startswith(f"{ISSUER}/authorize?")
    assert query["code_challenge_method"] == ["S256"]
    assert query["code_challenge"] == [masks.oidc.code_challenge(started.verifier)]
    assert query["state"] == [started.state]
    assert query["nonce"] == [started.nonce]
    assert query["organization"] == ["acme"]
    assert query["max_age"] == ["300"]
    assert query["resource"] == ["https://files.example"]
    assert "dpop_jkt" not in query
    assert started.verifier not in repr(started)
    assert masks.AuthorizationRequest.from_dict(started.to_dict()) == started


def test_start_leaves_out_a_nonce_without_openid_and_a_bad_organization(web: masks.Client) -> None:
    started = web.start(CALLBACK, scope=["profile"], organization="../evil")
    query = parse_qs(urlsplit(started.url).query)

    assert started.nonce == ""
    assert "nonce" not in query
    assert "organization" not in query


def test_a_sign_in_completes_with_a_verified_id_token(web: masks.Client, fake: Fake) -> None:
    started = web.start(CALLBACK, scope=["openid", "profile", "offline_access", "organization"], organization="acme")
    signed = web.complete(started, returned(fake.authorize(started.url)))

    assert signed.subject == "ada"
    assert signed.claims["org"]["key"] == "acme"
    assert signed.token.refresh_token
    assert signed.token.id_token


def test_a_sign_in_refuses_another_state(web: masks.Client, fake: Fake) -> None:
    started = web.start(CALLBACK)
    params = returned(fake.authorize(started.url))
    params["state"] = "forged"

    with pytest.raises(masks.Error) as raised:
        web.complete(started, params)

    assert raised.value.code == "invalid_state"


@pytest.mark.parametrize("iss", ["https://elsewhere.example", None])
def test_a_sign_in_refuses_an_answer_from_another_issuer(web: masks.Client, fake: Fake, iss: str | None) -> None:
    started = web.start(CALLBACK)
    params = returned(fake.authorize(started.url))

    if iss is None:
        del params["iss"]
    else:
        params["iss"] = iss

    with pytest.raises(masks.Error) as raised:
        web.complete(started, params)

    assert raised.value.code == "invalid_issuer"


def test_a_sign_in_raises_the_error_masks_answered(web: masks.Client) -> None:
    started = web.start(CALLBACK)

    with pytest.raises(masks.Error) as raised:
        web.complete(started, {"error": "access_denied", "error_description": "no", "state": started.state})

    assert raised.value.code == "access_denied"


def test_a_sign_in_refuses_an_id_token_for_another_nonce(web: masks.Client, fake: Fake) -> None:
    started = web.start(CALLBACK)
    params = returned(fake.authorize(started.url))
    replayed = masks.AuthorizationRequest.from_dict({**started.to_dict(), "nonce": "another"})

    with pytest.raises(masks.InvalidToken, match="another sign-in"):
        web.complete(replayed, params)


def test_a_code_is_spent_once_and_needs_its_verifier(web: masks.Client, fake: Fake) -> None:
    started = web.start(CALLBACK)
    params = returned(fake.authorize(started.url))
    wrong = masks.AuthorizationRequest.from_dict({**started.to_dict(), "verifier": "x" * 64})

    with pytest.raises(masks.Error) as raised:
        web.complete(wrong, params)

    assert raised.value.code == "invalid_grant"


def test_id_tokens_are_checked(web: masks.Client, fake: Fake) -> None:
    now = int(time.time())
    good = {"iss": ISSUER, "sub": "ada", "aud": "web", "exp": now + 60, "iat": now}

    assert web.verify_id_token(fake.issue(good, typ="JWT"))["sub"] == "ada"

    refused = {
        "another audience": fake.issue({**good, "aud": "other"}, typ="JWT"),
        "several audiences without azp": fake.issue({**good, "aud": ["web", "other"]}, typ="JWT"),
        "an access token": fake.issue(good),
        "expired": fake.issue({**good, "exp": now - 600}, typ="JWT"),
        "another at_hash": fake.issue({**good, "at_hash": "nope"}, typ="JWT"),
    }

    for name, token in refused.items():
        with pytest.raises(masks.InvalidToken):
            web.verify_id_token(token, access_token="access")
            pytest.fail(f"{name} was accepted")


def test_userinfo_answers_the_profile(web: masks.Client, fake: Fake) -> None:
    started = web.start(CALLBACK, scope=["openid", "profile", "email"])
    signed = web.complete(started, returned(fake.authorize(started.url)))

    assert web.userinfo(signed.token)["email"] == "ada@example.com"
    assert web.userinfo(signed.token.access_token)["sub"] == "ada"


def test_userinfo_with_a_held_token_sends_a_proof(fake: Fake, issuer: masks.Issuer) -> None:
    dpop = masks.Key.generate()
    fake.add("web", FakeClient(method="client_secret_basic", secret="secret"))
    client = masks.Client(issuer, "web", secret="secret", dpop=dpop, http=fake.http())
    started = client.start(CALLBACK)

    assert parse_qs(urlsplit(started.url).query)["dpop_jkt"] == [dpop.thumbprint]

    signed = client.complete(started, returned(fake.authorize(started.url)))

    assert signed.token.bound
    assert client.userinfo(signed.token)["sub"] == "ada"


def test_end_session_url(web: masks.Client) -> None:
    url = web.end_session_url(post_logout_redirect_uri=f"{APP}/", state="s")

    assert url.startswith(f"{ISSUER}/logout?")
    assert returned(url) == {"client_id": "web", "post_logout_redirect_uri": f"{APP}/", "state": "s"}


def test_logout_tokens_are_checked(web: masks.Client, fake: Fake) -> None:
    logout = web.verify_logout_token(fake.logout_token("web", subject="ada", sid="s-1"))

    assert (logout.subject, logout.sid) == ("ada", "s-1")

    refused = {
        "another client": fake.logout_token("other", subject="ada"),
        "no subject or session": fake.logout_token("web"),
        "a nonce": fake.logout_token("web", subject="ada", nonce="n"),
        "no event": fake.logout_token("web", subject="ada", events={"other": {}}),
        "the future": fake.logout_token("web", subject="ada", iat=int(time.time()) + 3600),
        "an ID token": fake.issue({"iss": ISSUER, "aud": "web", "sub": "ada", "iat": 1, "jti": "j"}, typ="JWT"),
    }

    for name, token in refused.items():
        with pytest.raises(masks.InvalidToken):
            web.verify_logout_token(token)
            pytest.fail(f"{name} was accepted")


def handshake(issuer: masks.Issuer, **changes: Any) -> masks.Handshake:
    options: dict[str, Any] = {
        "name": "App",
        "resource": APP,
        "redirect_uris": [CALLBACK],
        "return_to": f"{APP}/auth/handshake/callback",
        "scope": ["openid", "profile", "catalog:"],
        **changes,
    }

    return masks.Handshake(issuer, **options)


def test_a_handshake_registers_the_app(fake: Fake, issuer: masks.Issuer) -> None:
    shaking = handshake(issuer, backchannel_logout_uri=f"{APP}/auth/logout/backchannel")
    started = shaking.start()
    query = parse_qs(urlsplit(started.url).query)

    assert query["redirect_uris"] == [CALLBACK]
    assert query["scope"] == ["openid profile catalog:"]
    assert query["state"] == [started.state]

    with fake.http() as http:
        registration = shaking.complete(returned(fake.handshake(started.url)), started.state, http=http)

    assert registration.client_id == "app"
    assert registration.client_secret
    assert registration.registration_access_token
    assert fake.handshakes["app"] == "openid profile catalog:"


def test_a_handshake_registers_logout_uris_the_issuer_takes(fake: Fake, issuer: masks.Issuer) -> None:
    held = masks.Issuer(
        url=issuer.url,
        metadata=masks.Metadata(issuer=issuer.url, handshake_endpoint=f"{ISSUER}/handshake"),
    )
    shaking = handshake(
        held,
        backchannel_logout_uri=f"{APP}/auth/logout/backchannel",
        post_logout_redirect_uri=f"{APP}/auth/logout/return",
    )
    query = parse_qs(urlsplit(shaking.start().url).query)

    assert "backchannel_logout_uri" not in query
    assert query["post_logout_redirect_uri"] == [f"{APP}/auth/logout/return"]
    assert shaking.metadata().post_logout_redirect_uris == [f"{APP}/auth/logout/return"]

    with pytest.raises(ValueError):
        handshake(issuer, post_logout_redirect_uri="https://elsewhere.example/bye")


@pytest.mark.parametrize(
    ("changes", "code"),
    [({"state": "forged"}, "invalid_state"), ({"iss": "https://elsewhere.example"}, "invalid_issuer")],
)
def test_a_handshake_refuses_a_forged_answer(
    fake: Fake, issuer: masks.Issuer, changes: dict[str, str], code: str
) -> None:
    shaking = handshake(issuer)
    started = shaking.start()
    params = {**returned(fake.handshake(started.url)), **changes}

    with pytest.raises(masks.Error) as raised, fake.http() as http:
        shaking.complete(params, started.state, http=http)

    assert raised.value.code == code


def test_a_declined_handshake_raises(issuer: masks.Issuer) -> None:
    with pytest.raises(masks.Error) as raised:
        handshake(issuer).complete({"error": "access_denied", "state": "s"}, "s")

    assert raised.value.code == "access_denied"


@pytest.mark.parametrize(
    "changes",
    [
        {"return_to": "https://elsewhere.example/callback"},
        {"redirect_uris": ["https://elsewhere.example/callback"]},
        {"redirect_uris": []},
        {"resource": "app.example"},
        {"resource": "http://app.example"},
        {"scope": []},
    ],
)
def test_a_handshake_shares_one_origin(issuer: masks.Issuer, changes: dict[str, Any]) -> None:
    with pytest.raises((ValueError, masks.InsecureURL)):
        handshake(issuer, **changes)


def test_a_delegation_holds_a_connection_and_releases_upstream_tokens(web: masks.Client, fake: Fake) -> None:
    started = web.start_delegation("github", CALLBACK)

    assert "masks:delegate:github" in started.scopes
    assert started.provider == "github"

    held = web.finish_delegation(started, returned(fake.authorize(started.url)))

    assert held.provider == "github"
    assert held.secret
    assert held.secret not in repr(held)

    upstream = web.delegated_token(held.secret, connection=held.connection)

    assert upstream.access_token == "upstream-token"
    assert upstream.secret and upstream.secret != held.secret
    assert not upstream.expired()

    with pytest.raises(masks.DelegationRefused) as raised:
        web.delegated_token(held.secret, connection=held.connection)

    assert raised.value.code == "invalid_grant"
    assert raised.value.secret == ""


def test_a_delegation_that_masks_cannot_serve_is_unavailable(web: masks.Client, fake: Fake) -> None:
    started = web.start_delegation("github", CALLBACK)
    held = web.finish_delegation(started, returned(fake.authorize(started.url)))
    fake.unavailable_tokens = True

    with pytest.raises(masks.DelegationUnavailable):
        web.delegated_token(held.secret, connection=held.connection)


def test_a_delegation_refuses_a_sign_in_without_a_connection(web: masks.Client, fake: Fake) -> None:
    started = web.start_delegation("github", CALLBACK)
    params = returned(fake.authorize(started.url))
    plain = masks.AuthorizationRequest.from_dict({**started.to_dict(), "provider": "gitlab"})

    with pytest.raises(masks.DelegationRefused) as raised:
        web.finish_delegation(plain, params)

    assert raised.value.code == "access_denied"


def test_an_unreachable_issuer_is_an_unavailable_delegation(issuer: masks.Issuer) -> None:
    def handle(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("refused", request=request)

    client = masks.Client(issuer, "web", secret="s", http=httpx.Client(transport=httpx.MockTransport(handle)))

    with pytest.raises(masks.DelegationUnavailable):
        client.delegated_token("secret", connection="c")


@pytest.mark.anyio
async def test_the_async_client_signs_in(fake: Fake, issuer: masks.Issuer) -> None:
    fake.add("web", FakeClient(method="client_secret_basic", secret="secret"))

    async with masks.AsyncClient(issuer, "web", secret="secret", http=fake.async_http()) as client:
        started = client.start(CALLBACK)
        signed = await client.complete(started, returned(fake.authorize(started.url)))
        profile = await client.userinfo(signed.token)
        logout = await client.verify_logout_token(fake.logout_token("web", sid="s"))
        delegation = client.start_delegation("github", CALLBACK)
        held = await client.finish_delegation(delegation, returned(fake.authorize(delegation.url)))
        upstream = await client.delegated_token(held.secret, connection=held.connection)

    async with fake.async_http() as http:
        shaking = handshake(issuer)
        begun = shaking.start()
        registration = await shaking.acomplete(returned(fake.handshake(begun.url)), begun.state, http=http)

    assert profile["sub"] == signed.subject == "ada"
    assert logout.sid == "s"
    assert upstream.access_token == "upstream-token"
    assert registration.client_id == "app"
