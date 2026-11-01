from __future__ import annotations

import json
from collections.abc import Awaitable, Callable, MutableMapping
from typing import Any

from .dpop import DPOP
from .errors import InvalidToken, Unavailable
from .verifier import PROOF_ALGORITHMS, AsyncVerifier

Scope = MutableMapping[str, Any]
Receive = Callable[[], Awaitable[MutableMapping[str, Any]]]
Send = Callable[[MutableMapping[str, Any]], Awaitable[None]]
App = Callable[[Scope, Receive, Send], Awaitable[None]]

CLAIMS = "masks.claims"


def challenges(description: str) -> list[tuple[bytes, bytes]]:
    algorithms = f'algs="{" ".join(PROOF_ALGORITHMS)}"'

    if not description:
        return [(b"www-authenticate", b"Bearer"), (b"www-authenticate", f"{DPOP} {algorithms}".encode())]

    quoted = description.replace("\\", "\\\\").replace('"', '\\"')
    challenge = f'error="invalid_token", error_description="{quoted}"'

    return [
        (b"www-authenticate", f"Bearer {challenge}".encode()),
        (b"www-authenticate", f"{DPOP} {challenge}, {algorithms}".encode()),
    ]


def requested_url(scope: Scope) -> str:
    headers = dict(scope.get("headers") or [])
    host = headers.get(b"host", b"").decode("latin-1")

    if not host and scope.get("server"):
        server_host, server_port = scope["server"]
        host = f"{server_host}:{server_port}"

    scheme = {"ws": "http", "wss": "https"}.get(scope.get("scheme", "http"), scope.get("scheme", "http"))
    path = scope.get("raw_path") or scope.get("path", "/").encode()
    query = scope.get("query_string") or b""
    target = f"{scheme}://{host}{path.decode('latin-1')}"

    return f"{target}?{query.decode('latin-1')}" if query else target


class Middleware:
    def __init__(self, app: App, verifier: AsyncVerifier) -> None:
        self.app = app
        self.verifier = verifier

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return

        headers = [(name.decode("latin-1"), value.decode("latin-1")) for name, value in scope.get("headers") or []]
        method = scope.get("method", "GET")

        try:
            claims = await self.verifier.authenticate(method, requested_url(scope), headers)
        except InvalidToken as error:
            await self._refuse(scope, send, error.description, missing=error.missing)
            return
        except Unavailable:
            await self._unavailable(scope, send)
            return

        scope[CLAIMS] = claims
        scope.setdefault("state", {})["masks_claims"] = claims

        await self.app(scope, receive, send)

    async def _unavailable(self, scope: Scope, send: Send) -> None:
        if scope["type"] == "websocket":
            await send({"type": "websocket.close", "code": 1013})
            return

        body = json.dumps(
            {"error": "temporarily_unavailable", "error_description": "the token could not be checked just now"}
        ).encode()

        await send(
            {
                "type": "http.response.start",
                "status": 503,
                "headers": [(b"content-type", b"application/json"), (b"retry-after", b"5")],
            }
        )
        await send({"type": "http.response.body", "body": body})

    async def _refuse(self, scope: Scope, send: Send, description: str, *, missing: bool = False) -> None:
        if scope["type"] == "websocket":
            await send({"type": "websocket.close", "code": 1008})
            return

        body = json.dumps({"error": "invalid_token", "error_description": description}).encode()

        await send(
            {
                "type": "http.response.start",
                "status": 401,
                "headers": [(b"content-type", b"application/json"), *challenges("" if missing else description)],
            }
        )
        await send({"type": "http.response.body", "body": body})
