from __future__ import annotations

import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from typing import Any, cast
from urllib.parse import urlsplit

import httpx
import pytest
from flask import Flask, jsonify, request

import masks
from masks.flask import Masks, masked
from masks.web import Config, ServerSessions

from . import scenarios
from .fake import Fake
from .scenarios import APP, Answered


class FlaskBrowser:
    def __init__(self, config: Config) -> None:
        app = Flask(__name__)
        auth = Masks(app, config)

        @app.get("/me")
        @auth.required()
        def me() -> Any:
            return jsonify(masked.to_dict())

        @app.get("/admin")
        @auth.required("admin")
        def admin() -> Any:
            return jsonify({"privileges": masked.privileges})

        @app.get("/billing")
        @auth.required("billing")
        def billing() -> Any:
            return jsonify({"role": masked.organization.role if masked.organization else None})

        @app.get("/public")
        def public() -> Any:
            return jsonify({"signed_in": masked.signed_in}), 200, {"Cache-Control": "public, max-age=600"}

        @app.get("/plain")
        def plain() -> Any:
            return jsonify({"plain": True})

        @app.get("/note")
        def note() -> Any:
            return jsonify(scenarios.note(auth.session(), request.args.get("size")))

        @app.get("/connect")
        def connect() -> Any:
            return auth.start_delegation(request.args["provider"])

        @app.get("/connected")
        def connected() -> Any:
            try:
                return jsonify(scenarios.connection(auth.finish_delegation()))
            except masks.DelegationRefused as error:
                return jsonify({"error": error.code}), 400

        @app.get("/api/catalog")
        @auth.protected("read")
        def catalog() -> Any:
            return jsonify({"subject": masked.subject})

        self.client = app.test_client()

    def _target(self, target: str) -> str:
        held = urlsplit(target)

        return held.path + (f"?{held.query}" if held.query else "")

    def _answered(self, sent: Any) -> Answered:
        return Answered(sent.status_code, httpx.Headers(list(sent.headers.items())), sent.get_data())

    def get(self, target: str, headers: dict[str, str] | None = None) -> Answered:
        return self._answered(self.client.get(self._target(target), headers=headers or {}, base_url=APP))

    def post(self, target: str, headers: dict[str, str] | None = None, data: dict[str, str] | None = None) -> Answered:
        return self._answered(self.client.post(self._target(target), headers=headers or {}, data=data, base_url=APP))


@pytest.mark.parametrize("scenario", scenarios.SCENARIOS, ids=lambda scenario: scenario.__name__)
def test_flask(scenario: Callable[..., None], fake: Fake) -> None:
    scenario(FlaskBrowser, fake)


@pytest.mark.parametrize("scenario", scenarios.TIMED, ids=lambda scenario: scenario.__name__)
def test_flask_over_time(scenario: Callable[..., None], fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    scenario(FlaskBrowser, fake, monkeypatch)


def test_flask_takes_the_secret_from_the_app(fake: Fake) -> None:
    app = Flask(__name__)
    app.secret_key = "k" * 40
    auth = Masks(app, issuer="https://id.example", http=fake.http())

    assert auth.engine.config.backend.name == "__Host-masks"


def test_a_privilege_named_before_init_app_is_checked_by_it(fake: Fake) -> None:
    auth = Masks(issuer="https://id.example", http=fake.http())
    app = Flask(__name__)
    app.secret_key = "k" * 40

    @app.get("/typo")
    @auth.required("admni")
    def typo() -> Any:
        return "never"

    with pytest.raises(ValueError, match="admni"):
        auth.init_app(app)


def test_an_async_session_store_is_refused_at_init_app(fake: Fake) -> None:
    class AsyncStore:
        async def read(self, key: str) -> None:
            return None

    with pytest.raises(TypeError, match="async framework"):
        Masks(Flask(__name__), scenarios.config(fake, sessions=ServerSessions(cast(Any, AsyncStore()))))


def test_an_app_factory_and_calls_inside_a_view(fake: Fake) -> None:
    auth = Masks()

    def create() -> Flask:
        app = Flask(__name__)
        auth.init_app(app)

        @app.get("/inside")
        def inside() -> Any:
            person = auth.authorize("admin")
            return jsonify({"subject": person.subject})

        @app.get("/client")
        def client() -> Any:
            return jsonify({"client_id": auth.client().client_id, "connected": auth.connected()})

        return app

    auth._config = scenarios.config(fake)
    app = create()
    browser = app.test_client()

    assert browser.get("/inside", base_url=APP).headers["Location"] == "/auth"
    assert browser.get("/client", base_url=APP).json == {"client_id": "web", "connected": True}


def stale_pair(fake: Fake, monkeypatch: pytest.MonkeyPatch) -> tuple[FlaskBrowser, FlaskBrowser, list[str]]:
    held = scenarios.config(fake)
    first = FlaskBrowser(held)
    second = FlaskBrowser(held)
    scenarios.sign_in(first, fake)
    cookie = first.client.get_cookie("__Host-masks", domain="app.example")
    assert cookie is not None
    second.client.set_cookie("__Host-masks", cookie.value, domain="app.example", secure=True)
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)
    refreshed: list[str] = []
    token = fake.token

    def counted(request: httpx.Request) -> httpx.Response:
        if b"grant_type=refresh_token" in request.content:
            refreshed.append("refresh")
            time.sleep(0.2)

        return token(request)

    monkeypatch.setattr(fake, "token", counted)

    return first, second, refreshed


def test_two_workers_sharing_a_store_refresh_once(fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    first, second, refreshed = stale_pair(fake, monkeypatch)

    assert first.get("/public").json() == {"signed_in": True}
    assert second.get("/public").json() == {"signed_in": True}
    assert refreshed == ["refresh"]


def test_two_workers_refreshing_at_once_refresh_once(fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    first, second, refreshed = stale_pair(fake, monkeypatch)

    with ThreadPoolExecutor(2) as pool:
        answers = list(pool.map(lambda browser: browser.get("/public").json(), [first, second]))

    assert answers == [{"signed_in": True}, {"signed_in": True}]
    assert refreshed == ["refresh"]
