import dataclasses
import time
from collections.abc import Callable, Iterator, Mapping
from typing import Annotated, Any
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse, Response
from fastapi.testclient import TestClient

import masks
from masks.fastapi import Masks
from masks.web import Config, MemoryCredentials, MemorySessionStore, Person, ServerSessions

from . import scenarios
from .fake import AUDIENCE, ISSUER, Fake, FakeClient
from .scenarios import Answered

APP = "https://app.example"
SECRET = "s" * 32
PRIVILEGES = {
    "read": ["catalog:read"],
    "admin": ["catalog:admin"],
    "billing": {"role": ["owner", "billing"]},
    "acme_admin": {"scope": ["catalog:admin"], "role": "owner", "organization": "acme"},
}
HTML = {"Accept": "text/html"}
JSON = {"Accept": "application/json"}


def build(fake: Fake, credentials: Any = None, **changes: Any) -> tuple[FastAPI, Masks]:
    fake.add("web", FakeClient(method="client_secret_basic", secret="secret"))
    options: dict[str, Any] = {
        "issuer": ISSUER,
        "secret": SECRET,
        "resource": APP,
        "credentials": credentials if credentials is not None else MemoryCredentials("web", "secret"),
        "scope": ["openid", "profile", "email", "offline_access", "organization"],
        "privileges": PRIVILEGES,
        "manages": lambda person: person.subject == "ada",
        "http": fake.http(),
        "async_http": fake.async_http(),
        **changes,
    }

    return application(Config(**options))


def application(config: Config) -> tuple[FastAPI, Masks]:
    auth = Masks(config)
    app = FastAPI()
    auth.install(app)

    @app.get("/me")
    async def me(person: Annotated[Person, Depends(auth.require())]) -> dict[str, Any]:
        return person.to_dict()

    @app.get("/admin")
    async def admin(person: Annotated[Person, Depends(auth.require("admin"))]) -> dict[str, Any]:
        return {"privileges": person.privileges}

    @app.get("/billing")
    async def billing(person: Annotated[Person, Depends(auth.require("billing"))]) -> dict[str, Any]:
        return {"role": person.organization.role if person.organization else None}

    @app.get("/public")
    async def public(person: Annotated[Person, Depends(auth.person)]) -> Response:
        return JSONResponse({"signed_in": person.signed_in}, headers={"Cache-Control": "public, max-age=600"})

    @app.get("/plain")
    async def plain() -> dict[str, Any]:
        return {"plain": True}

    @app.get("/note")
    async def note(request: Request, size: str | None = None) -> dict[str, int]:
        return scenarios.note(await auth.session(request), size)

    @app.get("/connect")
    async def connect(request: Request, provider: str) -> Response:
        return await auth.start_delegation(request, provider)

    @app.get("/connected")
    async def connected(request: Request) -> Response:
        try:
            return JSONResponse(scenarios.connection(await auth.finish_delegation(request)))
        except masks.DelegationRefused as error:
            return JSONResponse({"error": error.code}, status_code=400)

    @app.get("/whoami")
    async def whoami(person: Annotated[Person, Depends(auth.person)]) -> dict[str, Any]:
        return {"signed_in": person.signed_in}

    @app.get("/api/catalog")
    async def catalog(person: Annotated[Person, Depends(auth.protect("read"))]) -> dict[str, Any]:
        return {"subject": person.subject, "by_token": person.by_token}

    @app.get("/either")
    async def either(person: Annotated[Person, Depends(auth.require("read", tokens=True))]) -> dict[str, Any]:
        return {"subject": person.subject, "by_token": person.by_token}

    @app.get("/client")
    async def client(request: Request) -> dict[str, Any]:
        held = await auth.client(request)
        started = held.start_delegation("github", f"{APP}/connected")

        return {"client_id": held.client_id, "provider": started.provider}

    return app, auth


@pytest.fixture
def app(fake: Fake) -> Iterator[TestClient]:
    application, _ = build(fake)

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        yield client


class FastAPIBrowser:
    def __init__(self, config: Config, fake: Fake) -> None:
        app, _ = application(dataclasses.replace(config, async_http=fake.async_http()))
        self.client = TestClient(app, base_url=APP, follow_redirects=False)

    def _answered(self, sent: Any) -> Answered:
        return Answered(sent.status_code, sent.headers, sent.content)

    def get(self, target: str, headers: dict[str, str] | None = None) -> Answered:
        return self._answered(self.client.get(target, headers=headers or {}))

    def post(self, target: str, headers: dict[str, str] | None = None, data: dict[str, str] | None = None) -> Answered:
        return self._answered(self.client.post(target, headers=headers or {}, data=data))


@pytest.mark.parametrize("scenario", scenarios.SCENARIOS, ids=lambda scenario: scenario.__name__)
def test_fastapi(scenario: Callable[..., None], fake: Fake) -> None:
    scenario(lambda config: FastAPIBrowser(config, fake), fake)


@pytest.mark.parametrize("scenario", scenarios.TIMED, ids=lambda scenario: scenario.__name__)
def test_fastapi_over_time(scenario: Callable[..., None], fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    scenario(lambda config: FastAPIBrowser(config, fake), fake, monkeypatch)


def location(response: Any) -> str:
    assert response.status_code in (302, 303), response.text
    return str(response.headers["location"])


def sign_in(client: TestClient, fake: Fake, subject: str = "ada", path: str = "/auth", **query: str) -> Any:
    begun = client.get(path, params=query, headers=HTML)
    callback = fake.authorize(location(begun), subject)

    return client.get(callback, headers=HTML)


def test_a_visitor_is_sent_through_masks_and_back(app: TestClient, fake: Fake) -> None:
    assert location(app.get("/me", headers=HTML)) == "/auth"

    landed = sign_in(app, fake)

    assert location(landed) == "/me"
    me = app.get("/me").json()
    assert me["subject"] == "ada"
    assert me["name"] == "Ada Lovelace"
    assert me["email"] == "ada@example.com"
    assert me["account_url"] == f"{ISSUER}/"
    assert [held["key"] for held in me["organizations"]] == ["acme", "globex"]
    assert me["picture"] == "/auth/avatar"
    assert me["avatars"]["photo"] == f"{ISSUER}/avatars/ada/photo"


def test_a_json_request_gets_401_with_a_login_url(app: TestClient) -> None:
    refused = app.get("/me", headers=JSON)

    assert refused.status_code == 401
    assert refused.json() == {"signed_in": False, "error": "login_required", "login_url": "/auth"}
    assert app.get("/auth/session").status_code == 401


def test_the_session_cookie_is_sealed_and_strict(app: TestClient, fake: Fake) -> None:
    landed = sign_in(app, fake)
    cookie = landed.headers["set-cookie"]

    assert "HttpOnly" in cookie and "Secure" in cookie and "SameSite=Lax" in cookie
    assert "ada" not in cookie and "eyJ" not in cookie

    session = app.get("/auth/session")

    assert session.headers["cache-control"] == "no-store"
    assert session.json()["signed_in"] is True
    assert "access_token" not in session.text


def test_a_tampered_cookie_is_a_signed_out_visitor(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)
    held = app.cookies["__Host-masks"]
    app.cookies.set("__Host-masks", held[:-4] + ("AAAA" if not held.endswith("AAAA") else "BBBB"), domain="app.example")

    assert app.get("/whoami").json() == {"signed_in": False}


def test_return_to_stays_on_this_site(app: TestClient, fake: Fake) -> None:
    for unsafe in ("https://evil.example/", "//evil.example", "/\\evil.example", "/ok\x00"):
        assert location(sign_in(app, fake, return_to=unsafe)) == "/"

    assert location(sign_in(app, fake, return_to="/reports?page=2")) == "/reports?page=2"


def test_several_sign_ins_can_be_in_flight(app: TestClient, fake: Fake) -> None:
    first = location(app.get("/auth", params={"return_to": "/one"}, headers=HTML))
    second = location(app.get("/auth", params={"return_to": "/two"}, headers=HTML))

    assert location(app.get(fake.authorize(first), headers=HTML)) == "/one"
    assert location(app.get(fake.authorize(second), headers=HTML)) == "/two"


def test_a_forged_state_restarts_once_and_then_refuses(app: TestClient, fake: Fake) -> None:
    begun = location(app.get("/auth", headers=HTML))
    callback = fake.authorize(begun).replace("state=", "state=x")

    assert location(app.get(callback, headers=HTML)) == "/auth"
    assert app.get(callback, headers=HTML).status_code == 400
    assert app.get(callback, headers=JSON).json()["error"] == "invalid_state"


def test_an_error_from_masks_is_shown(app: TestClient) -> None:
    refused = app.get("/auth/callback", params={"error": "access_denied", "error_description": "no"}, headers=JSON)

    assert refused.status_code == 400
    assert refused.json()["error"] == "access_denied"


def test_signing_in_to_an_organization(app: TestClient, fake: Fake) -> None:
    begun = location(app.get("/auth", params={"organization": "Globex"}, headers=HTML))

    assert parse_qs(urlsplit(begun).query)["organization"] == ["globex"]

    app.get(fake.authorize(begun), headers=HTML)

    assert app.get("/me").json()["organization"]["key"] == "globex"
    assert app.get("/billing", headers=JSON).json()["error"] == "insufficient_role"


def test_a_role_in_the_organization_is_a_privilege(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake, organization="acme")

    assert app.get("/billing").json() == {"role": "owner"}


def test_a_role_without_an_organization_is_refused(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    refused = app.get("/billing", headers=JSON)

    assert refused.status_code == 403
    assert refused.json()["error"] == "insufficient_organization"
    assert app.get("/billing", headers=HTML).status_code == 403


def test_a_missing_privilege_asks_masks_once(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    stepped = location(app.get("/admin", headers=HTML))
    query = parse_qs(urlsplit(stepped).query)

    assert stepped.startswith("/auth?")
    assert query == {"return_to": ["/admin"], "privilege": ["admin"]}

    begun = location(app.get(stepped, headers=HTML))

    assert "catalog:admin" in parse_qs(urlsplit(begun).query)["scope"][0]
    assert location(app.get(fake.authorize(begun), headers=HTML)) == "/admin"
    assert app.get("/admin").json() == {"privileges": ["admin"]}


def test_a_privilege_masks_does_not_grant_is_refused_without_a_loop(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake, subject="bob")

    stepped = location(app.get("/admin", headers=HTML))
    app.get(fake.authorize(location(app.get(stepped, headers=HTML)), "bob"), headers=HTML)

    refused = app.get("/admin", headers=JSON)

    assert refused.status_code == 403
    assert refused.json()["error"] == "insufficient_scope"


def test_a_json_request_missing_a_privilege_gets_the_login_url(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    refused = app.get("/admin", headers=JSON)

    assert refused.status_code == 403
    assert refused.json() == {
        "error": "privilege_required",
        "privileges": ["admin"],
        "login_url": "/auth?return_to=%2Fadmin&privilege=admin",
    }


def test_signing_out_revokes_the_refresh_token(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)
    revoked = len(fake.revoked)

    assert location(app.post("/auth/logout", headers=HTML)) == "/"
    assert len(fake.revoked) == revoked + 1
    assert app.get("/whoami").json() == {"signed_in": False}


def test_signing_out_everywhere_goes_through_masks(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    upstream = location(app.get("/auth/logout", params={"everywhere": "1"}, headers=HTML))
    query = parse_qs(urlsplit(upstream).query)

    assert upstream.startswith(f"{ISSUER}/logout?")
    assert query["post_logout_redirect_uri"] == [f"{APP}/auth/logout/return"]
    assert app.get("/whoami").json() == {"signed_in": False}

    back = app.get("/auth/logout/return", params={"state": query["state"][0]}, headers=HTML)

    assert location(back) == "/"
    assert app.get("/auth/logout/return", params={"state": query["state"][0]}, headers=JSON).status_code == 400
    assert app.get("/auth/logout/return", params={"state": "forged"}, headers=JSON).json()["error"] == "invalid_state"
    assert app.post("/auth/logout", headers=JSON).json() == {"signed_in": False}


def test_a_cross_site_request_cannot_sign_anyone_out(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    for method in ("GET", "POST"):
        refused = app.request(
            method, "/auth/logout", params={"everywhere": "1"}, headers={**HTML, "Sec-Fetch-Site": "cross-site"}
        )

        assert refused.status_code == 403

    assert app.get("/whoami").json() == {"signed_in": True}
    assert location(app.get("/auth/logout", headers={**HTML, "Sec-Fetch-Site": "same-origin"})) == "/"


def test_a_refresh_masks_cannot_serve_keeps_the_session(
    app: TestClient, fake: Fake, monkeypatch: pytest.MonkeyPatch
) -> None:
    sign_in(app, fake)
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)
    fake.unavailable_tokens = True

    assert app.get("/whoami").json() == {"signed_in": False}

    fake.unavailable_tokens = False

    assert app.get("/whoami").json() == {"signed_in": True}


def test_signing_out_from_another_site_is_refused(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    refused = app.post("/auth/logout", headers={**JSON, "Origin": "https://evil.example"})

    assert refused.status_code == 403
    assert app.get("/whoami").json() == {"signed_in": True}


def test_an_expired_token_is_refreshed_with_the_identity(
    app: TestClient, fake: Fake, monkeypatch: pytest.MonkeyPatch
) -> None:
    sign_in(app, fake)
    calls = fake.userinfo_calls
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)

    assert app.get("/me").json()["subject"] == "ada"
    assert fake.userinfo_calls == calls + 1
    assert app.get("/me").status_code == 200
    assert fake.userinfo_calls == calls + 1


def test_a_refreshed_session_never_reaches_a_shared_cache(
    app: TestClient, fake: Fake, monkeypatch: pytest.MonkeyPatch
) -> None:
    sign_in(app, fake)

    assert app.get("/public").headers["cache-control"] == "public, max-age=600"

    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)
    refreshed = app.get("/public")

    assert "set-cookie" in refreshed.headers
    assert refreshed.headers["cache-control"] == "no-store"


def test_only_a_private_answer_may_carry_a_session() -> None:
    assert masks.web.core.unshared("") == "no-store"
    assert masks.web.core.unshared("public, max-age=600") == "no-store"
    assert masks.web.core.unshared("s-maxage=60") == "no-store"
    assert masks.web.core.unshared("private, max-age=60") == "private, max-age=60"
    assert masks.web.core.unshared("No-Store") == "No-Store"


def test_a_refused_refresh_forgets_the_sign_in(app: TestClient, fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    sign_in(app, fake)
    fake.clients["web"].refresh.clear()
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)

    assert app.get("/me", headers=JSON).status_code == 401
    assert app.get("/auth/session").json()["error"] == "login_required"


def test_the_avatar_is_proxied_for_the_signed_in_person(app: TestClient, fake: Fake) -> None:
    assert app.get("/auth/avatar").status_code == 404

    sign_in(app, fake)
    photo = app.get("/auth/avatar", params={"size": "100"})

    assert photo.status_code == 200
    assert photo.content == fake.photo
    assert photo.headers["content-type"] == "image/png"
    assert photo.headers["x-content-type-options"] == "nosniff"
    assert fake.seen[-1].url.params["size"] == "128"

    fake.photo_type = "text/html"

    assert app.get("/auth/avatar").status_code == 404


def test_a_token_is_checked_against_the_resource(app: TestClient, fake: Fake) -> None:
    missing = app.get("/api/catalog")

    assert missing.status_code == 401
    assert (
        'resource_metadata="https://app.example/.well-known/oauth-protected-resource"'
        in missing.headers["www-authenticate"]
    )

    good = fake.access_token("caller", "catalog:read", "", subject="ada", audience=APP)

    assert app.get("/api/catalog", headers={"Authorization": f"Bearer {good}"}).json() == {
        "subject": "ada",
        "by_token": True,
    }

    narrow = fake.access_token("caller", "profile", "", audience=APP)
    refused = app.get("/api/catalog", headers={"Authorization": f"Bearer {narrow}"})

    assert refused.status_code == 403
    assert refused.json()["error"] == "insufficient_scope"
    assert 'scope="catalog:read"' in refused.headers["www-authenticate"]

    elsewhere = fake.access_token("caller", "catalog:read", "", audience=AUDIENCE)

    assert app.get("/api/catalog", headers={"Authorization": f"Bearer {elsewhere}"}).status_code == 401


def test_a_held_token_needs_its_proof_once(app: TestClient, fake: Fake) -> None:
    dpop = masks.Key.generate()
    token = fake.access_token("caller", "catalog:read", dpop.thumbprint, audience=APP)
    headers = {
        "Authorization": f"DPoP {token}",
        "DPoP": masks.proof(dpop, "GET", f"{APP}/api/catalog", token),
    }

    assert app.get("/api/catalog", headers=headers).status_code == 200

    replayed = app.get("/api/catalog", headers=headers)

    assert replayed.status_code == 401
    assert "already been used" in replayed.json()["error_description"]


def test_an_unreachable_issuer_answers_503(app: TestClient, fake: Fake) -> None:
    fake.keys_down = True
    token = fake.access_token("caller", "catalog:read", "", audience=APP)
    answered = app.get("/api/catalog", headers={"Authorization": f"Bearer {token}"})

    assert answered.status_code == 503
    assert "www-authenticate" not in answered.headers


def test_a_route_accepts_a_token_or_a_session(app: TestClient, fake: Fake) -> None:
    token = fake.access_token("caller", "catalog:read", "", subject="bob", audience=APP)

    assert app.get("/either", headers={"Authorization": f"Bearer {token}"}).json()["by_token"] is True

    sign_in(app, fake, privilege="read")

    assert app.get("/either").json() == {"subject": "ada", "by_token": False}


def test_the_resource_metadata(app: TestClient) -> None:
    found = app.get("/.well-known/oauth-protected-resource").json()

    assert found["resource"] == APP
    assert found["authorization_servers"] == [ISSUER]


def test_the_app_gets_a_client_for_delegations(app: TestClient) -> None:
    assert app.get("/client").json() == {"client_id": "web", "provider": "github"}


def test_a_handshake_connects_the_app(fake: Fake) -> None:
    credentials = MemoryCredentials()
    application, _ = build(fake, credentials=credentials)

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        assert location(client.get("/me", headers=HTML)) == "/auth/handshake"
        assert client.get("/me", headers=JSON).json()["error"] == "handshake_required"

        begun = location(client.get("/auth/handshake", headers=HTML))
        query = parse_qs(urlsplit(begun).query)

        assert query["redirect_uris"] == [f"{APP}/auth/callback"]
        assert query["return_to"] == [f"{APP}/auth/handshake/callback"]
        assert query["backchannel_logout_uri"] == [f"{APP}/auth/logout/backchannel"]
        assert query["post_logout_redirect_uri"] == [f"{APP}/auth/logout/return"]
        assert "catalog:admin" in query["scope"][0]

        assert location(client.get(fake.handshake(begun), headers=HTML)) == "/auth"
        assert credentials.read()["client_id"] == "app"

        landed = sign_in(client, fake)

        assert location(landed) == "/"
        assert client.get("/me").json()["subject"] == "ada"


def test_an_app_masks_no_longer_knows_shakes_hands_again(fake: Fake) -> None:
    client, credentials = connected(fake)
    del fake.registrations["app"]

    assert location(client.get("/auth", headers=HTML)) == "/auth/handshake"
    assert credentials.read() == {}


def test_a_handshake_callback_needs_this_browsers_state(fake: Fake) -> None:
    application, _ = build(fake, credentials=MemoryCredentials())

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        begun = location(client.get("/auth/handshake", headers=HTML))
        stolen = fake.handshake(begun)

    with TestClient(application, base_url=APP, follow_redirects=False) as other:
        assert other.get(stolen, headers=JSON).json()["error"] == "invalid_state"


def connected(fake: Fake) -> tuple[TestClient, MemoryCredentials]:
    credentials = MemoryCredentials()
    application, _ = build(fake, credentials=credentials)
    client = TestClient(application, base_url=APP, follow_redirects=False)
    begun = location(client.get("/auth/handshake", headers=HTML))
    client.get(fake.handshake(begun), headers=HTML)

    return client, credentials


def test_only_a_manager_sees_or_changes_the_connection(fake: Fake) -> None:
    client, credentials = connected(fake)

    assert location(client.get("/auth/handshake", headers=HTML)) == "/"

    sign_in(client, fake, subject="bob")

    assert client.get("/auth/handshake", headers=JSON).status_code == 403
    assert client.post("/auth/handshake/disconnect", headers=JSON).status_code == 403

    sign_in(client, fake)
    shown = client.get("/auth/handshake", headers=JSON).json()

    assert shown == {"connected": True, "issuer": ISSUER, "client_id": "app", "can_disconnect": True}

    page = client.get("/auth/handshake", headers=HTML)
    policy = page.headers["content-security-policy"]

    assert f"form-action 'self' {ISSUER};" in policy
    assert "frame-ancestors 'none'" in policy

    gone = client.post("/auth/handshake/disconnect", headers=JSON)

    assert gone.json() == {"connected": False, "handshake_url": "/auth/handshake"}
    assert credentials.read() == {}
    assert "app" not in fake.registrations


class AsyncMemorySessionStore:
    def __init__(self) -> None:
        self.held = MemorySessionStore()
        self.calls: list[str] = []

    async def read(self, key: str) -> dict[str, Any] | None:
        self.calls.append("read")
        return self.held.read(key)

    async def write(self, key: str, data: dict[str, Any], expires_in: int, tags: Mapping[str, str]) -> None:
        self.calls.append("write")
        self.held.write(key, data, expires_in, tags)

    async def delete(self, key: str) -> None:
        self.calls.append("delete")
        self.held.delete(key)

    async def end(self, *, issuer: str, subject: str = "", sid: str = "") -> int:
        self.calls.append("end")
        return self.held.end(issuer=issuer, subject=subject, sid=sid)


@pytest.mark.parametrize("asynchronous", [False, True], ids=["sync store", "async store"])
def test_back_channel_logout_ends_sessions_on_the_server(fake: Fake, asynchronous: bool) -> None:
    held = AsyncMemorySessionStore() if asynchronous else None
    store = held.held if held is not None else MemorySessionStore()
    application, _ = build(fake, credentials=MemoryCredentials(), sessions=ServerSessions(held or store))

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        begun = location(client.get("/auth/handshake", headers=HTML))

        assert parse_qs(urlsplit(begun).query)["backchannel_logout_uri"] == [f"{APP}/auth/logout/backchannel"]

        client.get(fake.handshake(begun), headers=HTML)
        before = client.cookies["__Host-masks"]
        sign_in(client, fake)
        after = client.cookies["__Host-masks"]

        assert before != after
        assert store.read(masks.web.sessions.hashed(before)) is None
        assert client.get("/whoami").json() == {"signed_in": True}

        refused = client.post("/auth/logout/backchannel", data={"logout_token": "nonsense"})

        assert refused.status_code == 400

        ended = client.post("/auth/logout/backchannel", data={"logout_token": fake.logout_token("app", subject="ada")})

        assert ended.status_code == 200
        assert client.get("/whoami").json() == {"signed_in": False}

    if held is not None:
        assert {"read", "write", "delete", "end"} <= set(held.calls)


def test_a_sign_in_from_another_issuer_is_forgotten(fake: Fake) -> None:
    application, auth = build(fake)

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        sign_in(client, fake)

        assert client.get("/whoami").json() == {"signed_in": True}

        auth.config.issuer = "https://elsewhere.example"
        assert client.get("/whoami").json() == {"signed_in": False}

        auth.config.issuer = ISSUER

        assert client.get("/whoami").json() == {"signed_in": False}


def test_a_logout_reaches_only_sessions_from_its_issuer() -> None:
    store = MemorySessionStore()
    store.write("a", {"data": {}}, 60, {"iss": ISSUER, "sub": "ada", "sid": "s-1"})
    store.write("b", {"data": {}}, 60, {"iss": "https://elsewhere.example", "sub": "ada", "sid": "s-1"})

    assert store.end(issuer=ISSUER, subject="ada") == 1
    assert store.read("a") is None
    assert store.read("b") is not None

    engine = masks.web.core.Masks(Config(issuer=ISSUER, secret=SECRET))
    engine.run(engine._depart(ISSUER, "ada", ""))

    assert engine.run(engine._departed(ISSUER, "ada", "s-1", time.time() - 5))
    assert not engine.run(engine._departed("https://elsewhere.example", "ada", "s-1", time.time() - 5))
    assert not engine.run(engine._departed(ISSUER, "ada", "s-1", time.time() + 5))


def test_an_async_session_store_needs_an_async_framework() -> None:
    sessions = ServerSessions(AsyncMemorySessionStore())

    with pytest.raises(TypeError, match="async framework"):
        sessions.load("anything")


def test_back_channel_logout_ends_cookie_sessions_too(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)
    answered = app.post("/auth/logout/backchannel", data={"logout_token": fake.logout_token("web", subject="ada")})

    assert answered.status_code == 200
    assert app.get("/whoami").json() == {"signed_in": False}

    sign_in(app, fake)

    assert app.get("/whoami").json() == {"signed_in": True}


def test_requests_with_one_expired_session_share_one_refresh(
    app: TestClient, fake: Fake, monkeypatch: pytest.MonkeyPatch
) -> None:
    sign_in(app, fake)
    stale = app.cookies["__Host-masks"]
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)

    assert app.get("/whoami").json() == {"signed_in": True}

    app.cookies.set("__Host-masks", stale, domain="app.example")

    assert app.get("/whoami").json() == {"signed_in": True}
    assert len(fake.grants) == 1


def test_a_logout_token_is_used_once(app: TestClient, fake: Fake) -> None:
    held = fake.logout_token("web", subject="ada")

    assert app.post("/auth/logout/backchannel", data={"logout_token": held}).status_code == 200

    reused = app.post("/auth/logout/backchannel", data={"logout_token": held})

    assert reused.status_code == 400
    assert "already used" in reused.json()["error_description"]


class ReadOnly:
    writable = False

    def read(self) -> dict[str, str]:
        return {}

    def write(self, registration: Any) -> None:
        raise TypeError("read only")

    def clear(self) -> None:
        raise TypeError("read only")


def test_a_read_only_store_refuses_the_handshake_before_registering(fake: Fake) -> None:
    application, _ = build(fake, credentials=ReadOnly())

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        begun = location(client.get("/auth/handshake", headers=HTML))
        refused = client.get(fake.handshake(begun), headers=JSON)

    assert refused.status_code == 403
    assert "app" in fake.initial.values()


def test_an_outage_during_the_handshake_is_unavailable(fake: Fake) -> None:
    application, _ = build(fake, credentials=MemoryCredentials())

    with TestClient(application, base_url=APP, follow_redirects=False) as client:
        begun = location(client.get("/auth/handshake", headers=HTML))
        fake.unavailable_tokens = True

        assert client.get(fake.handshake(begun), headers=HTML).status_code == 503


def test_a_large_back_channel_request_is_refused(app: TestClient) -> None:
    answered = app.post(
        "/auth/logout/backchannel",
        content=b"logout_token=" + b"a" * (70 * 1024),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    assert answered.status_code == 413
    assert answered.json()["error"] == "invalid_request"


def test_back_channel_logout_calls_the_app(fake: Fake) -> None:
    heard: list[masks.Logout] = []
    application, _ = build(fake, logged_out=heard.append)

    with TestClient(application, base_url=APP) as client:
        answered = client.post("/auth/logout/backchannel", data={"logout_token": fake.logout_token("web", sid="s-1")})

    assert answered.status_code == 200
    assert heard[0].sid == "s-1"


def test_settings_follow_the_request(fake: Fake) -> None:
    fake.add("other", FakeClient(method="client_secret_basic", secret="other"))
    stores = {"a.example": MemoryCredentials("web", "secret"), "b.example": MemoryCredentials("other", "other")}
    application, _ = build(
        fake,
        credentials=lambda request: stores[request.url.hostname],
        resource=lambda request: f"https://{request.url.hostname}",
    )

    for host, client_id in (("a.example", "web"), ("b.example", "other")):
        with TestClient(application, base_url=f"https://{host}", follow_redirects=False) as client:
            begun = location(client.get("/auth", headers=HTML))
            query = parse_qs(urlsplit(begun).query)

            assert query["client_id"] == [client_id]
            assert query["redirect_uri"] == [f"https://{host}/auth/callback"]


def test_an_unknown_privilege_is_a_mistake_in_the_app(fake: Fake) -> None:
    _, auth = build(fake)

    with pytest.raises(ValueError):
        auth.require("nonsense")


def test_cookie_sessions_need_a_long_secret() -> None:
    with pytest.raises(ValueError):
        Config(issuer=ISSUER, secret="short")


def test_a_connection_needs_a_delegation_redirect_uri(app: TestClient, fake: Fake) -> None:
    sign_in(app, fake)

    with pytest.raises(ValueError, match="delegation_redirect_uri"):
        app.get("/connect", params={"provider": "github"})


def test_a_delegation_path_is_registered_as_a_full_address(fake: Fake) -> None:
    _, auth = build(fake, delegation_redirect_uri="/connected")
    request = masks.web.core.Incoming("GET", f"{APP}/auth/handshake", httpx.Headers())
    shaken = auth.engine.handshake(request, auth.engine.run(auth.engine.discover(request)))

    assert f"{APP}/connected" in shaken.redirect_uris
    assert "masks:delegate:" in shaken.scope
