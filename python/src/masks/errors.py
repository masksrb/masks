from __future__ import annotations

import json

import httpx

from .failures import FAILURES


def failure(key: str, *values: object) -> tuple[str, str]:
    code, template = FAILURES[key]

    return code, template.format(*values)


def saying(key: str, *values: object) -> str:
    return failure(key, *values)[1]


class MasksError(Exception):
    code: str
    description: str
    status: int | None
    uri: str

    def __init__(self, code: str, description: str = "", *, status: int | None = None, uri: str = "") -> None:
        self.code = code
        self.description = description
        self.status = status
        self.uri = uri
        super().__init__(f"masks: {code}: {description}" if description else f"masks: {code}")


class Refused(MasksError):
    @classmethod
    def of(cls, key: str, *values: object) -> Refused:
        return cls(*failure(key, *values))


class InvalidToken(MasksError):
    missing: bool

    def __init__(self, description: str, *, code: str = "invalid_token", missing: bool = False) -> None:
        super().__init__(code, description)
        self.missing = missing

    @classmethod
    def of(cls, key: str, *values: object) -> InvalidToken:
        code, description = failure(key, *values)

        return cls(description, code=code, missing=key == "no_token")


class Forbidden(MasksError):
    scope: str

    def __init__(self, code: str, description: str, *, scope: str = "") -> None:
        super().__init__(code, description, status=403)
        self.scope = scope

    @classmethod
    def of(cls, key: str, *values: object) -> Forbidden:
        return cls(*failure(key, *values))


class Unavailable(MasksError):
    def __init__(self, description: str) -> None:
        super().__init__("temporarily_unavailable", description)

    @classmethod
    def of(cls, key: str, *values: object) -> Unavailable:
        return cls(saying(key, *values))


class Insecure(MasksError):
    def __init__(self, description: str) -> None:
        super().__init__("insecure_url", description)

    @classmethod
    def of(cls, key: str, *values: object) -> Insecure:
        return cls(saying(key, *values))


class Foreign(MasksError):
    def __init__(self, description: str) -> None:
        super().__init__("foreign_origin", description)

    @classmethod
    def of(cls, key: str, *values: object) -> Foreign:
        return cls(saying(key, *values))


class DelegationRefused(MasksError):
    secret: str

    def __init__(self, code: str, description: str = "", *, status: int | None = None, secret: str = "") -> None:
        super().__init__(code, description, status=status)
        self.secret = secret

    @property
    def sign_in_again(self) -> bool:
        return self.code in ("login_required", "interaction_required")

    @classmethod
    def of(cls, key: str, *values: object) -> DelegationRefused:
        return cls(*failure(key, *values))


class DelegationUnavailable(MasksError):
    secret: str

    def __init__(self, description: str, *, secret: str = "") -> None:
        super().__init__("temporarily_unavailable", description)
        self.secret = secret

    @classmethod
    def of(cls, key: str, *values: object) -> DelegationUnavailable:
        return cls(saying(key, *values))


def has_code(error: BaseException, code: str) -> bool:
    return isinstance(error, MasksError) and error.code == code


READ_LIMIT = 1 << 20


def refused(response: httpx.Response) -> Refused:
    try:
        body = json.loads(response.content[:READ_LIMIT])
    except ValueError:
        body = None

    if isinstance(body, dict) and isinstance(body.get("error"), str) and body["error"]:
        return Refused(
            body["error"],
            str(body.get("error_description") or ""),
            status=response.status_code,
            uri=str(body.get("error_uri") or ""),
        )

    return Refused(*failure("answered_status", response.request.url, response.status_code), status=response.status_code)
