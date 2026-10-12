from __future__ import annotations

import hashlib
import re
import secrets
import time
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

from .keys import encode
from .models import Token, _strings

DEFAULT_SCOPE = ("openid", "profile", "email")
OPENID = "openid"
ORGANIZATION = "organization"
ORGANIZATION_CLAIM = "org"
ORGANIZATIONS_CLAIM = "orgs"
AVATARS_CLAIM = "masks:avatars"
DELEGATE_SCOPE = "masks:delegate:"
LOGOUT_EVENT = "http://schemas.openid.net/event/backchannel-logout"
CHALLENGE_METHOD = "S256"

ORGANIZATION_KEY = re.compile(r"[a-z0-9][a-z0-9-]*")


def organization_key(value: object) -> str | None:
    key = str(value or "").strip().lower()

    return key if ORGANIZATION_KEY.fullmatch(key) else None


def code_verifier() -> str:
    return secrets.token_urlsafe(64)


def code_challenge(verifier: str) -> str:
    return encode(hashlib.sha256(verifier.encode()).digest())


def flattened(params: Mapping[str, Any]) -> dict[str, str]:
    held: dict[str, str] = {}

    for key, value in params.items():
        if isinstance(value, (list, tuple)):
            value = value[0] if value else ""

        held[str(key)] = "" if value is None else str(value)

    return held


@dataclass(frozen=True)
class AuthorizationRequest:
    url: str
    state: str
    redirect_uri: str
    verifier: str = field(repr=False)
    nonce: str = ""
    scope: str = ""
    resource: tuple[str, ...] = ()
    provider: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "url": self.url,
            "state": self.state,
            "redirect_uri": self.redirect_uri,
            "verifier": self.verifier,
            "nonce": self.nonce,
            "scope": self.scope,
            "resource": list(self.resource),
            "provider": self.provider,
        }

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> AuthorizationRequest:
        return cls(
            url=str(data.get("url") or ""),
            state=str(data.get("state") or ""),
            redirect_uri=str(data.get("redirect_uri") or ""),
            verifier=str(data.get("verifier") or ""),
            nonce=str(data.get("nonce") or ""),
            scope=str(data.get("scope") or ""),
            resource=tuple(_strings(data.get("resource"))),
            provider=str(data.get("provider") or ""),
        )

    @property
    def scopes(self) -> list[str]:
        return self.scope.split()


@dataclass
class SignIn:
    token: Token
    claims: dict[str, Any] = field(default_factory=dict)

    @property
    def subject(self) -> str:
        return str(self.claims.get("sub") or "")


@dataclass(frozen=True)
class Logout:
    subject: str
    sid: str
    id: str
    issued_at: int
    raw: dict[str, Any] = field(repr=False)


@dataclass(frozen=True)
class HeldConnection:
    connection: str
    provider: str
    provider_name: str = ""
    label: str = ""
    subject: str = ""
    secret: str = field(default="", repr=False)


@dataclass(frozen=True)
class Upstream:
    access_token: str = field(repr=False)
    expires_at: float | None
    scope: str
    secret: str = field(repr=False)

    def expired(self, leeway: float = 60) -> bool:
        return self.expires_at is not None and time.time() + leeway >= self.expires_at
