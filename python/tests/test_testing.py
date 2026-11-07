from __future__ import annotations

from urllib.parse import parse_qsl, urlsplit

import masks
from masks.testing import ISSUER, Fake, FakeClient

CALLBACK = "https://app.example/auth/callback"


def signed_in(fake: Fake) -> tuple[masks.Client, masks.SignIn]:
    fake.add("app", FakeClient(method="client_secret_basic", secret="secret"))
    http = fake.http()
    client = masks.Client(masks.discover(ISSUER, http=http), "app", secret="secret", http=http)
    started = client.start(CALLBACK, scope=["openid", "offline_access"])
    answered = dict(parse_qsl(urlsplit(fake.authorize(started.url, subject="bob")).query))

    return client, client.complete(started, answered)


def test_a_sign_in_completes_against_the_fake() -> None:
    _, signed = signed_in(Fake())

    assert signed.subject == "bob"
    assert signed.claims["iss"] == ISSUER
    assert signed.token.id_token


def test_a_refresh_against_the_fake_rotates_the_token() -> None:
    client, signed = signed_in(Fake())
    renewed = client.refresh(signed.token.refresh_token or "")

    assert renewed.access_token != signed.token.access_token
    assert renewed.refresh_token
    assert renewed.refresh_token != signed.token.refresh_token


def test_a_logout_token_from_the_fake_verifies() -> None:
    fake = Fake()
    client, signed = signed_in(fake)
    logout = client.verify_logout_token(fake.logout_token("app", subject="bob", sid=str(signed.claims["sid"])))

    assert logout.subject == "bob"
    assert logout.sid == signed.claims["sid"]
