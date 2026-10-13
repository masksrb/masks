from __future__ import annotations

import dataclasses
import time
from typing import Any

import anyio
import fakeredis
import pytest
from fastapi.testclient import TestClient
from flask import Flask

import masks
from masks.flask import Masks
from masks.web import AsyncRedisStore, MemoryStore, RedisStore
from masks.web.core import LOGOUT_LEEWAY, LOGOUT_MEMORY, logout_memory
from masks.web.stores import asynchronous

from . import scenarios
from .fake import Fake
from .scenarios import APP, HTML
from .test_fastapi import application
from .test_flask import FlaskBrowser


def contract(store: Any) -> None:
    assert store.add("k", "first", 60)
    assert not store.add("k", "second", 60)
    assert store.get("k") == "first"

    store.set("k", "third", 60)

    assert store.get("k") == "third"

    store.delete("k")

    assert store.get("k") is None
    assert store.add("k", "again", 60)


def test_the_memory_store(monkeypatch: pytest.MonkeyPatch) -> None:
    store = MemoryStore()
    contract(store)
    store.set("short", "gone", 5)
    now = time.monotonic()
    monkeypatch.setattr("masks.web.stores.time.monotonic", lambda: now + 6)

    assert store.get("short") is None
    assert store.add("short", "back", 5)


def test_the_redis_store() -> None:
    contract(RedisStore(fakeredis.FakeRedis()))


def test_the_async_redis_store() -> None:
    store = AsyncRedisStore(fakeredis.FakeAsyncRedis())

    async def run() -> None:
        assert await store.add("k", "first", 60)
        assert not await store.add("k", "second", 60)
        assert await store.get("k") == "first"

        await store.set("k", "third", 60)

        assert await store.get("k") == "third"

        await store.delete("k")

        assert await store.get("k") is None

    anyio.run(run)
    assert asynchronous(store)
    assert not asynchronous(RedisStore(fakeredis.FakeRedis()))


def test_a_logout_on_one_worker_ends_the_session_on_another(fake: Fake) -> None:
    held = dataclasses.replace(
        scenarios.config(fake), async_http=fake.async_http(), store=AsyncRedisStore(fakeredis.FakeAsyncRedis())
    )
    first, _ = application(held)
    second, _ = application(held)

    with (
        TestClient(first, base_url=APP, follow_redirects=False) as one,
        TestClient(second, base_url=APP, follow_redirects=False) as other,
    ):
        begun = one.get("/auth", headers=HTML)
        one.get(fake.authorize(begun.headers["location"]), headers=HTML)
        other.cookies.set("__Host-masks", one.cookies["__Host-masks"], domain="app.example")

        assert other.get("/whoami").json() == {"signed_in": True}

        logout = fake.logout_token("web", subject="ada")

        assert one.post("/auth/logout/backchannel", data={"logout_token": logout}).status_code == 200
        assert other.get("/whoami").json() == {"signed_in": False}
        assert other.post("/auth/logout/backchannel", data={"logout_token": logout}).status_code == 400


def test_flask_refuses_an_async_store(fake: Fake) -> None:
    app = Flask(__name__)
    app.secret_key = "k" * 40

    with pytest.raises(TypeError, match="async framework"):
        Masks(app, issuer="https://id.example", http=fake.http(), store=AsyncRedisStore(fakeredis.FakeAsyncRedis()))


class FailingStore(MemoryStore):
    def __init__(self) -> None:
        super().__init__()
        self.failing: set[str] = set()

    def add(self, key: str, value: str, expires_in: int) -> bool:
        if "add" in self.failing:
            raise ConnectionError("the store is down")

        return super().add(key, value, expires_in)

    def set(self, key: str, value: str, expires_in: int) -> None:
        if "set" in self.failing:
            raise ConnectionError("the store is down")

        super().set(key, value, expires_in)

    def claims(self) -> list[str]:
        return [key for key, (value, _) in self._held.items() if value == "1"]


def stale(fake: Fake, monkeypatch: pytest.MonkeyPatch, store: FailingStore) -> FlaskBrowser:
    browser = FlaskBrowser(dataclasses.replace(scenarios.config(fake), store=store))
    scenarios.sign_in(browser, fake)
    later = time.time() + 7200
    monkeypatch.setattr(masks.models.time, "time", lambda: later)

    return browser


def test_a_logout_token_is_taken_again_when_its_departure_was_not_recorded(fake: Fake) -> None:
    store = FailingStore()
    browser = FlaskBrowser(dataclasses.replace(scenarios.config(fake), store=store))
    held = fake.logout_token("web", subject="ada")
    store.failing.add("set")

    assert browser.post("/auth/logout/backchannel", data={"logout_token": held}).status == 500

    store.failing.clear()

    assert browser.post("/auth/logout/backchannel", data={"logout_token": held}).status == 200
    assert browser.post("/auth/logout/backchannel", data={"logout_token": held}).status == 400


def test_a_logout_token_is_remembered_until_it_expires() -> None:
    now = int(time.time())

    def remembered(expires_in: int) -> int:
        return logout_memory(masks.Logout("ada", "", "j", now, {"exp": now + expires_in}))

    assert remembered(120) == LOGOUT_MEMORY
    assert remembered(3600) >= 3600 + LOGOUT_LEEWAY - 1


def test_a_store_outage_during_a_refresh_keeps_the_session(fake: Fake, monkeypatch: pytest.MonkeyPatch) -> None:
    store = FailingStore()
    browser = stale(fake, monkeypatch, store)
    store.failing.add("add")

    assert browser.get("/public").json() == {"signed_in": False}

    store.failing.clear()

    assert browser.get("/public").json() == {"signed_in": True}


def test_a_refresh_lets_go_of_its_claim_when_the_result_cannot_be_shared(
    fake: Fake, monkeypatch: pytest.MonkeyPatch
) -> None:
    store = FailingStore()
    browser = stale(fake, monkeypatch, store)
    store.failing.add("set")

    assert browser.get("/public").json() == {"signed_in": True}
    assert store.claims() == []
