from __future__ import annotations

import json
import os
import tempfile
import threading
import time
from pathlib import Path
from typing import Protocol

from ..models import Registration

KEYS = ("issuer", "client_id", "client_secret", "registration_access_token", "registration_client_uri")


class Credentials(Protocol):
    @property
    def writable(self) -> bool: ...

    def read(self) -> dict[str, str]: ...

    def write(self, issuer: str, registration: Registration) -> None: ...

    def clear(self) -> None: ...


def held(issuer: str, registration: Registration) -> dict[str, str]:
    found = {
        "issuer": issuer,
        "client_id": registration.client_id,
        "client_secret": registration.client_secret or "",
        "registration_access_token": registration.registration_access_token or "",
        "registration_client_uri": registration.registration_client_uri or "",
        "connected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    return {key: value for key, value in found.items() if value}


def given(issuer: str, client_id: str, client_secret: str) -> dict[str, str]:
    pairs = (("issuer", issuer.rstrip("/")), ("client_id", client_id), ("client_secret", client_secret))

    return {key: value for key, value in pairs if value}


class FileCredentials:
    def __init__(self, path: str | os.PathLike[str] = "masks.json") -> None:
        self.path = Path(path)
        self._lock = threading.Lock()
        self._held: dict[str, str] | None = None
        self._version: tuple[int, int, int] | None = None

    @property
    def writable(self) -> bool:
        try:
            self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            descriptor, probe = tempfile.mkstemp(dir=self.path.parent, prefix=".masks-")
            os.close(descriptor)
            os.unlink(probe)
        except OSError:
            return False

        return True

    def read(self) -> dict[str, str]:
        with self._lock:
            try:
                found = self.path.stat()
            except FileNotFoundError:
                self._held = None
                return {}

            version = (found.st_ino, found.st_size, found.st_mtime_ns)

            if self._held is None or version != self._version:
                try:
                    parsed = json.loads(self.path.read_bytes())
                except ValueError:
                    parsed = {}

                self._held = {key: str(value) for key, value in parsed.items()} if isinstance(parsed, dict) else {}
                self._version = version

            return dict(self._held)

    def write(self, issuer: str, registration: Registration) -> None:
        content = json.dumps(held(issuer, registration), indent=2)

        with self._lock:
            self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            descriptor, temporary = tempfile.mkstemp(dir=self.path.parent, prefix=".masks-")

            try:
                os.fchmod(descriptor, 0o600)

                with os.fdopen(descriptor, "w") as file:
                    file.write(content)
                    file.flush()
                    os.fsync(file.fileno())

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

    def __init__(self, client_id: str = "", client_secret: str = "", issuer: str = "") -> None:
        self._held = given(issuer, client_id, client_secret)

    def read(self) -> dict[str, str]:
        return dict(self._held)

    def write(self, issuer: str, registration: Registration) -> None:
        self._held = held(issuer, registration)

    def clear(self) -> None:
        self._held = {}


class StaticCredentials:
    writable = False

    def __init__(self, client_id: str, client_secret: str = "", issuer: str = "") -> None:
        if not client_id:
            raise ValueError("masks: static credentials need a client_id")

        self._held = given(issuer, client_id, client_secret)

    def read(self) -> dict[str, str]:
        return dict(self._held)

    def write(self, issuer: str, registration: Registration) -> None:
        raise TypeError("masks: these credentials come from configuration and cannot be replaced")

    def clear(self) -> None:
        raise TypeError("masks: these credentials come from configuration and cannot be removed")
