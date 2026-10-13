from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import Any, cast
from urllib.parse import urlsplit

import django
import httpx
import pytest
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.test import Client

from masks.django import engine
from masks.web import Config, ServerSessions

from . import scenarios
from .fake import ISSUER, Fake
from .scenarios import Answered

if not settings.configured:
    settings.configure(
        SECRET_KEY="d" * 50,
        ALLOWED_HOSTS=["app.example"],
        ROOT_URLCONF="tests.django_app",
        MIDDLEWARE=[
            "django.middleware.common.CommonMiddleware",
            "django.middleware.csrf.CsrfViewMiddleware",
            "masks.django.middleware.MasksMiddleware",
        ],
        INSTALLED_APPS=[],
        MASKS={"issuer": ISSUER},
        USE_TZ=True,
    )
    django.setup()


class DjangoBrowser:
    def __init__(self, config: Config) -> None:
        settings.MASKS = config
        self.client = Client(HTTP_HOST="app.example")

    def _target(self, target: str) -> str:
        held = urlsplit(target)

        return held.path + (f"?{held.query}" if held.query else "")

    def _answered(self, sent: Any) -> Answered:
        pairs = list(sent.headers.items())
        pairs += [("set-cookie", morsel.OutputString()) for morsel in sent.cookies.values()]

        return Answered(sent.status_code, httpx.Headers(pairs), sent.content)

    def get(self, target: str, headers: dict[str, str] | None = None) -> Answered:
        return self._answered(self.client.get(self._target(target), headers=headers or {}, secure=True))

    def post(self, target: str, headers: dict[str, str] | None = None, data: dict[str, str] | None = None) -> Answered:
        return self._answered(self.client.post(self._target(target), data or {}, headers=headers or {}, secure=True))


@pytest.fixture(autouse=True)
def restored() -> Iterator[None]:
    held = settings.MASKS
    yield
    settings.MASKS = held


@pytest.mark.parametrize("scenario", scenarios.SCENARIOS, ids=lambda scenario: scenario.__name__)
def test_django(scenario: Callable[..., None], fake: Fake) -> None:
    scenario(DjangoBrowser, fake)


@pytest.mark.parametrize("scenario", scenarios.TIMED, ids=lambda scenario: scenario.__name__)
def test_django_over_time(scenario: Callable[..., None], fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    scenario(DjangoBrowser, fake, monkeypatch)


def test_masks_forms_check_their_own_origin_under_djangos_csrf_check(fake: Fake) -> None:
    browser = DjangoBrowser(scenarios.config(fake))
    browser.client = Client(HTTP_HOST="app.example", enforce_csrf_checks=True)
    scenarios.sign_in(browser, fake)
    elsewhere = {"Origin": "https://elsewhere.example", **scenarios.JSON}
    here = {"Origin": scenarios.APP, **scenarios.HTML}

    assert browser.post("/auth/logout", elsewhere).status == 403
    assert browser.get("/me").status == 200
    assert "/handshake" in browser.post("/auth/handshake", here).location
    assert browser.post("/auth/logout", here).status == 303
    assert browser.get("/me", scenarios.JSON).status == 401


def test_django_refuses_an_async_session_store(fake: Fake) -> None:
    class AsyncStore:
        async def read(self, key: str) -> None:
            return None

    settings.MASKS = scenarios.config(fake, sessions=ServerSessions(cast(Any, AsyncStore())))

    with pytest.raises(ImproperlyConfigured, match="async framework"):
        engine()
