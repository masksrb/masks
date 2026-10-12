from __future__ import annotations

from collections.abc import Callable
from typing import Any
from urllib.parse import urlsplit

import httpx
import pytest
from flask import Flask, jsonify

from masks.flask import Masks, masked
from masks.web import Config

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


def test_flask_refreshes_and_forgets(fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    scenarios.refreshes_and_forgets(FlaskBrowser, fake, monkeypatch)


def test_flask_takes_the_secret_from_the_app(fake: Fake) -> None:
    app = Flask(__name__)
    app.secret_key = "k" * 40
    auth = Masks(app, issuer="https://id.example", http=fake.http())

    assert auth.engine.config.backend.name == "masks_session"
