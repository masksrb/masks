from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import Any
from urllib.parse import urlsplit

import django
import httpx
import pytest
from django.conf import settings
from django.test import Client

from masks.web import Config

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


def test_django_refreshes_and_forgets(fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    scenarios.refreshes_and_forgets(DjangoBrowser, fake, monkeypatch)


def test_django_keeps_its_csrf_check_on_sign_out(fake: Fake) -> None:
    browser = DjangoBrowser(scenarios.config(fake))
    browser.client = Client(HTTP_HOST="app.example", enforce_csrf_checks=True)
    scenarios.sign_in(browser, fake)

    assert browser.post("/auth/logout", scenarios.JSON).status == 403
    assert browser.get("/me").status == 200
