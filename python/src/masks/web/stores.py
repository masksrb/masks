from __future__ import annotations

import hashlib
import inspect
import threading
import time
from typing import Any, Protocol

SWEEP_EVERY = 60.0


class Store(Protocol):
    def add(self, key: str, value: str, expires_in: int) -> bool: ...

    def get(self, key: str) -> str | None: ...

    def set(self, key: str, value: str, expires_in: int) -> None: ...

    def delete(self, key: str) -> None: ...


class AsyncStore(Protocol):
    async def add(self, key: str, value: str, expires_in: int) -> bool: ...

    async def get(self, key: str) -> str | None: ...

    async def set(self, key: str, value: str, expires_in: int) -> None: ...

    async def delete(self, key: str) -> None: ...


def asynchronous(store: Store | AsyncStore) -> bool:
    return inspect.iscoroutinefunction(getattr(store, "get", None))


def keyed(*parts: str) -> str:
    return "masks:" + hashlib.sha256("\x00".join(parts).encode()).hexdigest()


class MemoryStore:
    def __init__(self) -> None:
        self._held: dict[str, tuple[str, float]] = {}
        self._swept = time.monotonic()
        self._lock = threading.Lock()

    def _live(self, key: str, now: float) -> str | None:
        if now - self._swept > SWEEP_EVERY:
            self._swept = now
            self._held = {name: held for name, held in self._held.items() if held[1] > now}

        found = self._held.get(key)

        return found[0] if found is not None and found[1] > now else None

    def add(self, key: str, value: str, expires_in: int) -> bool:
        now = time.monotonic()

        with self._lock:
            if self._live(key, now) is not None:
                return False

            self._held[key] = (value, now + expires_in)

            return True

    def get(self, key: str) -> str | None:
        with self._lock:
            return self._live(key, time.monotonic())

    def set(self, key: str, value: str, expires_in: int) -> None:
        now = time.monotonic()

        with self._lock:
            self._live(key, now)
            self._held[key] = (value, now + expires_in)

    def delete(self, key: str) -> None:
        with self._lock:
            self._held.pop(key, None)


def text(value: Any) -> str | None:
    if value is None:
        return None

    return value.decode() if isinstance(value, bytes) else str(value)


class RedisStore:
    def __init__(self, client: Any) -> None:
        self.client = client

    def add(self, key: str, value: str, expires_in: int) -> bool:
        return bool(self.client.set(key, value, nx=True, ex=max(expires_in, 1)))

    def get(self, key: str) -> str | None:
        return text(self.client.get(key))

    def set(self, key: str, value: str, expires_in: int) -> None:
        self.client.set(key, value, ex=max(expires_in, 1))

    def delete(self, key: str) -> None:
        self.client.delete(key)


class AsyncRedisStore:
    def __init__(self, client: Any) -> None:
        self.client = client

    async def add(self, key: str, value: str, expires_in: int) -> bool:
        return bool(await self.client.set(key, value, nx=True, ex=max(expires_in, 1)))

    async def get(self, key: str) -> str | None:
        return text(await self.client.get(key))

    async def set(self, key: str, value: str, expires_in: int) -> None:
        await self.client.set(key, value, ex=max(expires_in, 1))

    async def delete(self, key: str) -> None:
        await self.client.delete(key)


class Replays:
    def __init__(self, store: Store) -> None:
        self.store = store

    def first(self, key: str, expires_in: int) -> bool:
        return self.store.add(keyed("proof", key), "1", expires_in)


class AsyncReplays:
    def __init__(self, store: AsyncStore) -> None:
        self.store = store

    async def first(self, key: str, expires_in: int) -> bool:
        return await self.store.add(keyed("proof", key), "1", expires_in)
