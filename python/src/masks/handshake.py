from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode, urlsplit

import httpx

from .client import _Flows, words
from .errors import Refused
from .flows import Flow, arun, check, default_async_http, default_http, origin, run
from .keys import random_id
from .keyset import same
from .models import CLIENT_SECRET_BASIC, GRANT_REFRESH_TOKEN, ClientMetadata, Issuer, Registration
from .oidc import DEFAULT_SCOPE, flattened

HANDSHAKE_PATH = "/handshake"
GRANT_TYPES = ("authorization_code", GRANT_REFRESH_TOKEN)


@dataclass(frozen=True)
class HandshakeRequest:
    url: str
    state: str


def absolute(value: str, named: str, allow_plain_http: bool) -> str:
    held = urlsplit(value)

    if not held.scheme or not held.hostname or held.fragment:
        raise ValueError(f"masks: {named} must be an absolute URL without a fragment: {value!r}")

    check(value, allow_plain_http)

    return value


class Handshake:
    def __init__(
        self,
        issuer: Issuer,
        *,
        name: str,
        resource: str,
        redirect_uris: Sequence[str],
        return_to: str,
        scope: Sequence[str] = DEFAULT_SCOPE,
        backchannel_logout_uri: str = "",
        post_logout_redirect_uri: str = "",
    ) -> None:
        plain = issuer.allow_plain_http
        self.issuer = issuer
        self.name = name.strip()
        self.resource = absolute(resource, "resource", plain)
        self.redirect_uris = [absolute(uri, "each redirect_uri", plain) for uri in redirect_uris]
        self.return_to = absolute(return_to, "return_to", plain)
        self.scope = words(scope)
        self.backchannel_logout_uri = (
            absolute(backchannel_logout_uri, "backchannel_logout_uri", plain)
            if backchannel_logout_uri and issuer.metadata.backchannel_logout_supported
            else ""
        )
        self.post_logout_redirect_uri = (
            absolute(post_logout_redirect_uri, "post_logout_redirect_uri", plain) if post_logout_redirect_uri else ""
        )

        if not self.redirect_uris:
            raise ValueError("masks: a handshake needs at least one redirect_uri")

        if not self.scope:
            raise ValueError("masks: a handshake needs at least one scope")

        home = origin(self.resource)
        elsewhere = [
            uri
            for uri in [self.return_to, *self.redirect_uris, self.backchannel_logout_uri, self.post_logout_redirect_uri]
            if uri and origin(uri) != home
        ]

        if elsewhere:
            raise ValueError(f"masks: everything in a handshake shares the origin {home}: {', '.join(elsewhere)}")

    @property
    def endpoint(self) -> str:
        return self.issuer.metadata.handshake_endpoint or f"{self.issuer.url}{HANDSHAKE_PATH}"

    def start(self, state: str | None = None) -> HandshakeRequest:
        state = state or random_id()
        pairs = [
            ("client_name", self.name),
            ("resource", self.resource),
            ("scope", " ".join(self.scope)),
            ("return_to", self.return_to),
            ("state", state),
        ]

        if self.backchannel_logout_uri:
            pairs.append(("backchannel_logout_uri", self.backchannel_logout_uri))

        if self.post_logout_redirect_uri:
            pairs.append(("post_logout_redirect_uri", self.post_logout_redirect_uri))

        pairs.extend(("redirect_uris", uri) for uri in self.redirect_uris)

        return HandshakeRequest(url=f"{self.endpoint}?{urlencode(pairs)}", state=state)

    def metadata(self) -> ClientMetadata:
        return ClientMetadata(
            client_name=self.name or None,
            redirect_uris=self.redirect_uris,
            grant_types=list(GRANT_TYPES),
            scope=" ".join(self.scope),
            token_endpoint_auth_method=CLIENT_SECRET_BASIC,
            backchannel_logout_uri=self.backchannel_logout_uri or None,
            post_logout_redirect_uris=[self.post_logout_redirect_uri] if self.post_logout_redirect_uri else None,
        )

    def _complete(self, params: Any, state: str) -> Flow[Registration]:
        held = flattened(params)

        if held.get("error"):
            raise Refused(held["error"], held.get("error_description", ""))

        if not state or not same(held.get("state"), state):
            raise Refused.of("state_mismatch")

        named = held.get("iss", "")

        if named and named.rstrip("/") != self.issuer.url:
            raise Refused("invalid_issuer", f"that came back from {named}, not {self.issuer.url}")

        token = held.get("initial_access_token", "")

        if not token:
            raise Refused("invalid_request", "the handshake came back without a token")

        registration = yield from _Flows._registered(self.issuer, self.metadata(), token)

        if not registration.client_secret:
            raise Refused("invalid_client_metadata", "the handshake registered a client without a secret")

        return registration

    def complete(self, params: Any, state: str, *, http: httpx.Client | None = None) -> Registration:
        if http is None:
            with default_http() as held:
                return run(self._complete(params, state), held)

        return run(self._complete(params, state), http)

    async def acomplete(self, params: Any, state: str, *, http: httpx.AsyncClient | None = None) -> Registration:
        if http is None:
            async with default_async_http() as held:
                return await arun(self._complete(params, state), held)

        return await arun(self._complete(params, state), http)
