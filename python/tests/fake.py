from __future__ import annotations

import base64
import hashlib
import json
import secrets
import time
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import parse_qsl, unquote_plus, urlencode, urlsplit

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from masks.client import ASSERTION_TYPE
from masks.dpop import PROOF_TYPE
from masks.keys import encode, thumbprint
from masks.models import (
    ACCESS_TOKEN_TYPE,
    GRANT_CLIENT_CREDENTIALS,
    GRANT_DEVICE_CODE,
    GRANT_REFRESH_TOKEN,
    GRANT_TOKEN_EXCHANGE,
    UPSTREAM_ACCESS_TOKEN_TYPE,
)
from masks.verifier import PROOF_ALGORITHMS, typed

ISSUER = "https://id.example"
AUDIENCE = "https://files.example"
LOGOUT_EVENT = "http://schemas.openid.net/event/backchannel-logout"

PEOPLE: dict[str, dict[str, Any]] = {
    "ada": {
        "sub": "ada",
        "name": "Ada Lovelace",
        "preferred_username": "ada",
        "email": "ada@example.com",
        "email_verified": True,
        "masks:avatars": {
            "photo": f"{ISSUER}/avatars/ada/photo",
            "identicon": f"{ISSUER}/avatars/ada/identicon",
        },
        "orgs": [
            {"id": "o-1", "key": "acme", "name": "Acme", "role": "owner"},
            {"id": "o-2", "key": "globex", "name": "Globex", "role": "member"},
        ],
        "scopes": {"catalog:read", "catalog:admin"},
    },
    "bob": {
        "sub": "bob",
        "name": "Bob",
        "preferred_username": "bob",
        "email": "bob@example.com",
        "email_verified": False,
        "orgs": [{"id": "o-1", "key": "acme", "name": "Acme", "role": "member"}],
        "scopes": {"catalog:read"},
    },
}


@dataclass
class FakeClient:
    method: str
    secret: str = ""
    jwks: dict[str, Any] = field(default_factory=dict)
    scope: str = ""
    refresh: set[str] = field(default_factory=set)
    namespace: str = ""


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
        self.enrolled: dict[str, str] = {}
        self.unenrolled: list[str] = []
        self.introspected_issuer = ISSUER
        self.exchanged: list[dict[str, str]] = []
        self.codes: dict[str, dict[str, Any]] = {}
        self.grants: dict[str, dict[str, Any]] = {}
        self.handshakes: dict[str, str] = {}
        self.userinfo_calls = 0
        self.photo = b"\x89PNG fake photo"
        self.photo_type = "image/png"
        self.unavailable_tokens = False
        self.keys_down = False
        self.discovery_down = False
        self.discovery_fetches = 0
        self.auth_time: int | None = None
        self.pairs: list[tuple[str, str]] = []

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
            ("POST", "/introspect"): self.introspect,
            ("POST", "/enrollments"): self.enroll,
            ("GET", "/userinfo"): self.userinfo,
            ("GET", "/avatars/ada/photo"): self.avatar,
        }

        if (request.method, path) in routes:
            return routes[(request.method, path)](request)

        if path.startswith("/register/"):
            return self.registration(request, path.removeprefix("/register/"))

        if request.method == "DELETE" and path.startswith("/enrollments/"):
            return self.unenroll(request, request.url.raw_path.decode().removeprefix("/enrollments/"))

        return respond(404, {"error": "not_found"})

    def discovery(self, _: httpx.Request) -> httpx.Response:
        self.discovery_fetches += 1

        if self.discovery_down:
            return respond(503)

        return respond(
            200,
            {
                "issuer": self.issuer,
                "token_endpoint": f"{ISSUER}/token",
                "jwks_uri": f"{ISSUER}/.well-known/jwks.json",
                "device_authorization_endpoint": f"{ISSUER}/device_authorization",
                "revocation_endpoint": f"{ISSUER}/revoke",
                "registration_endpoint": f"{ISSUER}/register",
                "introspection_endpoint": f"{ISSUER}/introspect",
                "enrollment_endpoint": f"{ISSUER}/enrollments",
                "authorization_endpoint": f"{ISSUER}/authorize",
                "userinfo_endpoint": f"{ISSUER}/userinfo",
                "end_session_endpoint": f"{ISSUER}/logout",
                "handshake_endpoint": f"{ISSUER}/handshake",
                "authorization_response_iss_parameter_supported": True,
                "backchannel_logout_supported": True,
                "tenant": {"uuid": "t-1", "subdomain": "fake", "name": "Fake"},
            },
        )

    def keys(self, _: httpx.Request) -> httpx.Response:
        self.jwks_fetches += 1

        if self.keys_down:
            return respond(500)
        public = json.loads(RSAAlgorithm.to_jwk(self.signing.public_key()))

        return respond(200, {"keys": [{**public, "kid": self.kid, "alg": "RS256", "use": "sig"}]})

    def issue(self, claims: dict[str, Any], typ: str = "at+jwt", kid: str | None = None) -> str:
        return jwt.encode(claims, self.signing, algorithm="RS256", headers={"typ": typ, "kid": kid or self.kid})

    def access_token(
        self,
        client_id: str,
        scope: str,
        jkt: str,
        *,
        subject: str = "",
        audience: Any = AUDIENCE,
        lifetime: int = 3600,
        act: dict[str, Any] | None = None,
    ) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": ISSUER,
            "sub": subject or client_id,
            "aud": audience,
            "exp": now + lifetime,
            "iat": now,
            "jti": secrets.token_urlsafe(16),
            "client_id": client_id,
            "scope": scope,
        }

        if jkt:
            claims["cnf"] = {"jkt": jkt}

        if act:
            claims["act"] = act

        return self.issue(claims)

    def presented(self, token: str) -> dict[str, Any] | None:
        try:
            return jwt.decode(
                token,
                self.signing.public_key(),
                algorithms=["RS256"],
                options={"verify_aud": False, "require": ["iss", "exp", "jti"]},
            )
        except jwt.PyJWTError:
            return None

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

        self.pairs = parse_qsl(request.content.decode(), keep_blank_values=True)

        return dict(self.pairs)

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

        if self.unavailable_tokens:
            return oauth_error(503, "temporarily_unavailable")

        if grant == "authorization_code":
            return self.redeem(form, client_id, jkt)

        if grant == GRANT_REFRESH_TOKEN:
            presented = form.get("refresh_token", "")

            if presented not in client.refresh:
                return oauth_error(400, "invalid_grant")

            client.refresh.discard(presented)

            if presented in self.grants:
                return self.signed_in(self.grants.pop(presented), client_id, jkt, client)
        elif grant == GRANT_DEVICE_CODE:
            if self.pending > 0:
                self.pending -= 1

                if not self.slowed:
                    self.slowed = True
                    return oauth_error(400, "slow_down")

                return oauth_error(400, "authorization_pending")
        elif grant == GRANT_TOKEN_EXCHANGE:
            return self.exchange(form, client_id, jkt)
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

    def exchange(self, form: dict[str, str], client_id: str, jkt: str) -> httpx.Response:
        self.exchanged.append(form)

        if form.get("subject_token_type") != ACCESS_TOKEN_TYPE:
            return oauth_error(400, "invalid_request")

        subject = self.presented(form.get("subject_token", ""))

        if subject is None or form.get("subject_token") in self.revoked:
            return oauth_error(400, "invalid_grant")

        if subject.get("cnf", {}).get("jkt") not in (None, jkt):
            return oauth_error(400, "invalid_grant")

        if form.get("requested_token_type") == UPSTREAM_ACCESS_TOKEN_TYPE:
            return respond(
                200,
                {
                    "access_token": "upstream-token",
                    "issued_token_type": UPSTREAM_ACCESS_TOKEN_TYPE,
                    "token_type": "Bearer",
                    "expires_in": 600,
                    "scope": "repo",
                },
            )

        actor = self.presented(form["actor_token"]) if "actor_token" in form else None
        act = {"sub": actor["sub"], "client_id": actor["client_id"]} if actor else {"sub": client_id}
        lifetime = min(int(form.get("requested_lifetime") or 3600), 3600)
        scope = form.get("scope") or subject.get("scope", "")
        resource = [value for name, value in self.pairs if name == "resource"] or subject["aud"]

        return respond(
            200,
            {
                "access_token": self.access_token(
                    client_id, scope, jkt, subject=subject["sub"], audience=resource, lifetime=lifetime, act=act
                ),
                "issued_token_type": ACCESS_TOKEN_TYPE,
                "token_type": "DPoP" if jkt else "Bearer",
                "expires_in": lifetime,
                "scope": scope,
            },
        )

    def introspect(self, request: httpx.Request) -> httpx.Response:
        form = self.form(request)
        client_id, _, ok = self.authenticated(request, form)

        if not ok:
            return oauth_error(401, "invalid_client")

        claims = self.presented(form.get("token", ""))

        if claims is None or form.get("token") in self.revoked:
            return respond(200, {"active": False})

        return respond(
            200,
            {
                "active": True,
                "scope": claims.get("scope", ""),
                "client_id": claims.get("client_id"),
                "token_type": "DPoP" if "cnf" in claims else "Bearer",
                "cnf": claims.get("cnf"),
                "exp": claims["exp"],
                "iat": claims["iat"],
                "sub": claims["sub"],
                "aud": claims["aud"] if isinstance(claims["aud"], list) else [claims["aud"]],
                "iss": self.introspected_issuer,
                "jti": claims["jti"],
                "tenant": {"uuid": "t-1", "subdomain": "fake", "name": "Fake"},
                "asked_by": client_id,
            },
        )

    def enroll(self, request: httpx.Request) -> httpx.Response:
        form = self.form(request)
        client_id, client, ok = self.authenticated(request, form)

        if not ok or client is None:
            return oauth_error(401, "invalid_client")

        scopes = form.get("scope", "").split()

        if not scopes or not client.namespace or any(not scope.startswith(f"{client.namespace}:") for scope in scopes):
            return oauth_error(400, "invalid_request")

        lifetime = int(form.get("expires_in") or 900)

        if not 60 <= lifetime <= 3600:
            return oauth_error(400, "invalid_request")

        token = secrets.token_urlsafe(16)
        machine = f"machine-{len(self.enrolled) + 1}"
        self.initial[token] = machine
        self.enrolled[machine] = client_id

        return respond(201, {"initial_access_token": token, "expires_in": lifetime, "scope": " ".join(scopes)})

    def unenroll(self, request: httpx.Request, machine: str) -> httpx.Response:
        form = self.form(request)
        client_id, _, ok = self.authenticated(request, form)

        if not ok:
            return oauth_error(401, "invalid_client")

        if self.enrolled.get(machine) != client_id:
            return oauth_error(404, "invalid_request")

        self.clients.pop(machine, None)
        self.unenrolled.append(machine)

        return respond(204)

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
        if self.unavailable_tokens:
            return oauth_error(503, "temporarily_unavailable")

        presented = request.headers.get("Authorization", "").removeprefix("Bearer ")
        client_id = self.initial.pop(presented, None)

        if client_id is None:
            return oauth_error(401, "invalid_token")

        metadata = json.loads(request.content or b"{}")
        token = secrets.token_urlsafe(16)
        method = metadata.get("token_endpoint_auth_method", "client_secret_basic")
        secret = secrets.token_urlsafe(16) if method.startswith("client_secret") else ""

        self.add(
            client_id,
            FakeClient(method=method, secret=secret, jwks=metadata.get("jwks") or {}, scope=metadata.get("scope", "")),
        )
        self.registrations[client_id] = token

        if secret:
            metadata["client_secret"] = secret

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

    def authorize(self, url: str, subject: str = "ada", organization: str | None = None) -> str:
        held = urlsplit(url)
        assert f"{held.scheme}://{held.netloc}{held.path}" == f"{ISSUER}/authorize"
        params = dict(parse_qsl(held.query))
        resources = [value for name, value in parse_qsl(held.query) if name == "resource"]
        assert params["response_type"] == "code"
        assert params["code_challenge_method"] == "S256"
        actor = PEOPLE[subject]
        asked = params["scope"].split()
        granted = [
            scope
            for scope in asked
            if ":" not in scope or scope in actor["scopes"] or scope.startswith("masks:delegate:")
        ]
        chosen = organization or params.get("organization")
        org = next((held for held in actor["orgs"] if held["key"] == chosen), None) if "organization" in asked else None
        code = secrets.token_urlsafe(16)
        self.codes[code] = {
            "client_id": params["client_id"],
            "redirect_uri": params["redirect_uri"],
            "challenge": params["code_challenge"],
            "nonce": params.get("nonce"),
            "scope": " ".join(granted),
            "subject": subject,
            "org": org,
            "resource": resources,
            "dpop_jkt": params.get("dpop_jkt"),
            "sid": secrets.token_urlsafe(8),
        }
        query = urlencode({"code": code, "state": params["state"], "iss": ISSUER})

        return f"{params['redirect_uri']}?{query}"

    def redeem(self, form: dict[str, str], client_id: str, jkt: str) -> httpx.Response:
        grant = self.codes.pop(form.get("code", ""), None)

        if grant is None or grant["client_id"] != client_id or grant["redirect_uri"] != form.get("redirect_uri"):
            return oauth_error(400, "invalid_grant")

        if encode(hashlib.sha256(form.get("code_verifier", "").encode()).digest()) != grant["challenge"]:
            return oauth_error(400, "invalid_grant")

        if grant["dpop_jkt"] and grant["dpop_jkt"] != jkt:
            return oauth_error(400, "invalid_dpop_proof")

        return self.signed_in(grant, client_id, jkt, self.clients[client_id], id_token=True)

    def signed_in(
        self, grant: dict[str, Any], client_id: str, jkt: str, client: FakeClient, id_token: bool = False
    ) -> httpx.Response:
        scope = grant["scope"]
        access = self.access_token(
            client_id, scope, jkt, subject=grant["subject"], audience=grant["resource"] or AUDIENCE
        )
        body: dict[str, Any] = {
            "access_token": access,
            "token_type": "DPoP" if jkt else "Bearer",
            "expires_in": 3600,
            "scope": scope,
        }

        if id_token and "openid" in scope.split():
            body["id_token"] = self.id_token(grant, client_id, access)

        if "offline_access" in scope.split():
            refresh = secrets.token_urlsafe(16)
            client.refresh.add(refresh)
            self.grants[refresh] = grant
            body["refresh_token"] = refresh

        delegated = [
            scope.removeprefix("masks:delegate:") for scope in scope.split() if scope.startswith("masks:delegate:")
        ]

        if delegated:
            body["delegations"] = [
                {
                    "connection": "c0ffee00-0000-4000-8000-000000000001",
                    "provider": name,
                    "provider_name": "GitHub",
                    "label": "ada@github",
                    "subject": "1234",
                }
                for name in delegated
            ]

        return respond(200, body)

    def id_token(self, grant: dict[str, Any], client_id: str, access: str) -> str:
        actor = PEOPLE[grant["subject"]]
        now = int(time.time())
        digest = hashlib.sha256(access.encode()).digest()
        claims = {
            "iss": ISSUER,
            "sub": grant["subject"],
            "aud": client_id,
            "exp": now + 900,
            "iat": now,
            "nonce": grant["nonce"],
            "sid": grant["sid"],
            "at_hash": encode(digest[:16]),
            "tenant": {"uuid": "t-1", "subdomain": "fake", "name": "Fake"},
            "name": actor["name"],
            "masks:avatars": actor.get("masks:avatars"),
            "org": grant["org"],
            "auth_time": self.auth_time,
        }

        return self.issue({key: value for key, value in claims.items() if value is not None}, typ="JWT")

    def logout_token(self, client_id: str, subject: str = "", sid: str = "", **changes: Any) -> str:
        now = int(time.time())
        claims = {
            "iss": ISSUER,
            "aud": client_id,
            "iat": now,
            "exp": now + 120,
            "jti": secrets.token_urlsafe(8),
            "events": {LOGOUT_EVENT: {}},
            "sub": subject or None,
            "sid": sid or None,
            **changes,
        }

        return self.issue({key: value for key, value in claims.items() if value is not None}, typ="logout+jwt")

    def userinfo(self, request: httpx.Request) -> httpx.Response:
        self.userinfo_calls += 1
        scheme, _, token = request.headers.get("Authorization", "").partition(" ")
        claims = self.presented(token)

        if claims is None or token in self.revoked:
            return oauth_error(401, "invalid_token")

        bound = claims.get("cnf", {}).get("jkt")

        if bool(bound) != (scheme == "DPoP"):
            return oauth_error(401, "invalid_token")

        if bound:
            presented = request.headers.get("DPoP", "")
            header = jwt.get_unverified_header(presented)
            proof = jwt.decode(presented, jwt.PyJWK(header["jwk"]).key, algorithms=[header["alg"]])

            if thumbprint(header["jwk"]) != bound or proof["htm"] != "GET" or proof["htu"] != f"{ISSUER}/userinfo":
                return oauth_error(401, "invalid_dpop_proof")

        actor = PEOPLE.get(claims["sub"])

        if actor is None:
            return respond(200, {"sub": claims["sub"]})

        return respond(200, {key: value for key, value in actor.items() if key != "scopes"})

    def avatar(self, request: httpx.Request) -> httpx.Response:
        if self.presented(request.headers.get("Authorization", "").partition(" ")[2]) is None:
            return respond(401)

        return httpx.Response(200, content=self.photo, headers={"Content-Type": self.photo_type})

    def handshake(self, url: str, client_id: str = "app") -> str:
        held = urlsplit(url)
        assert f"{held.scheme}://{held.netloc}{held.path}" == f"{ISSUER}/handshake"
        params = dict(parse_qsl(held.query))
        redirect_uris = [value for name, value in parse_qsl(held.query) if name == "redirect_uris"]
        assert redirect_uris and params["resource"] and params["scope"]
        token = secrets.token_urlsafe(16)
        self.initial[token] = client_id
        self.handshakes[client_id] = params["scope"]
        query = urlencode({"initial_access_token": token, "iss": ISSUER, "state": params["state"]})

        return f"{params['return_to']}?{query}"
