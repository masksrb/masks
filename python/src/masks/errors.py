from __future__ import annotations

import json

import httpx


class MasksError(Exception):
    pass


class Error(MasksError):
    def __init__(self, code: str, description: str = "", *, status: int | None = None, uri: str = "") -> None:
        self.code = code
        self.description = description
        self.status = status
        self.uri = uri
        super().__init__(f"masks: {code}: {description}" if description else f"masks: {code}")


class InvalidToken(MasksError):
    pass


class Unavailable(MasksError):
    pass


class InsecureURL(MasksError):
    pass


class ForeignOrigin(MasksError):
    pass


def has_code(error: BaseException, code: str) -> bool:
    return isinstance(error, Error) and error.code == code


READ_LIMIT = 1 << 20


def refused(response: httpx.Response) -> Error:
    try:
        body = json.loads(response.content[:READ_LIMIT])
    except ValueError:
        body = None

    if isinstance(body, dict) and isinstance(body.get("error"), str) and body["error"]:
        return Error(
            body["error"],
            str(body.get("error_description") or ""),
            status=response.status_code,
            uri=str(body.get("error_uri") or ""),
        )

    return Error("server_error", f"{response.request.url} answered {response.status_code}", status=response.status_code)
