from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

from ..errors import Forbidden, failure
from ..oidc import AVATARS_CLAIM, ORGANIZATION, ORGANIZATION_CLAIM, ORGANIZATIONS_CLAIM

OWNER = "owner"


@dataclass(frozen=True)
class Privilege:
    name: str
    scopes: tuple[str, ...] = ()
    roles: tuple[str, ...] = ()
    organization: str = ""

    KEYS = ("scope", "role", "organization")

    @classmethod
    def build(cls, name: str, spec: Any) -> Privilege:
        held: Mapping[str, Any] = spec if isinstance(spec, Mapping) else {"scope": spec}
        unknown = set(held) - set(cls.KEYS)

        if unknown:
            raise ValueError(
                f"masks: the {name} privilege names {', '.join(sorted(unknown))}, "
                "which is not scope, role, or organization"
            )

        return cls(
            name=str(name),
            scopes=tuple(listed(held.get("scope"))),
            roles=tuple(listed(held.get("role"))),
            organization=str(held.get("organization") or ""),
        )


def listed(value: Any) -> list[str]:
    if value is None:
        return []

    if isinstance(value, str):
        return value.split()

    return [str(item) for item in value]


@dataclass(frozen=True)
class Organization:
    id: str
    key: str
    name: str = ""
    role: str = ""

    @classmethod
    def read(cls, value: Any) -> Organization | None:
        if not isinstance(value, Mapping):
            return None

        found = cls(**{name: str(value.get(name) or "") for name in ("id", "key", "name", "role")})

        return found if found.id and found.key and found.role else None

    def has_role(self, *roles: str) -> bool:
        return self.role in roles

    @property
    def owner(self) -> bool:
        return self.has_role(OWNER)

    def to_dict(self) -> dict[str, str]:
        return {"id": self.id, "key": self.key, "name": self.name, "role": self.role}


@dataclass(frozen=True)
class Actor:
    signed_in: bool = False
    claims: dict[str, Any] = field(default_factory=dict)
    scopes: tuple[str, ...] = ()
    access_token: str = field(default="", repr=False)
    expires_at: float | None = None
    account_url: str = ""
    known: Mapping[str, Privilege] = field(default_factory=dict, repr=False)
    by_token: bool = False
    avatar_url: str = ""

    def __getitem__(self, claim: str) -> Any:
        return self.claims.get(claim)

    def get(self, claim: str, default: Any = None) -> Any:
        return self.claims.get(claim, default)

    @property
    def subject(self) -> str:
        return str(self.claims.get("sub") or "")

    @property
    def name(self) -> str:
        return str(self.claims.get("name") or "")

    @property
    def nickname(self) -> str:
        return str(self.claims.get("preferred_username") or "")

    @property
    def email(self) -> str:
        return str(self.claims.get("email") or "")

    @property
    def email_verified(self) -> bool:
        return self.claims.get("email_verified") is True

    @property
    def avatars(self) -> dict[str, str]:
        found = self.claims.get(AVATARS_CLAIM)

        return {str(key): str(value) for key, value in found.items() if value} if isinstance(found, Mapping) else {}

    @property
    def picture(self) -> str:
        if self.avatar_url and self.avatars.get("photo"):
            return self.avatar_url

        return str(self.claims.get("picture") or self.avatars.get("photo") or self.avatars.get("identicon") or "")

    @property
    def tenant(self) -> dict[str, str]:
        found = self.claims.get("tenant")

        return {str(key): str(value) for key, value in found.items()} if isinstance(found, Mapping) else {}

    @property
    def organization(self) -> Organization | None:
        return Organization.read(self.claims.get(ORGANIZATION_CLAIM))

    @property
    def organizations(self) -> list[Organization]:
        found = self.claims.get(ORGANIZATIONS_CLAIM)
        held = [Organization.read(item) for item in found] if isinstance(found, list) else []

        return [item for item in held if item is not None]

    def has_role(self, *roles: str) -> bool:
        held = self.organization

        return held is not None and held.has_role(*roles)

    def permits(self, scope: str) -> bool:
        return scope in self.scopes

    def member(self, *roles: str, organization: str = "") -> Organization:
        held = self.organization

        if held is None:
            raise Forbidden(*failure("no_organization"), scope=ORGANIZATION)

        if organization and organization not in (held.key, held.id):
            raise Forbidden.of("other_organization", held.key, organization)

        if roles and not held.has_role(*roles):
            raise Forbidden.of("other_role", held.role, held.key, " or ".join(roles))

        return held

    def privilege(self, name: str) -> Privilege:
        try:
            return self.known[name]
        except KeyError:
            raise ValueError(f"masks: no privilege is named {name}") from None

    def holds(self, privilege: Privilege) -> bool:
        if not set(privilege.scopes) <= set(self.scopes):
            return False

        if not privilege.roles and not privilege.organization:
            return True

        try:
            self.member(*privilege.roles, organization=privilege.organization)
        except Forbidden:
            return False

        return True

    def has_privilege(self, *names: str) -> bool:
        wanted = [self.privilege(name) for name in names]

        return self.signed_in and all(self.holds(privilege) for privilege in wanted)

    @property
    def privileges(self) -> list[str]:
        if not self.signed_in:
            return []

        return [name for name, privilege in self.known.items() if self.holds(privilege)]

    def to_dict(self) -> dict[str, Any]:
        found = {
            "signed_in": self.signed_in,
            "subject": self.subject or None,
            "name": self.name or None,
            "nickname": self.nickname or None,
            "email": self.email or None,
            "email_verified": self.claims.get("email_verified"),
            "picture": self.picture or None,
            "avatars": self.avatars or None,
            "tenant": self.tenant or None,
            "organization": self.organization.to_dict() if self.organization else None,
            "organizations": [item.to_dict() for item in self.organizations] or None,
            "scopes": list(self.scopes),
            "privileges": self.privileges,
            "expires_at": int(self.expires_at) if self.expires_at else None,
            "account_url": self.account_url or None,
        }

        return {key: value for key, value in found.items() if value is not None}


def nobody(known: Mapping[str, Privilege] | None = None) -> Actor:
    return Actor(known=known or {})


def privileges(spec: Mapping[str, Any]) -> dict[str, Privilege]:
    return {str(name): Privilege.build(str(name), value) for name, value in spec.items()}


def scoped(names: Sequence[str], known: Mapping[str, Privilege]) -> list[Privilege]:
    found = []

    for name in names:
        if name not in known:
            raise ValueError(f"masks: no privilege is named {name}")

        found.append(known[name])

    return found
