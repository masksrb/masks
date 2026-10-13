from __future__ import annotations

import json
import re
import secrets
import time
from collections.abc import Callable, MutableMapping
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


def note(session: MutableMapping[str, Any], size: str | None) -> dict[str, int]:
    if size is not None:
        session["note"] = secrets.token_hex(int(size) // 2)

    return {"note": len(session.get("note", ""))}


def connection(held: masks.HeldConnection) -> dict[str, Any]:
    return {
        "connection": held.connection,
        "provider": held.provider,
        "account": held.account,
        "secret": bool(held.secret),
    }


def config(fake: Fake, **changes: Any) -> Config:
    fake.add("web", FakeClient(method="client_secret_basic", secret="secret"))
    options: dict[str, Any] = {
        "issuer": ISSUER,
        "secret": SECRET,
        "resource": APP,
        "credentials": MemoryCredentials("web", "secret"),
        "scope": ["openid", "profile", "email", "offline_access", "organization"],
        "privileges": PRIVILEGES,
        "manages": lambda actor: actor.subject == "ada",
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
    assert re.fullmatch(r"1\.[\w-]+", cookie.split(";")[0].removeprefix("__Host-masks="))

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
    assert "error" not in missing.headers["www-authenticate"]

    good = fake.access_token("caller", "catalog:read", "", subject="ada", audience=APP)

    assert browser.get("/api/catalog", {"Authorization": f"Bearer {good}"}).json()["subject"] == "ada"

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
    assert credentials.read()["issuer"] == ISSUER
    assert sign_in(browser, fake).location == "/"
    assert browser.get("/auth/handshake", JSON).json()["client_id"] == "app"


def refuses_credentials_from_another_issuer(build: Build, fake: Fake) -> None:
    elsewhere = MemoryCredentials("web", "secret", issuer="https://elsewhere.example")
    browser = build(config(fake, credentials=elsewhere))
    refused = browser.get("/auth", JSON)

    assert refused.status == 500
    assert "another issuer" in refused.json()["error_description"]
    assert browser.get("/auth/handshake", JSON).status == 500


def shows_no_error_from_a_sign_in_this_browser_did_not_start(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    forged = browser.get("/auth/callback?error=access_denied&error_description=Call+555-0100+now&state=forged", HTML)

    assert forged.status == 400
    assert b"555-0100" not in forged.body
    assert b"invalid_state" in forged.body


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
    assert browser.get("/auth/avatar?size=64").status == 200
    assert browser.get("/auth/avatar?size=" + "9" * 5000).status == 200


class RecordingStore(MemorySessionStore):
    def __init__(self) -> None:
        super().__init__()
        self.reads = 0

    def read(self, key: str) -> dict[str, Any] | None:
        self.reads += 1
        return super().read(key)


def shows_the_avatar_route_as_the_picture(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)
    me = browser.get("/me").json()

    assert me["picture"] == "/auth/avatar"
    assert me["avatars"]["photo"] == f"{ISSUER}/avatars/ada/photo"


def refuses_a_sign_out_from_another_site(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)

    assert browser.post("/auth/logout", {**JSON, "Origin": "https://evil.example"}).status == 403
    assert browser.post("/auth/logout", {**JSON, "Sec-Fetch-Site": "cross-site"}).status == 403
    assert browser.get("/auth/logout?everywhere=1", {**HTML, "Sec-Fetch-Site": "cross-site"}).status == 403
    assert browser.get("/me").status == 200
    assert browser.post("/auth/logout", {**JSON, "Origin": APP}).json() == {"signed_in": False}


def signs_out_everywhere(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)
    upstream = browser.post("/auth/logout?everywhere=1", HTML).location
    query = parse_qs(urlsplit(upstream).query)

    assert upstream.startswith(f"{ISSUER}/logout?")
    assert query["post_logout_redirect_uri"] == [f"{APP}/auth/logout/return"]
    assert browser.get("/me", JSON).status == 401
    assert browser.get(f"/auth/logout/return?state={query['state'][0]}", HTML).location == "/"
    assert browser.get(f"/auth/logout/return?state={query['state'][0]}", JSON).status == 400


def restarts_a_forged_state_once(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    begun = browser.get("/auth", HTML).location
    callback = fake.authorize(begun).replace("state=", "state=x")

    assert browser.get(callback, HTML).location == "/auth"
    assert browser.get(callback, JSON).json()["error"] == "invalid_state"


def keeps_a_handshake_to_its_browser(build: Build, fake: Fake) -> None:
    settings = config(fake, credentials=MemoryCredentials())
    begun = build(settings).get("/auth/handshake", HTML).location

    assert build(settings).get(fake.handshake(begun), JSON).json()["error"] == "invalid_state"


def lets_only_a_manager_change_the_connection(build: Build, fake: Fake) -> None:
    credentials = MemoryCredentials()
    browser = build(config(fake, credentials=credentials))
    browser.get(fake.handshake(browser.get("/auth/handshake", HTML).location), HTML)

    assert browser.get("/auth/handshake", HTML).location == "/"

    sign_in(browser, fake, subject="bob")

    assert browser.get("/auth/handshake", JSON).status == 403
    assert browser.post("/auth/handshake/disconnect", JSON).status == 403

    sign_in(browser, fake)
    page = browser.get("/auth/handshake", HTML)

    assert f"form-action 'self' {ISSUER};" in page.headers["content-security-policy"]
    assert b"Reconnect" in page.body
    assert browser.post("/auth/handshake/disconnect", JSON).json()["connected"] is False
    assert credentials.read() == {}


def uses_a_logout_token_once(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    held = fake.logout_token("web", subject="ada")

    assert browser.post("/auth/logout/backchannel", data={"logout_token": held}).status == 200

    reused = browser.post("/auth/logout/backchannel", data={"logout_token": held})

    assert reused.status == 400
    assert "already used" in reused.json()["error_description"]


def refuses_a_large_back_channel_request(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    answered = browser.post("/auth/logout/backchannel", data={"logout_token": "a" * (70 * 1024)})

    assert answered.status == 413


def reads_no_session_for_a_route_that_needs_none(build: Build, fake: Fake) -> None:
    store = RecordingStore()
    browser = build(config(fake, sessions=ServerSessions(store)))
    sign_in(browser, fake)
    reads = store.reads
    plain = browser.get("/plain")

    assert plain.status == 200
    assert store.reads == reads
    assert not plain.cookies


def keeps_a_refreshed_session_out_of_shared_caches(build: Build, fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)

    assert browser.get("/public").headers["cache-control"] == "public, max-age=600"

    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)
    refreshed = browser.get("/public")

    assert refreshed.json() == {"signed_in": True}
    assert refreshed.cookies
    assert refreshed.headers["cache-control"] == "no-store"


def delegating(fake: Fake) -> Config:
    return config(fake, delegation_redirect_uri="/connected")


def connects_a_provider(build: Build, fake: Fake) -> None:
    browser = build(delegating(fake))
    sign_in(browser, fake)
    started = browser.get("/connect?provider=github", HTML)

    assert "masks%3Adelegate%3Agithub" in started.location
    assert "redirect_uri=https%3A%2F%2Fapp.example%2Fconnected" in started.location

    returned = fake.authorize(started.location, "ada")
    connected = browser.get(returned, HTML)

    assert connected.status == 200, connected.body
    assert connected.json() == {
        "connection": "c0ffee00-0000-4000-8000-000000000001",
        "provider": "github",
        "account": "ada",
        "secret": True,
    }
    assert browser.get(returned, HTML).json() == {"error": "invalid_state"}


def sends_a_visitor_to_sign_in_before_connecting(build: Build, fake: Fake) -> None:
    browser = build(delegating(fake))

    assert browser.get("/connect?provider=github", HTML).location == "/auth"
    assert browser.get("/connect?provider=github", JSON).json()["error"] == "login_required"


def refuses_a_connection_masks_made_for_another_account(build: Build, fake: Fake) -> None:
    browser = build(delegating(fake))
    sign_in(browser, fake)
    started = browser.get("/connect?provider=github", HTML)

    assert browser.get(fake.authorize(started.location, "bob"), HTML).json() == {"error": "access_denied"}


def keeps_a_connection_to_its_browser(build: Build, fake: Fake) -> None:
    browser = build(delegating(fake))
    other = build(delegating(fake))
    sign_in(browser, fake)
    sign_in(other, fake)
    started = browser.get("/connect?provider=github", HTML)

    assert other.get(fake.authorize(started.location, "ada"), HTML).json() == {"error": "invalid_state"}


def forgets_a_connection_when_someone_else_signs_in(build: Build, fake: Fake) -> None:
    browser = build(delegating(fake))
    sign_in(browser, fake)
    started = browser.get("/connect?provider=github", HTML)
    sign_in(browser, fake, "bob")

    assert browser.get(fake.authorize(started.location, "ada"), HTML).json() == {"error": "invalid_state"}


def passes_on_a_provider_refusal(build: Build, fake: Fake) -> None:
    browser = build(delegating(fake))
    sign_in(browser, fake)
    started = browser.get("/connect?provider=github", HTML)
    state = parse_qs(urlsplit(started.location).query)["state"][0]

    assert browser.get(f"/connected?error=access_denied&state={state}", HTML).json() == {"error": "access_denied"}
    assert browser.get(fake.authorize(started.location, "ada"), HTML).json() == {"error": "invalid_state"}


def keeps_a_large_session_in_several_cookies(build: Build, fake: Fake) -> None:
    browser = build(config(fake))
    sign_in(browser, fake)
    grown = browser.get("/note?size=9000")

    assert [cookie.split("=")[0] for cookie in grown.cookies] == ["__Host-masks", "__Host-masks-1", "__Host-masks-2"]
    assert browser.get("/note").json() == {"note": 9000}
    assert browser.get("/me").json()["subject"] == "ada"

    shrunk = browser.get("/note?size=0")
    cleared = [cookie.split("=")[0] for cookie in shrunk.cookies if "max-age=0" in cookie.lower()]

    assert len(shrunk.cookies) == 3
    assert cleared == ["__Host-masks-1", "__Host-masks-2"]
    assert browser.get("/note").json() == {"note": 0}
    assert browser.get("/me").json()["subject"] == "ada"


SCENARIOS = [
    signs_in_and_out,
    keeps_return_to_local,
    steps_up_for_a_privilege,
    refuses_a_privilege_masks_withheld,
    checks_roles,
    protects_an_api,
    answers_503_when_the_keys_are_down,
    shakes_hands,
    refuses_credentials_from_another_issuer,
    shows_no_error_from_a_sign_in_this_browser_did_not_start,
    ends_sessions_from_the_back_channel,
    proxies_the_avatar,
    shows_the_avatar_route_as_the_picture,
    refuses_a_sign_out_from_another_site,
    signs_out_everywhere,
    restarts_a_forged_state_once,
    keeps_a_handshake_to_its_browser,
    lets_only_a_manager_change_the_connection,
    uses_a_logout_token_once,
    refuses_a_large_back_channel_request,
    reads_no_session_for_a_route_that_needs_none,
    connects_a_provider,
    sends_a_visitor_to_sign_in_before_connecting,
    refuses_a_connection_masks_made_for_another_account,
    keeps_a_connection_to_its_browser,
    forgets_a_connection_when_someone_else_signs_in,
    passes_on_a_provider_refusal,
    keeps_a_large_session_in_several_cookies,
]

TIMED = [refreshes_and_forgets, keeps_a_refreshed_session_out_of_shared_caches]
