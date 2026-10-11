from __future__ import annotations

import threading
from collections.abc import Awaitable, Callable
from typing import Protocol, runtime_checkable

import anyio

from .models import Token


@runtime_checkable
class TokenSource(Protocol):
    def token(self) -> Token: ...


@runtime_checkable
class AsyncTokenSource(Protocol):
    async def token(self) -> Token: ...


class CachedTokenSource:
    def __init__(self, fetch: Callable[[], Token], held: Token | None = None) -> None:
        self._fetch = fetch
        self._held = held
        self._lock = threading.Lock()

    def token(self) -> Token:
        with self._lock:
            if self._held is not None and self._held.valid():
                return self._held

            self._held = self._fetch()

            return self._held


class AsyncCachedTokenSource:
    def __init__(self, fetch: Callable[[], Awaitable[Token]], held: Token | None = None) -> None:
        self._fetch = fetch
        self._held = held
        self._lock: anyio.Lock | None = None

    async def token(self) -> Token:
        if self._lock is None:
            self._lock = anyio.Lock()

        async with self._lock:
            if self._held is not None and self._held.valid():
                return self._held

            self._held = await self._fetch()

            return self._held
