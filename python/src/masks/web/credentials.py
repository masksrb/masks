from __future__ import annotations

import json
import os
import tempfile
import threading
import time
from pathlib import Path
from typing import Protocol

from ..models import Registration

KEYS = ("client_id", "client_secret", "registration_access_token", "registration_client_uri")


class Credentials(Protocol):
    writable: bool

    def read(self) -> dict[str, str]: ...

    def write(self, registration: Registration) -> None: ...

    def clear(self) -> None: ...


def held(registration: Registration) -> dict[str, str]:
    found = {
        "client_id": registration.client_id,
        "client_secret": registration.client_secret or "",
        "registration_access_token": registration.registration_access_token or "",
        "registration_client_uri": registration.registration_client_uri or "",
        "connected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    return {key: value for key, value in found.items() if value}


class FileCredentials:
    writable = True

    def __init__(self, path: str | os.PathLike[str] = "masks.json") -> None:
        self.path = Path(path)
        self._lock = threading.Lock()
        self._held: dict[str, str] | None = None
        self._read_at = 0.0

    def read(self) -> dict[str, str]:
        with self._lock:
            try:
                changed = self.path.stat().st_mtime
            except FileNotFoundError:
                self._held = None
                return {}

            if self._held is None or changed != self._read_at:
                try:
                    found = json.loads(self.path.read_text())
                except (OSError, ValueError):
                    found = {}

                self._held = {key: str(value) for key, value in found.items()} if isinstance(found, dict) else {}
                self._read_at = changed

            return dict(self._held)

    def write(self, registration: Registration) -> None:
        content = json.dumps(held(registration), indent=2)

        with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary = tempfile.mkstemp(dir=self.path.parent, prefix=".masks-")

            try:
                os.fchmod(descriptor, 0o600)

                with os.fdopen(descriptor, "w") as file:
                    file.write(content)

                os.replace(temporary, self.path)
            except BaseException:
                Path(temporary).unlink(missing_ok=True)
                raise

            self._held = None

    def clear(self) -> None:
        with self._lock:
            self.path.unlink(missing_ok=True)
            self._held = None


class MemoryCredentials:
    writable = True

    def __init__(self, client_id: str = "", client_secret: str = "") -> None:
        self._held = {
            key: value for key, value in (("client_id", client_id), ("client_secret", client_secret)) if value
        }

    def read(self) -> dict[str, str]:
        return dict(self._held)

    def write(self, registration: Registration) -> None:
        self._held = held(registration)

    def clear(self) -> None:
        self._held = {}


class StaticCredentials:
    writable = False

    def __init__(self, client_id: str, client_secret: str = "") -> None:
        if not client_id:
            raise ValueError("masks: static credentials need a client_id")

        self._held = {
            key: value for key, value in (("client_id", client_id), ("client_secret", client_secret)) if value
        }

    def read(self) -> dict[str, str]:
        return dict(self._held)

    def write(self, registration: Registration) -> None:
        raise TypeError("masks: these credentials come from configuration and cannot be replaced")

    def clear(self) -> None:
        raise TypeError("masks: these credentials come from configuration and cannot be removed")
