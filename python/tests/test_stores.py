from __future__ import annotations

import dataclasses
import time
from typing import Any

import anyio
import fakeredis
import pytest
from fastapi.testclient import TestClient
from flask import Flask

from masks.flask import Masks
from masks.web import AsyncRedisStore, MemoryStore, RedisStore
from masks.web.stores import asynchronous

from . import scenarios
from .fake import Fake
from .scenarios import APP, HTML
from .test_fastapi import application


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
