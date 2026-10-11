from __future__ import annotations

import base64
import hashlib
import json
import secrets
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from jwt.algorithms import ECAlgorithm

THUMBED = {
    "EC": ("crv", "kty", "x", "y"),
    "RSA": ("e", "kty", "n"),
}

PRIVATE_MEMBERS = frozenset({"d", "p", "q", "dp", "dq", "qi", "k"})


def encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def random_id() -> str:
    return secrets.token_urlsafe(24)


def thumbprint(jwk: dict[str, Any]) -> str:
    named = THUMBED.get(str(jwk.get("kty")))

    if named is None:
        raise ValueError("that key is of a kind masks does not read")

    held = {field: jwk.get(field) for field in named}

    if any(not isinstance(value, str) or not value for value in held.values()):
        raise ValueError("that key is missing part of itself")

    canonical = json.dumps(held, separators=(",", ":"), sort_keys=True)

    return encode(hashlib.sha256(canonical.encode()).digest())


class Key:
    def __init__(self, private: ec.EllipticCurvePrivateKey) -> None:
        if not isinstance(private, ec.EllipticCurvePrivateKey) or not isinstance(private.curve, ec.SECP256R1):
            raise ValueError("masks: a key is a private P-256 key")

        self._private = private
        public = json.loads(ECAlgorithm.to_jwk(private.public_key()))
        self._thumbprint = thumbprint(public)
        self._public = {**public, "kid": self._thumbprint, "alg": "ES256", "use": "sig"}

    @classmethod
    def generate(cls) -> Key:
        return cls(ec.generate_private_key(ec.SECP256R1()))

    @classmethod
    def from_jwk(cls, value: str | bytes | dict[str, Any]) -> Key:
        held = json.loads(value) if isinstance(value, (str, bytes)) else dict(value)

        if held.get("kty") != "EC" or held.get("crv") != "P-256" or "d" not in held:
            raise ValueError("masks: a key is a private P-256 key")

        private = ECAlgorithm.from_jwk(held)

        if not isinstance(private, ec.EllipticCurvePrivateKey):
            raise ValueError("masks: a key is a private P-256 key")

        return cls(private)

    @property
    def thumbprint(self) -> str:
        return self._thumbprint

    def to_jwk(self) -> dict[str, Any]:
        private = json.loads(ECAlgorithm.to_jwk(self._private))

        return {**private, "kid": self._thumbprint, "alg": "ES256", "use": "sig"}

    def public_jwk(self) -> dict[str, Any]:
        return dict(self._public)

    def jwks(self) -> dict[str, Any]:
        return {"keys": [self.public_jwk()]}

    def sign(self, typ: str, claims: dict[str, Any], *, embed: bool) -> str:
        headers: dict[str, Any] = {"typ": typ}

        if embed:
            headers["jwk"] = {field: self._public[field] for field in ("kty", "crv", "x", "y")}
        else:
            headers["kid"] = self._thumbprint

        return jwt.encode(claims, self._private, algorithm="ES256", headers=headers)

    def __repr__(self) -> str:
        return f"Key(thumbprint={self._thumbprint!r})"
