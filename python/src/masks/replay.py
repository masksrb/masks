from __future__ import annotations

import threading
import time
from typing import Protocol

SWEEP_EVERY = 1.0


class ReplayStore(Protocol):
    def first(self, key: str, expires_in: int) -> bool: ...


class AsyncReplayStore(Protocol):
    async def first(self, key: str, expires_in: int) -> bool: ...


class MemoryReplayStore:
    def __init__(self) -> None:
        self._held: dict[str, float] = {}
        self._swept = 0.0
        self._lock = threading.Lock()

    def first(self, key: str, expires_in: int) -> bool:
        now = time.monotonic()

        with self._lock:
            if now - self._swept > SWEEP_EVERY:
                self._swept = now
                self._held = {held: until for held, until in self._held.items() if until >= now}

            if self._held.get(key, -1.0) >= now:
                return False

            self._held[key] = now + expires_in

            return True
