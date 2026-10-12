from __future__ import annotations

import hmac
import inspect
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx
import jwt

from .dpop import DPOP, PROOF_TYPE, tidied, token_hash
from .errors import InvalidToken
from .flows import Flow, arun, default_async_http, default_http, get, required, run
from .keys import PRIVATE_MEMBERS, thumbprint
from .models import Issuer, Tenant
from .replay import AsyncReplayStore, MemoryReplayStore, ReplayStore

ACCESS_TOKEN_TYPE = "at+jwt"
TOKEN_ALGORITHMS = ("RS256", "ES256")
PROOF_ALGORITHMS = ("ES256", "ES384", "ES512", "PS256", "PS384", "PS512", "RS256")
PROOF_WINDOW = 60
LEEWAY = 30
KEYS_LIFETIME = 300
KEYS_PATIENCE = 30
REPLAY_MEMORY = PROOF_WINDOW + 2 * LEEWAY

Headers = Mapping[str, str] | Sequence[tuple[str, str]] | httpx.Headers


@dataclass(frozen=True)
class Claims:
    issuer: str
    subject: str
    audience: list[str]
    expiry: int
    issued_at: int | None
    id: str
    client_id: str
    scope: str
    tenant: Tenant | None
    act: dict[str, Any] | None
    thumbprint: str | None
    raw: dict[str, Any] = field(repr=False)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Claims:
        audience = data.get("aud")
        found = data.get("cnf")
        confirmation: dict[str, Any] = found if isinstance(found, dict) else {}
        tenant = data.get("tenant")

        return cls(
            issuer=str(data.get("iss") or ""),
            subject=str(data.get("sub") or ""),
            audience=[str(item) for item in audience] if isinstance(audience, list) else [str(audience or "")],
            expiry=int(data["exp"]),
            issued_at=int(data["iat"]) if isinstance(data.get("iat"), (int, float)) else None,
            id=str(data.get("jti") or ""),
            client_id=str(data.get("client_id") or ""),
            scope=str(data.get("scope") or ""),
            tenant=Tenant(**{key: str(tenant.get(key) or "") for key in ("uuid", "subdomain", "name")})
            if isinstance(tenant, dict)
            else None,
            act=data.get("act") if isinstance(data.get("act"), dict) else None,
            thumbprint=str(confirmation.get("jkt")) if confirmation.get("jkt") else None,
            raw=data,
        )

    @property
    def scopes(self) -> list[str]:
        return self.scope.split()

    def has_scope(self, scope: str) -> bool:
        return scope in self.scopes

    @property
    def bound(self) -> bool:
        return bool(self.thumbprint)


def typed(header: dict[str, Any], want: str) -> bool:
    held = str(header.get("typ") or "").lower()

    return held.removeprefix("application/") == want


def remembered(answer: object) -> None:
    if inspect.iscoroutine(answer):
        answer.close()

    if answer is False:
        raise InvalidToken("masks: that proof has already been used")

    if answer is not True:
        raise InvalidToken("masks: the replay store answered with something other than true or false")


def unremembered() -> InvalidToken:
    return InvalidToken("masks: the replay store could not say whether that proof is new")


def unverified_header(token: str) -> dict[str, Any]:
    try:
        return jwt.get_unverified_header(token)
    except jwt.PyJWTError as error:
        raise InvalidToken(f"masks: that is not a signed JWT: {error}") from error


class _Verifying:
    def __init__(self, issuer: Issuer, audience: str | Sequence[str], *, public_url: str | None = None) -> None:
        self.issuer = issuer
        self.audience = [audience] if isinstance(audience, str) else list(audience)
        self.public_url = public_url.rstrip("/") if public_url else None
        self._keys: list[dict[str, Any]] = []
        self._keys_at = 0.0

    def _key(self, kid: str) -> Flow[dict[str, Any]]:
        age = time.monotonic() - self._keys_at
        found = self._find(kid)

        if found is not None and age < KEYS_LIFETIME:
            return found

        if age >= KEYS_PATIENCE or not self._keys_at:
            body = required((yield get(self.issuer.metadata.jwks_uri)))
            keys = body.get("keys")
            self._keys = [key for key in keys if isinstance(key, dict)] if isinstance(keys, list) else []
            self._keys_at = time.monotonic()
            found = self._find(kid)

        if found is None:
            raise InvalidToken(f"masks: {self.issuer.url} publishes no key {kid!r}")

        return found

    def _find(self, kid: str) -> dict[str, Any] | None:
        return next((key for key in self._keys if key.get("kid") == kid and key.get("use", "sig") == "sig"), None)

    def _verify(self, token: str) -> Flow[Claims]:
        header = unverified_header(token)
        algorithm = header.get("alg")

        if algorithm not in TOKEN_ALGORITHMS:
            raise InvalidToken(f"masks: {algorithm!r} is not an algorithm a masks token is signed with")

        if not typed(header, ACCESS_TOKEN_TYPE):
            raise InvalidToken(f"masks: that token is not typed {ACCESS_TOKEN_TYPE}")

        jwk = yield from self._key(str(header.get("kid") or ""))

        try:
            key = jwt.PyJWK(jwk, algorithm=algorithm).key
            claims = jwt.decode(
                token,
                key,
                algorithms=[algorithm],
                audience=self.audience,
                issuer=self.issuer.url,
                leeway=LEEWAY,
                options={"require": ["iss", "exp", "jti", "aud"]},
            )
        except jwt.PyJWTError as error:
            raise InvalidToken(f"masks: {error}") from error

        return Claims.from_dict(claims)

    def _authenticate(self, method: str, url: object, headers: Headers) -> Flow[tuple[Claims, str]]:
        held = httpx.Headers(headers)
        scheme, _, token = held.get("Authorization", "").partition(" ")

        if not token:
            raise InvalidToken("masks: the request carries no token")

        claims = yield from self._verify(token)

        if scheme.lower() == "bearer" and not claims.bound:
            return claims, ""

        if scheme.lower() == DPOP.lower() and claims.bound:
            seen = self._proven(method, self._target(str(url)), token, str(claims.thumbprint), held.get_list(DPOP))
            return claims, seen

        if scheme.lower() == "bearer":
            raise InvalidToken("masks: that token is held to a key and is presented with DPoP")

        raise InvalidToken("masks: that token is presented as a Bearer token")

    def _target(self, url: str) -> str:
        if not self.public_url:
            return url

        held = urlsplit(url)

        return self.public_url + urlunsplit(("", "", held.path, held.query, ""))

    def _proven(self, method: str, url: str, token: str, bound_to: str, presented: list[str]) -> str:
        if len(presented) != 1 or "," in presented[0]:
            raise InvalidToken("masks: exactly one DPoP proof is required")

        header = unverified_header(presented[0])
        algorithm = header.get("alg")

        if not typed(header, PROOF_TYPE):
            raise InvalidToken(f"masks: a proof is typed {PROOF_TYPE}")

        if algorithm not in PROOF_ALGORITHMS:
            raise InvalidToken(f"masks: {algorithm!r} is not an algorithm a proof may use")

        jwk = header.get("jwk")

        if not isinstance(jwk, dict) or jwk.get("kty") not in ("EC", "RSA") or PRIVATE_MEMBERS & set(jwk):
            raise InvalidToken("masks: a proof carries the public key that signed it")

        try:
            key = jwt.PyJWK(jwk, algorithm=algorithm).key
            claims = jwt.decode(
                presented[0],
                key,
                algorithms=[algorithm],
                options={"verify_aud": False, "verify_exp": False, "require": ["jti", "htm", "htu", "iat"]},
            )
        except jwt.PyJWTError as error:
            raise InvalidToken("masks: that proof was not signed by the key it carries") from error

        try:
            held = thumbprint(jwk)
        except ValueError as error:
            raise InvalidToken(f"masks: {error}") from error

        if not hmac.compare_digest(held, bound_to):
            raise InvalidToken("masks: that proof was signed by another key than the token is held to")

        if str(claims["htm"]).upper() != method.upper():
            raise InvalidToken("masks: that proof was made for another method")

        if tidied(str(claims["htu"])) != tidied(url):
            raise InvalidToken("masks: that proof was made for another URL")

        made = claims["iat"]

        if (
            not isinstance(made, (int, float))
            or made < time.time() - PROOF_WINDOW - LEEWAY
            or made > time.time() + LEEWAY
        ):
            raise InvalidToken("masks: that proof was not made just now")

        if not hmac.compare_digest(str(claims.get("ath") or ""), token_hash(token)):
            raise InvalidToken("masks: that proof was made for another token")

        jti = claims["jti"]

        if not isinstance(jti, str) or not jti:
            raise InvalidToken("masks: a proof carries a jti")

        return f"{bound_to}:{jti}"


class Verifier(_Verifying):
    def __init__(
        self,
        issuer: Issuer,
        audience: str | Sequence[str],
        *,
        public_url: str | None = None,
        http: httpx.Client | None = None,
        replay: ReplayStore | None = None,
    ) -> None:
        super().__init__(issuer, audience, public_url=public_url)
        self.http = http or default_http()
        self.replay: ReplayStore = replay if replay is not None else MemoryReplayStore()

    def verify(self, token: str) -> Claims:
        return run(self._verify(token), self.http)

    def authenticate(self, method: str, url: object, headers: Headers) -> Claims:
        claims, seen = run(self._authenticate(method, url, headers), self.http)

        if seen:
            try:
                answer: object = self.replay.first(seen, REPLAY_MEMORY)
            except Exception as error:
                raise unremembered() from error

            remembered(answer)

        return claims


class AsyncVerifier(_Verifying):
    def __init__(
        self,
        issuer: Issuer,
        audience: str | Sequence[str],
        *,
        public_url: str | None = None,
        http: httpx.AsyncClient | None = None,
        replay: ReplayStore | AsyncReplayStore | None = None,
    ) -> None:
        super().__init__(issuer, audience, public_url=public_url)
        self.http = http or default_async_http()
        self.replay: ReplayStore | AsyncReplayStore = replay if replay is not None else MemoryReplayStore()

    async def verify(self, token: str) -> Claims:
        return await arun(self._verify(token), self.http)

    async def authenticate(self, method: str, url: object, headers: Headers) -> Claims:
        claims, seen = await arun(self._authenticate(method, url, headers), self.http)

        if seen:
            try:
                answer: object = self.replay.first(seen, REPLAY_MEMORY)

                if inspect.isawaitable(answer):
                    answer = await answer
            except Exception as error:
                raise unremembered() from error

            remembered(answer)

        return claims
