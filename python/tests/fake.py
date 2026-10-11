from __future__ import annotations

import base64
import json
import secrets
import time
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import parse_qsl, unquote_plus

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from masks.client import ASSERTION_TYPE
from masks.dpop import PROOF_TYPE
from masks.keys import thumbprint
from masks.models import GRANT_CLIENT_CREDENTIALS, GRANT_DEVICE_CODE, GRANT_REFRESH_TOKEN
from masks.verifier import PROOF_ALGORITHMS, typed

ISSUER = "https://id.example"
AUDIENCE = "https://files.example"


@dataclass
class FakeClient:
    method: str
    secret: str = ""
    jwks: dict[str, Any] = field(default_factory=dict)
    scope: str = ""
    refresh: set[str] = field(default_factory=set)


def respond(status: int, body: Any = None, headers: dict[str, str] | None = None) -> httpx.Response:
    if body is None:
        return httpx.Response(status, headers=headers)

    return httpx.Response(status, json=body, headers=headers)


def oauth_error(status: int, code: str, headers: dict[str, str] | None = None) -> httpx.Response:
    return respond(status, {"error": code, "error_description": f"{code} from the fake"}, headers)


class Fake:
    def __init__(self) -> None:
        self.signing = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.kid = "signing-1"
        self.clients: dict[str, FakeClient] = {}
        self.registrations: dict[str, str] = {}
        self.initial: dict[str, str] = {}
        self.assertions: set[str] = set()
        self.revoked: list[str] = []
        self.pending = 0
        self.slowed = False
        self.nonce = ""
        self.foreign_uri = False
        self.issuer = ISSUER
        self.jwks_fetches = 0
        self.seen: list[httpx.Request] = []

    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self.handle)

    def http(self) -> httpx.Client:
        return httpx.Client(transport=self.transport())

    def async_http(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=self.transport())

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.seen.append(request)
        path = request.url.path
        routes = {
            ("GET", "/.well-known/openid-configuration"): self.discovery,
            ("GET", "/.well-known/jwks.json"): self.keys,
            ("POST", "/token"): self.token,
            ("POST", "/device_authorization"): self.device,
            ("POST", "/revoke"): self.revoke,
            ("POST", "/register"): self.register,
        }

        if (request.method, path) in routes:
            return routes[(request.method, path)](request)

        if path.startswith("/register/"):
            return self.registration(request, path.removeprefix("/register/"))

        return respond(404, {"error": "not_found"})

    def discovery(self, _: httpx.Request) -> httpx.Response:
        return respond(
            200,
            {
                "issuer": self.issuer,
                "token_endpoint": f"{ISSUER}/token",
                "jwks_uri": f"{ISSUER}/.well-known/jwks.json",
                "device_authorization_endpoint": f"{ISSUER}/device_authorization",
                "revocation_endpoint": f"{ISSUER}/revoke",
                "registration_endpoint": f"{ISSUER}/register",
                "tenant": {"uuid": "t-1", "subdomain": "fake", "name": "Fake"},
            },
        )

    def keys(self, _: httpx.Request) -> httpx.Response:
        self.jwks_fetches += 1
        public = json.loads(RSAAlgorithm.to_jwk(self.signing.public_key()))

        return respond(200, {"keys": [{**public, "kid": self.kid, "alg": "RS256", "use": "sig"}]})

    def issue(self, claims: dict[str, Any], typ: str = "at+jwt", kid: str | None = None) -> str:
        return jwt.encode(claims, self.signing, algorithm="RS256", headers={"typ": typ, "kid": kid or self.kid})

    def access_token(self, client_id: str, scope: str, jkt: str) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": ISSUER,
            "sub": client_id,
            "aud": AUDIENCE,
            "exp": now + 3600,
            "iat": now,
            "jti": secrets.token_urlsafe(16),
            "client_id": client_id,
            "scope": scope,
        }

        if jkt:
            claims["cnf"] = {"jkt": jkt}

        return self.issue(claims)

    def add(self, client_id: str, client: FakeClient) -> None:
        self.clients[client_id] = client

    def authenticated(self, request: httpx.Request, form: dict[str, str]) -> tuple[str, FakeClient | None, bool]:
        authorization = request.headers.get("Authorization", "")

        if authorization.startswith("Basic "):
            pair = base64.b64decode(authorization.removeprefix("Basic ")).decode()
            presented_id, _, secret = pair.partition(":")
            client_id, secret = unquote_plus(presented_id), unquote_plus(secret)
            client = self.clients.get(client_id)

            return (
                client_id,
                client,
                client is not None and client.method == "client_secret_basic" and client.secret == secret,
            )

        client_id = form.get("client_id", "")
        client = self.clients.get(client_id)

        if client is None:
            return client_id, None, False

        if client.method == "client_secret_post":
            return client_id, client, form.get("client_secret") == client.secret

        if client.method == "none":
            return client_id, client, True

        if client.method == "private_key_jwt":
            return client_id, client, self.asserted(form, client_id, client)

        return client_id, client, False

    def asserted(self, form: dict[str, str], client_id: str, client: FakeClient) -> bool:
        if form.get("client_assertion_type") != ASSERTION_TYPE:
            return False

        assertion = form.get("client_assertion", "")
        header = jwt.get_unverified_header(assertion)
        keys = [key for key in client.jwks.get("keys", []) if key.get("kid") == header.get("kid")]

        if header.get("alg") != "ES256" or len(keys) != 1:
            return False

        try:
            claims = jwt.decode(
                assertion,
                jwt.PyJWK(keys[0], algorithm="ES256").key,
                algorithms=["ES256"],
                audience=[ISSUER, f"{ISSUER}/token"],
                leeway=0,
                options={"require": ["iss", "sub", "aud", "exp", "jti"]},
            )
        except jwt.PyJWTError:
            return False

        if claims["iss"] != client_id or claims["sub"] != client_id or claims["exp"] > time.time() + 3600:
            return False

        if claims["jti"] in self.assertions:
            return False

        self.assertions.add(claims["jti"])

        return True

    def proof(self, request: httpx.Request) -> tuple[str, bool]:
        presented = request.headers.get("DPoP")

        if not presented:
            return "", True

        header = jwt.get_unverified_header(presented)
        jwk = header.get("jwk")

        if (
            not typed(header, PROOF_TYPE)
            or header.get("alg") not in PROOF_ALGORITHMS
            or not isinstance(jwk, dict)
            or "d" in jwk
        ):
            return "", False

        try:
            claims = jwt.decode(
                presented,
                jwt.PyJWK(jwk, algorithm=header["alg"]).key,
                algorithms=[header["alg"]],
                options={"verify_aud": False, "require": ["jti", "htm", "htu", "iat"]},
            )
        except jwt.PyJWTError:
            return "", False

        if claims["htm"] != "POST" or claims["htu"] != f"{ISSUER}{request.url.path}" or "ath" in claims:
            return "", False

        if self.nonce and claims.get("nonce") != self.nonce:
            return "", False

        return thumbprint(jwk), True

    def form(self, request: httpx.Request) -> dict[str, str]:
        assert request.headers.get("Content-Type") == "application/x-www-form-urlencoded"

        return dict(parse_qsl(request.content.decode(), keep_blank_values=True))

    def token(self, request: httpx.Request) -> httpx.Response:
        form = self.form(request)
        jkt, ok = self.proof(request)

        if not ok:
            if self.nonce:
                return oauth_error(400, "use_dpop_nonce", {"DPoP-Nonce": self.nonce})

            return oauth_error(400, "invalid_dpop_proof")

        client_id, client, ok = self.authenticated(request, form)

        if not ok or client is None:
            return oauth_error(401, "invalid_client")

        grant = form.get("grant_type")

        if grant == GRANT_REFRESH_TOKEN:
            presented = form.get("refresh_token", "")

            if presented not in client.refresh:
                return oauth_error(400, "invalid_grant")

            client.refresh.discard(presented)
        elif grant == GRANT_DEVICE_CODE:
            if self.pending > 0:
                self.pending -= 1

                if not self.slowed:
                    self.slowed = True
                    return oauth_error(400, "slow_down")

                return oauth_error(400, "authorization_pending")
        elif grant != GRANT_CLIENT_CREDENTIALS:
            return oauth_error(400, "unsupported_grant_type")

        scope = form.get("scope") or client.scope
        refresh = secrets.token_urlsafe(16)
        client.refresh.add(refresh)

        return respond(
            200,
            {
                "access_token": self.access_token(client_id, scope, jkt),
                "token_type": "DPoP" if jkt else "Bearer",
                "expires_in": 3600,
                "scope": scope,
                "refresh_token": refresh,
            },
        )

    def device(self, request: httpx.Request) -> httpx.Response:
        form = self.form(request)
        client_id, _, ok = self.authenticated(request, form)

        if not ok or form.get("client_id") != client_id:
            return oauth_error(401, "invalid_client")

        return respond(
            200,
            {
                "device_code": "device-code",
                "user_code": "ABCD EFGH",
                "verification_uri": f"{ISSUER}/device",
                "expires_in": 600,
                "interval": 0,
            },
        )

    def revoke(self, request: httpx.Request) -> httpx.Response:
        form = self.form(request)

        if not self.authenticated(request, form)[2]:
            return oauth_error(401, "invalid_client")

        self.revoked.append(form.get("token", ""))

        return respond(200)

    def register(self, request: httpx.Request) -> httpx.Response:
        presented = request.headers.get("Authorization", "").removeprefix("Bearer ")
        client_id = self.initial.pop(presented, None)

        if client_id is None:
            return oauth_error(401, "invalid_token")

        metadata = json.loads(request.content or b"{}")
        token = secrets.token_urlsafe(16)

        self.add(
            client_id,
            FakeClient(
                method=metadata.get("token_endpoint_auth_method", "client_secret_basic"),
                jwks=metadata.get("jwks") or {},
                scope=metadata.get("scope", ""),
            ),
        )
        self.registrations[client_id] = token

        uri = (
            f"https://elsewhere.example/register/{client_id}" if self.foreign_uri else f"{ISSUER}/register/{client_id}"
        )

        return respond(
            201,
            {**metadata, "client_id": client_id, "registration_access_token": token, "registration_client_uri": uri},
        )

    def registration(self, request: httpx.Request, client_id: str) -> httpx.Response:
        held = self.registrations.get(client_id)
        client = self.clients.get(client_id)

        if held is None or client is None or request.headers.get("Authorization") != f"Bearer {held}":
            return oauth_error(401, "invalid_token")

        if request.method == "DELETE":
            del self.registrations[client_id]
            del self.clients[client_id]

            return respond(204)

        if request.method == "PUT":
            metadata = json.loads(request.content or b"{}")
            client.scope = metadata.get("scope", client.scope)

            return respond(200, {**metadata, "client_id": client_id})

        return respond(
            200, {"client_id": client_id, "token_endpoint_auth_method": client.method, "scope": client.scope}
        )
