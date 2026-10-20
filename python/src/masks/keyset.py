from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import threading
import time
from collections.abc import Sequence
from typing import Any

import httpx
import jwt

from .errors import Error, InvalidToken
from .flows import Flow, get, required
from .keys import encode
from .models import Issuer

SIGNING_ALGORITHMS = ("RS256", "ES256")
KEYS_LIFETIME = 300
KEYS_PATIENCE = 30
LEEWAY = 30
FIRST_BACKOFF = 5.0
LONGEST_BACKOFF = 60.0

SEGMENT = re.compile(r"[A-Za-z0-9_-]+")

HASHES = {"RS256": hashlib.sha256, "ES256": hashlib.sha256}


def typed(header: dict[str, Any], accepted: Sequence[str]) -> bool:
    held = str(header.get("typ") or "").lower().removeprefix("application/")

    return held in accepted


def unverified(error: jwt.PyJWTError) -> InvalidToken:
    if isinstance(error, jwt.ExpiredSignatureError):
        said = "that token has expired"
    elif isinstance(error, (jwt.ImmatureSignatureError, jwt.InvalidIssuedAtError)):
        said = "that token is not valid yet"
    elif isinstance(error, jwt.InvalidIssuerError):
        said = "that token was issued by another server"
    elif isinstance(error, jwt.InvalidAudienceError):
        said = "that token was issued for another app"
    elif isinstance(error, jwt.MissingRequiredClaimError):
        said = "that token is missing a claim it needs"
    elif isinstance(error, jwt.InvalidSignatureError):
        said = "that token was not signed by this issuer"
    elif isinstance(error, jwt.DecodeError):
        said = "that token is not a signed JWT"
    else:
        said = "that token could not be verified"

    return InvalidToken(f"masks: {said}")


def unverified_header(token: str) -> dict[str, Any]:
    segment, dot, rest = token.partition(".")

    if not dot or rest.count(".") != 1 or not SEGMENT.fullmatch(segment) or len(segment) % 4 == 1:
        raise InvalidToken("masks: that is not a signed JWT")

    try:
        header = json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))
    except ValueError as error:
        raise InvalidToken("masks: that is not a signed JWT") from error

    if not isinstance(header, dict):
        raise InvalidToken("masks: that is not a signed JWT: its header is not an object")

    return header


def recent(signed_in_at: Any, max_age: int) -> bool:
    return isinstance(signed_in_at, (int, float)) and signed_in_at + max_age + LEEWAY >= time.time()


def half_hash(value: str, algorithm: str) -> str:
    digest = HASHES[algorithm](value.encode()).digest()

    return encode(digest[: len(digest) // 2])


class Retry:
    def __init__(self) -> None:
        self.at = 0.0
        self.failure: Exception | None = None
        self._wait = FIRST_BACKOFF

    def waiting(self, now: float) -> bool:
        return now < self.at

    def failed(self, now: float, error: Exception) -> None:
        self.at = now + self._wait
        self.failure = error
        self._wait = min(self._wait * 2, LONGEST_BACKOFF)

    def succeeded(self) -> None:
        self.at = 0.0
        self.failure = None
        self._wait = FIRST_BACKOFF


class KeySet:
    def __init__(self, issuer: Issuer) -> None:
        self.issuer = issuer
        self._keys: list[dict[str, Any]] = []
        self._fetched_at = 0.0
        self._lock = threading.Lock()
        self._retry = Retry()

    def key(self, kid: str) -> Flow[dict[str, Any]]:
        now = time.monotonic()
        age = now - self._fetched_at
        found = self._find(kid)

        if found is not None and (age < KEYS_LIFETIME or self._retry.waiting(now)):
            return found

        if self._retry.waiting(now) and self._retry.failure is not None:
            raise self._retry.failure

        if age >= KEYS_PATIENCE or not self._fetched_at:
            try:
                body = required((yield get(self.issuer.metadata.jwks_uri)))
            except (Error, httpx.HTTPError) as error:
                with self._lock:
                    self._retry.failed(now, error)

                if found is None:
                    raise

                return found

            keys = body.get("keys")

            with self._lock:
                self._keys = [key for key in keys if isinstance(key, dict)] if isinstance(keys, list) else []
                self._fetched_at = now
                self._retry.succeeded()

            found = self._find(kid)

        if found is None:
            raise InvalidToken(f"masks: {self.issuer.url} publishes no key {kid!r}")

        return found

    def _find(self, kid: str) -> dict[str, Any] | None:
        with self._lock:
            return next((key for key in self._keys if key.get("kid") == kid and key.get("use", "sig") == "sig"), None)

    def verify(
        self,
        token: str,
        *,
        accepted: Sequence[str],
        audience: str | Sequence[str] | None,
        require: Sequence[str],
    ) -> Flow[tuple[dict[str, Any], str]]:
        header = unverified_header(token)
        algorithm = header.get("alg")

        if algorithm not in SIGNING_ALGORITHMS:
            raise InvalidToken(f"masks: {algorithm!r} is not an algorithm masks signs with")

        if not typed(header, accepted):
            raise InvalidToken(f"masks: that token is typed {header.get('typ')!r}")

        jwk = yield from self.key(str(header.get("kid") or ""))

        try:
            claims = jwt.decode(
                token,
                jwt.PyJWK(jwk, algorithm=algorithm).key,
                algorithms=[algorithm],
                audience=audience,
                issuer=self.issuer.url,
                leeway=LEEWAY,
                options={"require": list(require), "verify_aud": audience is not None},
            )
        except jwt.PyJWTError as error:
            raise unverified(error) from error

        return claims, str(algorithm)


def same(held: object, expected: str) -> bool:
    return isinstance(held, str) and bool(held) and hmac.compare_digest(held.encode(), expected.encode())
