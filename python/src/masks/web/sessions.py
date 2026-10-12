from __future__ import annotations

import base64
import binascii
import hashlib
import json
import secrets
import threading
import time
import zlib
from collections.abc import Iterator, Mapping, MutableMapping, Sequence
from typing import Any, Protocol

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

COOKIE = "masks_session"
LIFETIME = 14 * 24 * 3600
COOKIE_LIMIT = 4000
SECRET_LENGTH = 32
VERSION = "1"


class Session(MutableMapping[str, Any]):
    def __init__(self, data: Mapping[str, Any] | None = None, *, key: str = "", issued_at: float | None = None) -> None:
        self.data: dict[str, Any] = dict(data or {})
        self.key = key
        self.issued_at = issued_at if issued_at is not None else time.time()
        self.modified = False
        self.renewed = False
        self.ended_key = ""

    def __getitem__(self, name: str) -> Any:
        return self.data[name]

    def __setitem__(self, name: str, value: Any) -> None:
        self.data[name] = value
        self.modified = True

    def __delitem__(self, name: str) -> None:
        del self.data[name]
        self.modified = True

    def __iter__(self) -> Iterator[str]:
        return iter(self.data)

    def __len__(self) -> int:
        return len(self.data)

    def renew(self, keep: Sequence[str] = ()) -> None:
        self.data = {name: value for name, value in self.data.items() if name in keep}
        self.ended_key = self.ended_key or self.key
        self.key = ""
        self.issued_at = time.time()
        self.modified = True
        self.renewed = True

    @property
    def dirty(self) -> bool:
        return self.modified or self.renewed


class SessionStore(Protocol):
    def read(self, key: str) -> dict[str, Any] | None: ...

    def write(self, key: str, data: dict[str, Any], expires_in: int, tags: Mapping[str, str]) -> None: ...

    def delete(self, key: str) -> None: ...

    def end(self, *, subject: str = "", sid: str = "") -> int: ...


class SessionBackend(Protocol):
    name: str
    lifetime: int

    def load(self, cookie: str | None) -> Session: ...

    def save(self, session: Session, tags: Mapping[str, str]) -> str | None: ...

    def end(self, *, subject: str = "", sid: str = "") -> int | None: ...


def derived(secret: str | bytes, purpose: bytes) -> bytes:
    held = secret.encode() if isinstance(secret, str) else secret

    if len(held) < SECRET_LENGTH:
        raise ValueError(f"masks: a session secret is at least {SECRET_LENGTH} bytes long")

    return HKDF(algorithm=hashes.SHA256(), length=32, salt=b"masks", info=purpose).derive(held)


def b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


class CookieSessions:
    def __init__(
        self, secret: str | bytes | Sequence[str | bytes], *, name: str = COOKIE, lifetime: int = LIFETIME
    ) -> None:
        held = [secret] if isinstance(secret, (str, bytes)) else list(secret)

        if not held:
            raise ValueError("masks: cookie sessions need a secret")

        self.name = name
        self.lifetime = lifetime
        self._keys = [AESGCM(derived(one, b"masks session cookie " + VERSION.encode())) for one in held]
        self._bound = f"masks-session:{name}".encode()

    def load(self, cookie: str | None) -> Session:
        found = self._open(cookie or "")

        if found is None:
            return Session()

        issued_at = found.get("iat")
        data = found.get("data")

        if not isinstance(issued_at, (int, float)) or not isinstance(data, dict):
            return Session()

        if issued_at + self.lifetime < time.time() or issued_at > time.time() + 60:
            return Session()

        return Session(data, key="cookie", issued_at=float(issued_at))

    def _open(self, cookie: str) -> dict[str, Any] | None:
        version, _, sealed = cookie.partition(".")

        if version != VERSION or not sealed:
            return None

        try:
            raw = unb64(sealed)
        except (binascii.Error, ValueError):
            return None

        if len(raw) < 13:
            return None

        for key in self._keys:
            try:
                opened = key.decrypt(raw[:12], raw[12:], self._bound)
            except InvalidTag:
                continue

            try:
                found = json.loads(zlib.decompress(opened, bufsize=COOKIE_LIMIT * 4))
            except (zlib.error, ValueError):
                return None

            return found if isinstance(found, dict) else None

        return None

    def save(self, session: Session, tags: Mapping[str, str]) -> str | None:
        if not session.data:
            return None

        nonce = secrets.token_bytes(12)
        packed = zlib.compress(json.dumps({"iat": session.issued_at, "data": session.data}).encode())
        cookie = f"{VERSION}.{b64(nonce + self._keys[0].encrypt(nonce, packed, self._bound))}"

        if len(cookie) > COOKIE_LIMIT:
            raise ValueError("masks: this session no longer fits in a cookie; keep sessions on the server instead")

        return cookie

    def end(self, *, subject: str = "", sid: str = "") -> int | None:
        return None


def hashed(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class ServerSessions:
    def __init__(self, store: SessionStore, *, name: str = COOKIE, lifetime: int = LIFETIME) -> None:
        self.store = store
        self.name = name
        self.lifetime = lifetime

    def load(self, cookie: str | None) -> Session:
        if not cookie or len(cookie) > 128:
            return Session()

        found = self.store.read(hashed(cookie))

        if not isinstance(found, dict) or not isinstance(found.get("data"), dict):
            return Session()

        issued_at = found.get("iat")

        if not isinstance(issued_at, (int, float)) or issued_at + self.lifetime < time.time():
            self.store.delete(hashed(cookie))
            return Session()

        return Session(found["data"], key=cookie, issued_at=float(issued_at))

    def save(self, session: Session, tags: Mapping[str, str]) -> str | None:
        if session.ended_key:
            self.store.delete(hashed(session.ended_key))
            session.ended_key = ""

        if not session.data:
            if session.key:
                self.store.delete(hashed(session.key))

            return None

        session.key = session.key or secrets.token_urlsafe(32)
        remaining = int(session.issued_at + self.lifetime - time.time())
        self.store.write(hashed(session.key), {"iat": session.issued_at, "data": session.data}, max(remaining, 1), tags)

        return session.key

    def end(self, *, subject: str = "", sid: str = "") -> int | None:
        return self.store.end(subject=subject, sid=sid)


class MemorySessionStore:
    def __init__(self) -> None:
        self._held: dict[str, tuple[float, dict[str, Any], dict[str, str]]] = {}
        self._lock = threading.Lock()

    def read(self, key: str) -> dict[str, Any] | None:
        with self._lock:
            found = self._held.get(key)

            if found is None or found[0] < time.time():
                self._held.pop(key, None)
                return None

            return dict(json.loads(json.dumps(found[1])))

    def write(self, key: str, data: dict[str, Any], expires_in: int, tags: Mapping[str, str]) -> None:
        with self._lock:
            self._held[key] = (time.time() + expires_in, json.loads(json.dumps(data)), dict(tags))

    def delete(self, key: str) -> None:
        with self._lock:
            self._held.pop(key, None)

    def end(self, *, subject: str = "", sid: str = "") -> int:
        with self._lock:
            ended = [
                key
                for key, (_, _, tags) in self._held.items()
                if (sid and tags.get("sid") == sid) or (subject and not sid and tags.get("sub") == subject)
            ]

            for key in ended:
                del self._held[key]

            return len(ended)
