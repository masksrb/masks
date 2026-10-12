from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field, fields
from typing import Any, Literal

from .dpop import DPOP

AuthMethod = Literal["client_secret_basic", "client_secret_post", "private_key_jwt", "none"]

CLIENT_SECRET_BASIC: AuthMethod = "client_secret_basic"
CLIENT_SECRET_POST: AuthMethod = "client_secret_post"
PRIVATE_KEY_JWT: AuthMethod = "private_key_jwt"
NO_AUTH: AuthMethod = "none"

GRANT_CLIENT_CREDENTIALS = "client_credentials"
GRANT_REFRESH_TOKEN = "refresh_token"
GRANT_DEVICE_CODE = "urn:ietf:params:oauth:grant-type:device_code"
GRANT_TOKEN_EXCHANGE = "urn:ietf:params:oauth:grant-type:token-exchange"

ACCESS_TOKEN_TYPE = "urn:ietf:params:oauth:token-type:access_token"
ID_TOKEN_TYPE = "urn:ietf:params:oauth:token-type:id_token"
UPSTREAM_ACCESS_TOKEN_TYPE = "urn:masks:params:oauth:token-type:upstream_access_token"

EXPIRY_LEEWAY = 30


def _strings(value: Any) -> list[str]:
    return [str(item) for item in value] if isinstance(value, list) else []


def _known(cls: type, data: dict[str, Any]) -> dict[str, Any]:
    named = {item.name for item in fields(cls)}

    return {key: value for key, value in data.items() if key in named}


@dataclass(frozen=True)
class Tenant:
    uuid: str = ""
    subdomain: str = ""
    name: str = ""


@dataclass(frozen=True)
class Metadata:
    issuer: str
    tenant: Tenant = field(default_factory=Tenant)
    authorization_endpoint: str = ""
    token_endpoint: str = ""
    userinfo_endpoint: str = ""
    jwks_uri: str = ""
    registration_endpoint: str = ""
    device_authorization_endpoint: str = ""
    handshake_endpoint: str = ""
    revocation_endpoint: str = ""
    introspection_endpoint: str = ""
    end_session_endpoint: str = ""
    enrollment_endpoint: str = ""
    scopes_supported: list[str] = field(default_factory=list)
    grant_types_supported: list[str] = field(default_factory=list)
    token_endpoint_auth_methods_supported: list[str] = field(default_factory=list)
    dpop_signing_alg_values_supported: list[str] = field(default_factory=list)
    authorization_response_iss_parameter_supported: bool = False
    backchannel_logout_supported: bool = False

    ENDPOINTS = (
        "authorization_endpoint",
        "token_endpoint",
        "userinfo_endpoint",
        "jwks_uri",
        "registration_endpoint",
        "device_authorization_endpoint",
        "handshake_endpoint",
        "revocation_endpoint",
        "introspection_endpoint",
        "end_session_endpoint",
        "enrollment_endpoint",
    )

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Metadata:
        found = data.get("tenant")
        tenant: dict[str, Any] = found if isinstance(found, dict) else {}
        held: dict[str, Any] = {name: str(data.get(name) or "") for name in cls.ENDPOINTS}

        for name in (
            "scopes_supported",
            "grant_types_supported",
            "token_endpoint_auth_methods_supported",
            "dpop_signing_alg_values_supported",
        ):
            held[name] = _strings(data.get(name))

        return cls(
            issuer=str(data.get("issuer") or ""),
            tenant=Tenant(**{key: str(value) for key, value in _known(Tenant, tenant).items()}),
            authorization_response_iss_parameter_supported=data.get("authorization_response_iss_parameter_supported")
            is True,
            backchannel_logout_supported=data.get("backchannel_logout_supported") is True,
            **held,
        )

    def endpoints(self) -> list[str]:
        return [value for value in (getattr(self, name) for name in self.ENDPOINTS) if value]


@dataclass(frozen=True)
class ResourceMetadata:
    resource: str
    authorization_servers: list[str] = field(default_factory=list)
    scopes_supported: list[str] = field(default_factory=list)
    bearer_methods_supported: list[str] = field(default_factory=list)
    resource_name: str = ""

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ResourceMetadata:
        return cls(
            resource=str(data.get("resource") or ""),
            authorization_servers=_strings(data.get("authorization_servers")),
            scopes_supported=_strings(data.get("scopes_supported")),
            bearer_methods_supported=_strings(data.get("bearer_methods_supported")),
            resource_name=str(data.get("resource_name") or ""),
        )


@dataclass(frozen=True)
class Issuer:
    url: str
    metadata: Metadata
    allow_plain_http: bool = False


@dataclass
class Token:
    access_token: str
    token_type: str = "Bearer"
    refresh_token: str | None = None
    id_token: str | None = None
    scope: str = ""
    expires_in: int | None = None
    expires_at: float | None = None
    issued_token_type: str | None = None
    delegations: list[dict[str, Any]] | None = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Token:
        held = _known(cls, data)
        found = held.get("delegations")
        held["delegations"] = [item for item in found if isinstance(item, dict)] if isinstance(found, list) else None
        token = cls(**held)

        if token.expires_at is None and isinstance(token.expires_in, int) and token.expires_in > 0:
            token.expires_at = time.time() + token.expires_in

        return token

    def to_dict(self) -> dict[str, Any]:
        return {key: value for key, value in asdict(self).items() if value is not None}

    def valid(self) -> bool:
        return bool(self.access_token) and (self.expires_at is None or self.expires_at - time.time() > EXPIRY_LEEWAY)

    @property
    def bound(self) -> bool:
        return self.token_type.lower() == DPOP.lower()

    @property
    def scopes(self) -> list[str]:
        return self.scope.split()


@dataclass
class DeviceAuthorization:
    device_code: str
    user_code: str
    verification_uri: str
    verification_uri_complete: str = ""
    expires_in: int = 0
    interval: int = 0
    expires_at: float | None = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> DeviceAuthorization:
        held = cls(**_known(cls, data))

        if held.expires_in > 0:
            held.expires_at = time.time() + held.expires_in

        return held


@dataclass
class ClientMetadata:
    client_name: str | None = None
    redirect_uris: list[str] | None = None
    grant_types: list[str] | None = None
    response_types: list[str] | None = None
    scope: str | None = None
    token_endpoint_auth_method: AuthMethod | None = None
    application_type: str | None = None
    client_uri: str | None = None
    logo_uri: str | None = None
    jwks: dict[str, Any] | None = None
    jwks_uri: str | None = None
    resources: list[str] | None = None
    dpop_bound_access_tokens: bool | None = None
    backchannel_logout_uri: str | None = None
    post_logout_redirect_uris: list[str] | None = None

    def to_dict(self) -> dict[str, Any]:
        return {key: value for key, value in asdict(self).items() if value not in (None, "", [], {})}


@dataclass
class Registration(ClientMetadata):
    client_id: str = ""
    client_secret: str | None = None
    client_secret_expires_at: int | None = None
    client_id_issued_at: int | None = None
    registration_access_token: str | None = None
    registration_client_uri: str | None = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Registration:
        return cls(**_known(cls, data))

    def kept_from(self, held: Registration) -> Registration:
        if not self.client_secret:
            self.client_secret = held.client_secret
            self.client_secret_expires_at = held.client_secret_expires_at

        self.registration_access_token = self.registration_access_token or held.registration_access_token
        self.registration_client_uri = self.registration_client_uri or held.registration_client_uri

        return self


def _spaced(value: Any) -> str:
    if isinstance(value, list):
        return " ".join(str(item) for item in value)

    return str(value or "")


def _number(value: Any) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


@dataclass
class Enrollment:
    initial_access_token: str = field(repr=False)
    scope: str = ""
    expires_in: int = 0
    expires_at: float | None = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Enrollment:
        expires_in = _number(data.get("expires_in")) or 0

        return cls(
            initial_access_token=str(data.get("initial_access_token") or ""),
            scope=_spaced(data.get("scope")),
            expires_in=expires_in,
            expires_at=time.time() + expires_in if expires_in > 0 else None,
        )

    @property
    def scopes(self) -> list[str]:
        return self.scope.split()


@dataclass(frozen=True)
class Introspection:
    active: bool
    scope: str = ""
    client_id: str = ""
    username: str = ""
    token_type: str = ""
    subject: str = ""
    audience: list[str] = field(default_factory=list)
    issuer: str = ""
    id: str = ""
    expiry: int | None = None
    issued_at: int | None = None
    thumbprint: str | None = None
    tenant: Tenant | None = None
    raw: dict[str, Any] = field(default_factory=dict, repr=False)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Introspection:
        if data.get("active") is not True:
            return cls(active=False, raw=data)

        audience = data.get("aud")
        found = data.get("cnf")
        confirmation: dict[str, Any] = found if isinstance(found, dict) else {}
        tenant = data.get("tenant")

        return cls(
            active=True,
            scope=_spaced(data.get("scope")),
            client_id=str(data.get("client_id") or ""),
            username=str(data.get("username") or ""),
            token_type=str(data.get("token_type") or ""),
            subject=str(data.get("sub") or ""),
            audience=_strings(audience) if isinstance(audience, list) else [str(audience)] if audience else [],
            issuer=str(data.get("iss") or ""),
            id=str(data.get("jti") or ""),
            expiry=_number(data.get("exp")),
            issued_at=_number(data.get("iat")),
            thumbprint=str(confirmation["jkt"]) if confirmation.get("jkt") else None,
            tenant=Tenant(**{key: str(value) for key, value in _known(Tenant, tenant).items()})
            if isinstance(tenant, dict)
            else None,
            raw=data,
        )

    @property
    def scopes(self) -> list[str]:
        return self.scope.split() if self.active else []

    def has_scope(self, scope: str) -> bool:
        return scope in self.scopes

    @property
    def bound(self) -> bool:
        return bool(self.thumbprint)
