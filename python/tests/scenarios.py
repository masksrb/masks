from __future__ import annotations

import json
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest

import masks
from masks.web import Config, MemoryCredentials, MemorySessionStore, ServerSessions

from .fake import ISSUER, Fake, FakeClient

APP = "https://app.example"
SECRET = "s" * 32
PRIVILEGES = {
    "read": ["catalog:read"],
    "admin": ["catalog:admin"],
    "billing": {"role": ["owner", "billing"]},
}
HTML = {"Accept": "text/html"}
JSON = {"Accept": "application/json"}


@dataclass
class Answered:
    status: int
    headers: httpx.Headers
    body: bytes

    def json(self) -> Any:
        return json.loads(self.body)

    @property
    def location(self) -> str:
        assert self.status in (302, 303), (self.status, self.body[:300])
        return self.headers["location"]

    @property
    def cookies(self) -> list[str]:
        return self.headers.get_list("set-cookie")


class Browser(Protocol):
    def get(self, target: str, headers: dict[str, str] | None = None) -> Answered: ...

    def post(
        self, target: str, headers: dict[str, str] | None = None, data: dict[str, str] | None = None
    ) -> Answered: ...


Build = Callable[[Config], Browser]


def config(fake: Fake, **changes: Any) -> Config:
    fake.add("web", FakeClient(method="client_secret_basic", secret="secret"))
    options: dict[str, Any] = {
        "issuer": ISSUER,
        "secret": SECRET,
        "resource": APP,
        "credentials": MemoryCredentials("web", "secret"),
        "scope": ["openid", "profile", "email", "offline_access", "organization"],
        "privileges": PRIVILEGES,
        "manages": lambda person: person.subject == "ada",
        "http": fake.http(),
        **changes,
    }

    return Config(**options)


def sign_in(browser: Browser, fake: Fake, subject: str = "ada", target: str = "/auth") -> Answered:
    begun = browser.get(target, HTML)

    return browser.get(fake.authorize(begun.location, subject), HTML)


def signs_in_and_out(build: Build, fake: Fake) -> None:
    browser = build(config(fake))

    assert browser.get("/me", HTML).location == "/auth"
    assert browser.get("/me", JSON).json()["error"] == "login_required"

    landed = sign_in(browser, fake)

    assert landed.location == "/me"
    cookie = next(held for held in landed.cookies if held.startswith("__Host-masks="))
    assert "HttpOnly" in cookie and "Secure" in cookie and "SameSite=Lax" in cookie
    assert "eyJ" not in cookie

    me = browser.get("/me").json()
    assert me["subject"] == "ada"
    assert me["organizations"][0]["key"] == "acme"
    assert browser.get("/auth/session").json()["signed_in"] is True

    revoked = len(fake.revoked)
    assert browser.post("/auth/logout", JSON).json() == {"signed_in": False}
    assert len(fake.revoked) == revoked + 1
    assert browser.get("/me", JSON).status == 401


def keeps_return_to_local(build: Build, fake: Fake) -> None:
    browser = build(config(fake))

    assert sign_in(browser, fake, target="/auth?return_to=https://evil.example/").location == "/"
    assert sign_in(browser, fake, target="/auth?return_to=/reports%3Fpage%3D2").location == "/reports?page=2"


def steps_up_for_a_privilege(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)
    stepped = browser.get("/admin", HTML).location
    begun = browser.get(stepped, HTML).location

    assert "catalog:admin" in parse_qs(urlsplit(begun).query)["scope"][0]
    assert browser.get(fake.authorize(begun), HTML).location == "/admin"
    assert browser.get("/admin").json() == {"privileges": ["admin"]}


def refuses_a_privilege_masks_withheld(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake, subject="bob")
    stepped = browser.get("/admin", HTML).location
    browser.get(fake.authorize(browser.get(stepped, HTML).location, "bob"), HTML)

    refused = browser.get("/admin", JSON)

    assert refused.status == 403
    assert refused.json()["error"] == "insufficient_scope"


def checks_roles(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)

    assert browser.get("/billing", JSON).json()["error"] == "insufficient_organization"

    sign_in(browser, fake, target="/auth?organization=acme")

    assert browser.get("/billing").json() == {"role": "owner"}

    sign_in(browser, fake, target="/auth?organization=globex")

    assert browser.get("/billing", JSON).json()["error"] == "insufficient_role"


def refreshes_and_forgets(build: Build, fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)

    assert browser.get("/me").json()["subject"] == "ada"

    fake.clients["web"].refresh.clear()
    later += 7200

    assert browser.get("/me", JSON).status == 401


def protects_an_api(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    missing = browser.get("/api/catalog")

    assert missing.status == 401
    assert "resource_metadata=" in missing.headers["www-authenticate"]

    good = fake.access_token("caller", "catalog:read", "", subject="ada", audience=APP)

    assert browser.get("/api/catalog", {"Authorization": f"Bearer {good}"}).json() == {"subject": "ada"}

    narrow = fake.access_token("caller", "profile", "", audience=APP)

    assert browser.get("/api/catalog", {"Authorization": f"Bearer {narrow}"}).status == 403

    dpop = masks.Key.generate()
    held = fake.access_token("caller", "catalog:read", dpop.thumbprint, audience=APP)
    proven = {"Authorization": f"DPoP {held}", "DPoP": masks.proof(dpop, "GET", f"{APP}/api/catalog", held)}

    assert browser.get("/api/catalog", proven).status == 200
    assert browser.get("/api/catalog", proven).status == 401

    assert browser.get("/.well-known/oauth-protected-resource").json()["resource"] == APP


def answers_503_when_the_keys_are_down(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    fake.keys_down = True
    token = fake.access_token("caller", "catalog:read", "", audience=APP)
    unavailable = browser.get("/api/catalog", {"Authorization": f"Bearer {token}"})

    assert unavailable.status == 503
    assert "www-authenticate" not in unavailable.headers


def shakes_hands(build: Build, fake: Fake) -> None:
    credentials = MemoryCredentials()
    browser = build(config(fake, credentials=credentials))

    assert browser.get("/me", HTML).location == "/auth/handshake"

    begun = browser.get("/auth/handshake", HTML).location

    assert parse_qs(urlsplit(begun).query)["return_to"] == [f"{APP}/auth/handshake/callback"]
    assert browser.get(fake.handshake(begun), HTML).location == "/auth"
    assert credentials.read()["client_id"] == "app"
    assert sign_in(browser, fake).location == "/"
    assert browser.get("/auth/handshake", JSON).json()["client_id"] == "app"


def ends_sessions_from_the_back_channel(build: Build, fake: Fake) -> None:
    browser = build(config(fake, sessions=ServerSessions(MemorySessionStore())))
    sign_in(browser, fake)

    assert browser.get("/me").status == 200

    ended = browser.post("/auth/logout/backchannel", data={"logout_token": fake.logout_token("web", subject="ada")})

    assert ended.status == 200
    assert browser.get("/me", JSON).status == 401


def proxies_the_avatar(build: Build, fake: Fake) -> None:
    browser = build(config(fake))

    assert browser.get("/auth/avatar").status == 404

    sign_in(browser, fake)
    photo = browser.get("/auth/avatar")

    assert photo.status == 200
    assert photo.body == fake.photo


SCENARIOS = [
    signs_in_and_out,
    keeps_return_to_local,
    steps_up_for_a_privilege,
    refuses_a_privilege_masks_withheld,
    checks_roles,
    protects_an_api,
    answers_503_when_the_keys_are_down,
    shakes_hands,
    ends_sessions_from_the_back_channel,
    proxies_the_avatar,
]
