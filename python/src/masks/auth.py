from __future__ import annotations

import inspect
from collections.abc import AsyncGenerator, Generator
from typing import Any

import httpx

from .dpop import DPOP, proof
from .errors import ForeignOrigin
from .flows import origin
from .keys import Key
from .models import Token


class Auth(httpx.Auth):
    requires_request_body = True

    def __init__(self, source: Any, *origins: str, key: Key | None = None) -> None:
        self.source = source
        self.key = key
        self.origins = frozenset(origin(held) for held in origins)
        self._nonces: dict[str, str] = {}

    def sync_auth_flow(self, request: httpx.Request) -> Generator[httpx.Request, httpx.Response, None]:
        self._allowed(request)

        if inspect.iscoroutinefunction(self.source.token):
            raise TypeError("masks: an httpx.Client needs a token source that is not async")

        yield from self._signed(request, self.source.token())

    async def async_auth_flow(self, request: httpx.Request) -> AsyncGenerator[httpx.Request, httpx.Response]:
        self._allowed(request)

        token = self.source.token()

        if inspect.isawaitable(token):
            token = await token

        flow = self._signed(request, token)
        outgoing = next(flow)

        while True:
            response = yield outgoing

            try:
                outgoing = flow.send(response)
            except StopIteration:
                return

    def _allowed(self, request: httpx.Request) -> None:
        if origin(request.url) not in self.origins:
            named = ", ".join(sorted(self.origins)) or "no origin"
            raise ForeignOrigin(f"masks: this auth holds tokens only for {named}, not {origin(request.url)}")

    def _signed(self, request: httpx.Request, token: Token) -> Generator[httpx.Request, httpx.Response, None]:
        held = origin(request.url)
        self._sign(request, token, self._nonces.get(held, ""))

        response = yield request

        if not token.bound:
            return

        wanted = response.headers.get("DPoP-Nonce", "")

        if not wanted:
            return

        self._nonces[held] = wanted

        if response.status_code != 401 or "use_dpop_nonce" not in response.headers.get("WWW-Authenticate", ""):
            return

        self._sign(request, token, wanted)

        yield request

    def _sign(self, request: httpx.Request, token: Token, nonce: str) -> None:
        if not token.bound:
            request.headers["Authorization"] = f"Bearer {token.access_token}"
            return

        if self.key is None:
            raise ValueError("masks: a DPoP token needs the key it is held to")

        request.headers["Authorization"] = f"{DPOP} {token.access_token}"
        request.headers["DPoP"] = proof(self.key, request.method, str(request.url), token.access_token, nonce)
