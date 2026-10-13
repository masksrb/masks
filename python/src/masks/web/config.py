from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any, TypeAlias, TypeVar, cast

import httpx

from ..oidc import DELEGATE_SCOPE, Logout
from .credentials import Credentials, FileCredentials
from .person import Person, Privilege, privileges
from .sessions import LIFETIME, CookieSessions, SessionBackend
from .stores import AsyncStore, MemoryStore, Store

T = TypeVar("T")

DEFAULT_SCOPE = ("openid", "profile", "email", "offline_access")

Setting: TypeAlias = "T | Callable[[Any], T]"


def resolve(value: Setting[T], request: Any) -> T:
    if callable(value) and not isinstance(value, type):
        return value(request)

    return cast(T, value)


@dataclass
class Config:
    issuer: Setting[str]
    secret: str | bytes | Sequence[str | bytes] = ""
    resource: Setting[str] = ""
    name: Setting[str] = "An app"
    scope: Sequence[str] = DEFAULT_SCOPE
    resource_scopes: Sequence[str] | Mapping[str, str] = ()
    privileges: Mapping[str, Any] = field(default_factory=dict)
    namespace: str = ""
    organization: Setting[str] = ""
    credentials: Setting[Credentials] = field(default_factory=FileCredentials)
    sessions: SessionBackend | None = None
    store: Store | AsyncStore = field(default_factory=MemoryStore)
    session_lifetime: int = LIFETIME
    base_url: Setting[str] = ""
    prefix: str = "/auth"
    after_sign_in: str = "/"
    after_sign_out: str = "/"
    sign_out_of_issuer: bool = False
    manages: str | Callable[[Person], bool] | None = None
    logged_out: Callable[[Logout], None] | None = None
    delegation_redirect_uri: Setting[str] = ""
    allow_plain_http: bool = False
    cookie_secure: bool = True
    http: httpx.Client | None = None
    async_http: httpx.AsyncClient | None = None

    def __post_init__(self) -> None:
        self.prefix = "/" + self.prefix.strip("/") if self.prefix.strip("/") else ""
        self.known: dict[str, Privilege] = privileges(self.privileges)

        if self.sessions is None:
            if not self.secret:
                raise ValueError("masks: sessions need a secret of at least 32 bytes, or a session backend")

            self.sessions = CookieSessions(self.secret, lifetime=self.session_lifetime)

    @property
    def backend(self) -> SessionBackend:
        assert self.sessions is not None

        return self.sessions

    def scope_for(self, requested: str) -> list[str] | None:
        wanted = [scope for name in requested.split() if name in self.known for scope in self.known[name].scopes]

        if not wanted:
            return None

        return list(dict.fromkeys([*self.scope, *wanted]))

    def approved_scope(self) -> list[str]:
        asked = list(dict.fromkeys([*self.scope, *(scope for held in self.known.values() for scope in held.scopes)]))
        delegated = [DELEGATE_SCOPE] if self.delegation_redirect_uri else []

        if not self.namespace:
            return asked + delegated

        return [scope for scope in asked if not scope.startswith(self.namespace)] + [self.namespace, *delegated]

    def manager(self, person: Person) -> bool:
        if self.manages is None:
            return False

        if isinstance(self.manages, str):
            return person.signed_in and person.has_privilege(self.manages)

        return person.signed_in and bool(self.manages(person))
