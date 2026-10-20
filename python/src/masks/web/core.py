from __future__ import annotations

import hashlib
import html
import json
import re
import secrets
import threading
import time
from collections.abc import Callable, Generator, Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any, TypeVar, cast
from urllib.parse import urlencode, urlsplit

import anyio
import httpx
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from ..client import AsyncClient, Client, _Flows, delegation_failure
from ..dpop import DPOP
from ..errors import DelegationRefused, Error, Forbidden, InvalidToken, MasksError, Unavailable
from ..flows import (
    Flow,
    afetch,
    arun,
    check,
    default_async_http,
    default_http,
    discovery,
    fetch,
    origin,
    run,
)
from ..handshake import Handshake
from ..keys import random_id
from ..keyset import Retry, same
from ..models import Issuer, Registration, Token
from ..oidc import AVATARS_CLAIM, AuthorizationRequest, HeldConnection, Logout, organization_key
from ..verifier import PROOF_ALGORITHMS, AsyncVerifier, Claims, Verifier
from .actor import Actor, Privilege, nobody, scoped
from .config import Config, resolve
from .credentials import Credentials
from .sessions import COOKIE_PIECE, COOKIE_PIECES, Session, b64, settled, unb64
from .stores import AsyncReplays, AsyncStore, Replays, Store, asynchronous, keyed

T = TypeVar("T")

Step = Generator[Any, Any, T]

RENEWED = "renewed"
REFUSED = "refused"
UNREGISTERED = "unregistered"
UNREACHABLE = "unreachable"
RENEWAL_MEMORY = 60
RENEWAL_CLAIM = 30
RENEWAL_WAIT = 0.05
RENEWAL_WAITS = 200
RENEWAL_STRIPES = 64
LOGOUT_MEMORY = 600
LOGOUT_LEEWAY = 120

HELD = "masks"
REQUESTS = "masks_requests"
DELEGATIONS = "masks_delegations"
HANDSHAKES = "masks_handshakes"
FAREWELLS = "masks_farewells"
STEPPED_UP = "masks_stepped_up"
RETURN_TO = "masks_return_to"
RESTARTED = "masks_restarted_at"
CARRIED = (REQUESTS, HANDSHAKES, STEPPED_UP)

PENDING_LIFETIME = 3600
PENDING_LIMIT = 5
STEP_UP_WITHIN = 300
RESTART_WITHIN = 60
ISSUER_LIFETIME = 3600
AVATAR_SIZES = (32, 64, 128, 256, 512)
METADATA_PATH = "/.well-known/oauth-protected-resource"
FORM_LIMIT = 64 * 1024

IDENTITY = (
    "sub",
    "sid",
    "name",
    "preferred_username",
    "email",
    "email_verified",
    "tenant",
    "picture",
    AVATARS_CLAIM,
    "org",
    "orgs",
)

UNSAFE_PATH = re.compile(r"[\x00-\x20\x7f\\]")


@dataclass
class Incoming:
    method: str
    url: str
    headers: httpx.Headers
    query: dict[str, str] = field(default_factory=dict)
    form: dict[str, str] = field(default_factory=dict)
    native: Any = None

    @property
    def origin(self) -> str:
        return origin(self.url)

    @property
    def full_path(self) -> str:
        held = urlsplit(self.url)

        return held.path + (f"?{held.query}" if held.query else "")

    @property
    def wants_json(self) -> bool:
        accept = self.headers.get("Accept", "")

        if self.headers.get("X-Requested-With", "").lower() == "xmlhttprequest":
            return True

        if "application/json" in self.headers.get("Content-Type", "") or "application/json" in accept:
            return True

        return bool(accept) and "text/html" not in accept and "*/*" not in accept

    @property
    def authorization(self) -> str:
        return str(self.headers.get("Authorization", ""))


@dataclass
class Answer:
    status: int
    body: bytes = b""
    content_type: str = ""
    headers: list[tuple[str, str]] = field(default_factory=list)

    @classmethod
    def redirect(cls, url: str) -> Answer:
        return cls(303, headers=[("Location", url), ("Cache-Control", "no-store")])

    @classmethod
    def json(cls, status: int, data: Any, headers: Sequence[tuple[str, str]] = ()) -> Answer:
        return cls(
            status,
            json.dumps(data).encode(),
            "application/json",
            [("Cache-Control", "no-store"), *headers],
        )

    @classmethod
    def page(
        cls, status: int, title: str, said: str, extra: str = "", form_targets: Sequence[str] | None = ()
    ) -> Answer:
        body = (
            "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'>"
            f"<title>{html.escape(title)}</title><main><h1>{html.escape(title)}</h1>"
            f"<p>{html.escape(said)}</p>{extra}</main>"
        )

        return cls(
            status,
            body.encode(),
            "text/html; charset=utf-8",
            [
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
                ("X-Frame-Options", "DENY"),
                (
                    "Content-Security-Policy",
                    "default-src 'none'; style-src 'unsafe-inline'; "
                    + ("" if form_targets is None else "form-action " + " ".join(["'self'", *form_targets]) + "; ")
                    + "frame-ancestors 'none'",
                ),
            ],
        )

    def header(self, name: str) -> str:
        return next((value for held, value in self.headers if held.lower() == name.lower()), "")


@dataclass(frozen=True)
class Sealed:
    name: str
    value: str
    max_age: int
    secure: bool

    @property
    def header(self) -> str:
        secure = "; Secure" if self.secure else ""

        return f"{self.name}={self.value}; Path=/; Max-Age={self.max_age}; HttpOnly{secure}; SameSite=Lax"


@dataclass(frozen=True)
class Renewal:
    request: Incoming
    refresh_token: str = field(repr=False)
    identity: dict[str, Any]


@dataclass(frozen=True)
class Ending:
    issuer: str
    subject: str
    sid: str


@dataclass(frozen=True)
class Stored:
    operation: str
    key: str
    value: str = ""
    expires_in: int = 0


@dataclass(frozen=True)
class Pause:
    seconds: float


@dataclass(frozen=True)
class Renewed:
    outcome: str
    token: Token | None = None
    identity: dict[str, Any] = field(default_factory=dict)


class Refusal(MasksError):
    def __init__(self, answer: Answer) -> None:
        super().__init__(f"masks: refused with {answer.status}")
        self.answer = answer


def local_path(value: object) -> str | None:
    path = str(value or "")

    if not path.startswith("/") or path.startswith("//") or UNSAFE_PATH.search(path):
        return None

    held = urlsplit(path)

    if held.scheme or held.netloc or not held.path.startswith("/") or held.path.startswith("//"):
        return None

    return held.path + (f"?{held.query}" if held.query else "")


def unshared(cache_control: str) -> str:
    directives = {part.strip().split("=")[0].lower() for part in cache_control.split(",")}

    return cache_control if directives & {"private", "no-store"} else "no-store"


def cookies_in(header: str) -> dict[str, str]:
    held: dict[str, str] = {}

    for part in header.split(";"):
        key, found, value = part.strip().partition("=")

        if found and key not in held:
            held[key] = value.strip().strip('"')

    return held


def piece_name(name: str, index: int) -> str:
    return f"{name}-{index}" if index else name


def referring(request: Incoming) -> str:
    held = urlsplit(request.headers.get("Referer", ""))

    return local_path(held.path + (f"?{held.query}" if held.query else "")) or ""


def quoted(value: str) -> str:
    return re.sub(r"[\x00-\x1f\x7f]", " ", value.replace("\\", " ").replace('"', " ")).strip()


class Tracker:
    def __init__(self, session: Session, key: str) -> None:
        self.session = session
        self.key = key

    def _live(self) -> dict[str, dict[str, Any]]:
        found = self.session.get(self.key)
        now = time.time()
        held = (
            {
                key: value
                for key, value in found.items()
                if isinstance(value, dict)
                and isinstance(value.get("expires_at"), (int, float))
                and value["expires_at"] > now
            }
            if isinstance(found, dict)
            else {}
        )

        return dict(list(held.items())[-PENDING_LIMIT:])

    def open(self, **data: Any) -> str:
        return self.keep(random_id(), **data)

    def keep(self, key: str, **data: Any) -> str:
        held = self._live()
        held[key] = {
            "data": {name: value for name, value in data.items() if value is not None},
            "expires_at": time.time() + PENDING_LIFETIME,
        }
        self.session[self.key] = dict(list(held.items())[-PENDING_LIMIT:])

        return key

    def amend(self, key: str, **data: Any) -> None:
        held = self._live()

        if key in held:
            held[key]["data"].update(data)
            self.session[self.key] = held

    def claim(self, key: str) -> dict[str, Any] | None:
        held = self._live()
        found = next((value for name, value in held.items() if same(key, name)), None) if key else None

        if found is None:
            if self.session.get(self.key) != held:
                self.session[self.key] = held

            return None

        self.session[self.key] = {name: value for name, value in held.items() if value is not found}

        return dict(found["data"])


class Masks:
    def __init__(self, config: Config) -> None:
        self.config = config
        self._http = config.http
        self._async_http = config.async_http
        self._issuers: dict[str, tuple[Issuer | None, float, Retry]] = {}
        self._verifiers: dict[tuple[str, str], Verifier] = {}
        self._async_verifiers: dict[tuple[str, str], AsyncVerifier] = {}
        self._lock = threading.Lock()
        self._renew_locks = [threading.Lock() for _ in range(RENEWAL_STRIPES)]
        self._async_renew_locks: dict[int, anyio.Lock] = {}

    @property
    def http(self) -> httpx.Client:
        if self._http is None:
            self._http = default_http()

        return self._http

    @property
    def async_http(self) -> httpx.AsyncClient:
        if self._async_http is None:
            self._async_http = default_async_http()

        return self._async_http

    def path(self, name: str = "") -> str:
        return f"{self.config.prefix}{name}" or "/"

    def _pieces(self, header: str) -> tuple[str | None, tuple[str, ...]]:
        held = cookies_in(header)
        names = []

        for index in range(COOKIE_PIECES):
            named = piece_name(self.cookie_name, index)

            if named not in held:
                break

            names.append(named)

        return "".join(held[name] for name in names) or None, tuple(names)

    def load(self, header: str) -> Session:
        value, names = self._pieces(header)
        session = self.config.backend.load(value)
        session.cookie_names = names

        return session

    async def aload(self, header: str) -> Session:
        value, names = self._pieces(header)
        session = await self.config.backend.aload(value)
        session.cookie_names = names

        return session

    def seal(self, session: Session, secure_request: bool) -> list[Sealed]:
        if not session.dirty:
            return []

        return self._sealed(session, self.config.backend.save(session, self._tags(session)), secure_request)

    async def aseal(self, session: Session, secure_request: bool) -> list[Sealed]:
        if not session.dirty:
            return []

        return self._sealed(session, await self.config.backend.asave(session, self._tags(session)), secure_request)

    def _tags(self, session: Session) -> dict[str, str]:
        held = self._held(session)
        identity = held.get("identity") or {}
        tags = {name: str(identity[name]) for name in ("sub", "sid") if identity.get(name)}

        return {"iss": str(held["issuer"]), **tags} if tags and held.get("issuer") else tags

    def _sealed(self, session: Session, value: str | None, secure_request: bool) -> list[Sealed]:
        secure = self.config.cookie_secure or secure_request
        remaining = max(int(session.issued_at + self.config.backend.lifetime - time.time()), 1)
        pieces = [(value or "")[start : start + COOKIE_PIECE] for start in range(0, len(value or ""), COOKIE_PIECE)]

        if len(pieces) > COOKIE_PIECES:
            raise ValueError("masks: this session no longer fits in cookies; keep sessions on the server instead")

        sent = [
            Sealed(piece_name(self.cookie_name, index), piece, remaining, secure) for index, piece in enumerate(pieces)
        ]
        written = {held.name for held in sent}
        sent += [Sealed(name, "", 0, secure) for name in session.cookie_names if name not in written]
        session.modified = False
        session.renewed = False
        session.cookie_names = tuple(held.name for held in sent if held.value)

        return sent

    @property
    def cookie_name(self) -> str:
        named = self.config.backend.name

        return named if self.config.cookie_secure else named.removeprefix("__Host-").removeprefix("__Secure-")

    def cookies(self, session: Session, secure_request: bool) -> list[str]:
        return [held.header for held in self.seal(session, secure_request)]

    async def acookies(self, session: Session, secure_request: bool) -> list[str]:
        return [held.header for held in await self.aseal(session, secure_request)]

    def issuer_url(self, request: Incoming) -> str:
        found = str(resolve(self.config.issuer, request.native) or "").rstrip("/")

        if not found:
            raise ValueError("masks: no issuer is configured")

        return found

    def credentials(self, request: Incoming) -> Credentials:
        assert self.config.credentials is not None

        return resolve(self.config.credentials, request.native)

    def held_credentials(self, request: Incoming) -> dict[str, str]:
        held = self.credentials(request).read()
        named = held.get("issuer", "").rstrip("/")

        if held.get("client_id") and named != self.issuer_url(request) and (named or callable(self.config.issuer)):
            raise Refusal(
                self._refuse(request, "server_error", "the app's credentials were issued by another issuer", 500)
            )

        return held

    def configured(self, request: Incoming) -> bool:
        return bool(self.held_credentials(request).get("client_id"))

    def resource(self, request: Incoming) -> str:
        return str(resolve(self.config.resource, request.native) or "")

    def base(self, request: Incoming) -> str:
        named = str(resolve(self.config.base_url, request.native) or "").rstrip("/")
        resource = self.resource(request)

        return named or (origin(resource) if resource else request.origin)

    def delegation_uri(self, request: Incoming) -> str:
        named = str(resolve(self.config.delegation_redirect_uri, request.native) or "")

        return f"{self.base(request)}{named}" if named.startswith("/") else named

    def callback_uri(self, request: Incoming) -> str:
        return f"{self.base(request)}{self.path('/callback')}"

    def account_url(self, request: Incoming) -> str:
        return f"{self.issuer_url(request)}/"

    def discover(self, request: Incoming) -> Flow[Issuer]:
        named = self.issuer_url(request)
        now = time.monotonic()

        with self._lock:
            good, at, retry = self._issuers.setdefault(named, (None, 0.0, Retry()))

        if good is not None and (now - at < ISSUER_LIFETIME or retry.waiting(now)):
            return good

        if retry.waiting(now) and retry.failure is not None:
            raise retry.failure

        try:
            found = yield from discovery(named, self.config.allow_plain_http)
        except (Error, httpx.HTTPError) as error:
            with self._lock:
                retry.failed(now, error)

            if good is None:
                raise

            return good

        with self._lock:
            retry.succeeded()
            self._issuers[named] = (found, now, retry)

        return found

    def flows(self, request: Incoming, issuer: Issuer) -> _Flows:
        held = self.held_credentials(request)

        if not held.get("client_id"):
            raise Refusal(self._handshake_required(request))

        return _Flows(issuer, held["client_id"], secret=held.get("client_secret") or None)

    def client(self, request: Incoming, issuer: Issuer) -> Client:
        flows = self.flows(request, issuer)

        return Client(issuer, flows.client_id, secret=flows.secret, http=self.http)

    def async_client(self, request: Incoming, issuer: Issuer) -> AsyncClient:
        flows = self.flows(request, issuer)

        return AsyncClient(issuer, flows.client_id, secret=flows.secret, http=self.async_http)

    def login_url(self, return_to: str = "", organization: str = "", privilege: Sequence[str] = ()) -> str:
        query = {
            "return_to": local_path(return_to),
            "organization": organization_key(organization),
            "privilege": " ".join(privilege) or None,
        }
        held = {key: value for key, value in query.items() if value}

        return f"{self.path()}?{urlencode(held)}" if held else self.path()

    def _held(self, session: Session) -> dict[str, Any]:
        found = session.get(HELD)

        return found if isinstance(found, dict) else {}

    def _token(self, request: Incoming, session: Session) -> Token | None:
        held = self._held(session)
        found = held.get("token")

        if not isinstance(found, dict) or not found.get("access_token"):
            return None

        if held.get("issuer") != self.issuer_url(request):
            self.forget(session)
            return None

        return Token.from_dict(found)

    def _store(
        self, request: Incoming, session: Session, token: Token, identity: Mapping[str, Any] | None = None
    ) -> None:
        held = {key: value for key, value in token.to_dict().items() if key != "id_token"}
        kept = identity if identity is not None else self._held(session).get("identity") or {}
        session[HELD] = {
            "issuer": self.issuer_url(request),
            "token": held,
            "identity": {key: kept[key] for key in IDENTITY if key in kept},
        }

    def forget(self, session: Session) -> None:
        if HELD in session:
            del session[HELD]

    def _actor(self, request: Incoming, session: Session, token: Token | None, signed_in: bool) -> Actor:
        if token is None:
            return nobody(self.config.known)

        identity = self._held(session).get("identity") or {}

        return Actor(
            signed_in=signed_in,
            claims=dict(identity),
            scopes=tuple(token.scopes),
            access_token=token.access_token,
            expires_at=token.expires_at,
            account_url=self.account_url(request),
            known=self.config.known,
            avatar_url=self.path("/avatar"),
        )

    def actor(self, request: Incoming, session: Session) -> Step[Actor]:
        token = self._token(request, session)
        identity = dict(self._held(session).get("identity") or {})

        if token is None:
            return nobody(self.config.known)

        departed = yield from self._departed(
            self.issuer_url(request), str(identity.get("sub") or ""), str(identity.get("sid") or ""), session.issued_at
        )

        if departed:
            self.forget(session)
            return nobody(self.config.known)

        if token.valid():
            return self._actor(request, session, token, True)

        if not token.refresh_token or not self.configured(request):
            return self._actor(request, session, token, False)

        renewed = yield Renewal(request, token.refresh_token, identity)

        if renewed.outcome == RENEWED and renewed.token is not None:
            self._store(request, session, renewed.token, renewed.identity)
            return self._actor(request, session, renewed.token, True)

        if renewed.outcome == UNREGISTERED:
            self._disconnect(request, session)
        elif renewed.outcome == REFUSED:
            self.forget(session)

        held = self._token(request, session)

        return self._actor(request, session, held, False) if held else nobody(self.config.known)

    def _renewing(self, renewal: Renewal) -> Flow[Renewed]:
        request = renewal.request

        try:
            issuer = yield from self.discover(request)
            flows = self.flows(request, issuer)
            resource = self.resource(request)
            refreshed = yield from flows._refresh(renewal.refresh_token, (), [resource] if resource else [])
        except Error as error:
            if error.code == "invalid_client":
                return Renewed(UNREGISTERED)

            return Renewed(UNREACHABLE if outage(error) or error.status == 429 else REFUSED)
        except (httpx.HTTPError, Unavailable, Refusal):
            return Renewed(UNREACHABLE)

        if not refreshed.refresh_token:
            refreshed.refresh_token = renewal.refresh_token

        identity = dict(renewal.identity)

        try:
            profile = yield from flows._userinfo(refreshed)
        except (MasksError, httpx.HTTPError, ValueError):
            profile = {}

        if profile.get("sub") == identity.get("sub"):
            identity.update({key: profile[key] for key in IDENTITY if key in profile and key != "sid"})

        return Renewed(RENEWED, refreshed, identity)

    def _departed(self, issuer: str, subject: str, sid: str, since: float) -> Step[bool]:
        for kind, value in (("sid", sid), ("sub", subject)):
            if value:
                at = yield Stored("get", keyed("departed", issuer, kind, value))

                if at and float(at) >= since:
                    return True

        return False

    def _depart(self, issuer: str, subject: str, sid: str) -> Step[None]:
        kind, value = ("sid", sid) if sid else ("sub", subject)

        if value:
            yield Stored("set", keyed("departed", issuer, kind, value), str(time.time()), self.config.backend.lifetime)

    def _sealer(self, refresh_token: str) -> AESGCM:
        derived = HKDF(algorithm=hashes.SHA256(), length=32, salt=b"masks", info=b"masks shared refresh")

        return AESGCM(derived.derive(refresh_token.encode()))

    def _sealed_renewal(self, refresh_token: str, renewed: Renewed) -> str:
        nonce = secrets.token_bytes(12)
        held = {
            "outcome": renewed.outcome,
            "token": renewed.token.to_dict() if renewed.token is not None else None,
            "identity": renewed.identity,
        }

        return b64(nonce + self._sealer(refresh_token).encrypt(nonce, json.dumps(held).encode(), None))

    def _opened_renewal(self, refresh_token: str, value: str) -> Renewed:
        try:
            raw = unb64(value)
            held = json.loads(self._sealer(refresh_token).decrypt(raw[:12], raw[12:], None))
        except (InvalidTag, ValueError):
            return Renewed(UNREACHABLE)

        token = held.get("token")

        return Renewed(
            str(held.get("outcome") or UNREACHABLE),
            Token.from_dict(token) if isinstance(token, dict) else None,
            held.get("identity") if isinstance(held.get("identity"), dict) else {},
        )

    def _sharing(self, renewal: Renewal) -> Step[Renewed]:
        issuer = self.issuer_url(renewal.request)
        result = keyed("refreshed", issuer, renewal.refresh_token)
        claim = keyed("refreshing", issuer, renewal.refresh_token)
        found = yield Stored("get", result)

        if found:
            return self._opened_renewal(renewal.refresh_token, found)

        try:
            claimed = yield Stored("add", claim, "1", RENEWAL_CLAIM)
        except Exception:
            return Renewed(UNREACHABLE)

        if not claimed:
            for _ in range(RENEWAL_WAITS):
                yield Pause(RENEWAL_WAIT)
                found = yield Stored("get", result)

                if found:
                    return self._opened_renewal(renewal.refresh_token, found)

                pending = yield Stored("get", claim)

                if not pending:
                    break

            return Renewed(UNREACHABLE)

        try:
            renewed = yield from self._renewing(renewal)

            if renewed.outcome != UNREACHABLE:
                yield from self._share(result, renewal.refresh_token, renewed)
        except Exception:
            yield Stored("delete", claim)
            raise

        yield Stored("delete", claim)

        return renewed

    def _share(self, result: str, refresh_token: str, renewed: Renewed) -> Step[None]:
        try:
            yield Stored("set", result, self._sealed_renewal(refresh_token, renewed), RENEWAL_MEMORY)
        except Exception:
            return

    def _other(self, item: object) -> object:
        if isinstance(item, Stored):
            return getattr(self.config.store, item.operation)(*stored(item))

        if isinstance(item, Pause):
            time.sleep(item.seconds)
            return None

        if isinstance(item, Ending):
            return self.config.backend.end(issuer=item.issuer, subject=item.subject, sid=item.sid)

        if not isinstance(item, Renewal):
            raise TypeError(f"masks: a flow yielded {item!r}")

        return self._renew(item)

    async def _aother(self, item: object) -> object:
        if isinstance(item, Stored):
            return await settled(getattr(self.config.store, item.operation)(*stored(item)))

        if isinstance(item, Pause):
            await anyio.sleep(item.seconds)
            return None

        if isinstance(item, Ending):
            return await self.config.backend.aend(issuer=item.issuer, subject=item.subject, sid=item.sid)

        if not isinstance(item, Renewal):
            raise TypeError(f"masks: a flow yielded {item!r}")

        return await self._arenew(item)

    def _renew(self, renewal: Renewal) -> Renewed:
        key = hashlib.sha256(renewal.refresh_token.encode()).hexdigest()

        with self._renew_locks[int(key[:8], 16) % len(self._renew_locks)]:
            return run(self._sharing(renewal), self.http, self._other)

    async def _arenew(self, renewal: Renewal) -> Renewed:
        key = hashlib.sha256(renewal.refresh_token.encode()).hexdigest()
        stripe = int(key[:8], 16) % RENEWAL_STRIPES

        with self._lock:
            lock = self._async_renew_locks.setdefault(stripe, anyio.Lock())

        async with lock:
            return await arun(self._sharing(renewal), self.async_http, self._aother)

    def _disconnect(self, request: Incoming, session: Session) -> bool:
        credentials = self.credentials(request)

        if not credentials.writable:
            return False

        credentials.clear()
        self.forget(session)

        return True

    def _refuse(self, request: Incoming, code: str, description: str, status: int = 400) -> Answer:
        if request.wants_json:
            return Answer.json(status, {"error": code, "error_description": description})

        return Answer.page(status, "Sign-in failed", f"{code}: {description}")

    def _handshake_required(self, request: Incoming) -> Answer:
        if request.wants_json:
            return Answer.json(
                401, {"signed_in": False, "error": "handshake_required", "handshake_url": self.path("/handshake")}
            )

        return Answer.redirect(self.path("/handshake"))

    def _login_required(self, request: Incoming, session: Session) -> Answer:
        if not self.configured(request):
            return self._handshake_required(request)

        if request.wants_json:
            back = referring(request)

            return Answer.json(
                401, {"signed_in": False, "error": "login_required", "login_url": self.login_url(return_to=back)}
            )

        if request.method == "GET":
            session[RETURN_TO] = request.full_path

        return Answer.redirect(self.path())

    def registered(self, request: Incoming) -> Step[bool]:
        held = self.held_credentials(request)

        if not held.get("registration_client_uri") or not held.get("registration_access_token"):
            return bool(held.get("client_id"))

        issuer = yield from self.discover(request)

        try:
            yield from self.flows(request, issuer)._read_registration(
                Registration(
                    client_id=held["client_id"],
                    registration_client_uri=held["registration_client_uri"],
                    registration_access_token=held["registration_access_token"],
                )
            )
        except Error as error:
            if error.status in (401, 403, 404):
                return False

            raise

        return True

    def start(self, request: Incoming, session: Session) -> Step[Answer]:
        if not self.configured(request):
            return self._handshake_required(request)

        try:
            known = yield from self.registered(request)
        except (MasksError, httpx.HTTPError):
            known = True

        if not known and self._disconnect(request, session):
            return self._handshake_required(request)

        issuer = yield from self.discover(request)
        flows = self.flows(request, issuer)
        resource = self.resource(request)
        return_to = local_path(request.query.get("return_to")) or local_path(session.pop(RETURN_TO, None))
        state = Tracker(session, REQUESTS).open(return_to=return_to)
        organization = organization_key(request.query.get("organization")) or organization_key(
            resolve(self.config.organization, request.native)
        )
        started = flows.start(
            self.callback_uri(request),
            scope=self.config.scope_for(request.query.get("privilege", "")) or self.config.scope,
            resource=[resource] if resource else [],
            state=state,
            organization=organization,
        )
        Tracker(session, REQUESTS).amend(state, request=started.to_dict())

        return Answer.redirect(started.url)

    def callback(self, request: Incoming, session: Session) -> Step[Answer]:
        pending = Tracker(session, REQUESTS).claim(request.query.get("state", ""))

        if request.query.get("error") and pending is None:
            return self._refuse(
                request, "invalid_state", "that sign-in request is not one this browser started, or it expired"
            )

        if request.query.get("error"):
            self.forget(session)

            return self._refuse(request, request.query["error"], request.query.get("error_description", ""))

        if pending is None or not isinstance(pending.get("request"), dict):
            return (yield from self._stale(request, session))

        started = AuthorizationRequest.from_dict(pending["request"])

        try:
            issuer = yield from self.discover(request)
            flows = self.flows(request, issuer)
            signed = yield from flows._complete(started, request.query)
        except Error as error:
            if outage(error):
                raise

            self.forget(session)

            if error.code == "invalid_client" and self._disconnect(request, session):
                return Answer.redirect(self.path("/handshake"))

            return self._refuse(request, error.code, error.description)
        except InvalidToken as error:
            self.forget(session)

            return self._refuse(request, "invalid_token", str(error).removeprefix("masks: "))

        identity = dict(signed.claims)

        try:
            profile = yield from flows._userinfo(signed.token)
        except (MasksError, httpx.HTTPError, ValueError):
            profile = {}

        if profile.get("sub") == identity.get("sub"):
            identity = {**profile, **identity}

        session.renew(keep=CARRIED)
        self._store(request, session, signed.token, identity)

        return Answer.redirect(local_path(pending.get("return_to")) or self.config.after_sign_in)

    def _stale(self, request: Incoming, session: Session) -> Step[Answer]:
        actor = yield from self.actor(request, session)

        if actor.signed_in:
            return Answer.redirect(self.config.after_sign_in)

        restarted = session.get(RESTARTED)
        lately = isinstance(restarted, (int, float)) and time.time() - restarted < RESTART_WITHIN

        if not request.wants_json and not lately:
            session[RESTARTED] = time.time()
            return Answer.redirect(self.path())

        return self._refuse(
            request, "invalid_state", "that sign-in request is not one this browser started, or it expired"
        )

    def logout(self, request: Incoming, session: Session) -> Step[Answer]:
        refused = self._provenance(request)

        if refused is not None:
            return refused

        token = self._token(request, session)
        everywhere = self.config.sign_out_of_issuer or bool(request.query.get("everywhere"))
        flows: _Flows | None = None

        if self.configured(request):
            try:
                issuer = yield from self.discover(request)
                flows = self.flows(request, issuer)

                if token is not None and token.refresh_token:
                    yield from flows._revoke(token.refresh_token, "refresh_token")
            except (MasksError, httpx.HTTPError):
                pass

        session.renew()
        upstream = ""

        if everywhere and flows is not None and flows.issuer.metadata.end_session_endpoint:
            upstream = flows.end_session_url(
                post_logout_redirect_uri=self.farewell_uri(request), state=Tracker(session, FAREWELLS).open()
            )

        if request.wants_json:
            return Answer.json(200, {"signed_in": False, **({"logout_url": upstream} if upstream else {})})

        return Answer.redirect(upstream or self.config.after_sign_out)

    def farewell_uri(self, request: Incoming) -> str:
        return f"{self.base(request)}{self.path('/logout/return')}"

    def logout_return(self, request: Incoming, session: Session) -> Step[Answer]:
        yield from ()

        if Tracker(session, FAREWELLS).claim(request.query.get("state", "")) is None:
            return self._refuse(
                request, "invalid_state", "that sign-out is not one this browser started, or it expired"
            )

        return Answer.redirect(local_path(self.config.after_sign_out) or "/")

    def session_answer(self, request: Incoming, session: Session) -> Step[Answer]:
        actor = nobody(self.config.known)

        if self.configured(request):
            actor = yield from self.actor(request, session)

        if actor.signed_in:
            return Answer.json(200, actor.to_dict())

        self.forget(session)

        if not self.configured(request):
            return Answer.json(
                401, {"signed_in": False, "error": "handshake_required", "handshake_url": self.path("/handshake")}
            )

        return Answer.json(401, {"signed_in": False, "error": "login_required", "login_url": self.login_url()})

    def avatar(self, request: Incoming, session: Session) -> Step[Answer]:
        actor = yield from self.actor(request, session)
        photo = actor.avatars.get("photo", "")
        home = f"{self.issuer_url(request)}/"

        if not actor.signed_in or not photo.startswith(home):
            return Answer(404, headers=[("Cache-Control", "no-store")])

        asked = request.query.get("size", "")

        if asked:
            wanted = int(asked) if asked.isdigit() and len(asked) <= 4 else AVATAR_SIZES[-1]
            photo = f"{photo}?size={next((size for size in AVATAR_SIZES if size >= wanted), AVATAR_SIZES[-1])}"

        token = self._token(request, session)
        headers = {"Accept": "image/*", "Authorization": f"Bearer {token.access_token if token else ''}"}

        try:
            response = yield httpx.Request("GET", photo, headers=headers)
        except (httpx.HTTPError, Error):
            return Answer(502, headers=[("Cache-Control", "no-store")])

        if 300 <= response.status_code < 400 and response.headers.get("Location"):
            location = str(httpx.URL(photo).join(response.headers["Location"]))

            try:
                check(location, self.config.allow_plain_http)
            except MasksError:
                return Answer(404, headers=[("Cache-Control", "no-store")])

            return Answer(302, headers=[("Location", location), ("Cache-Control", "private, max-age=300")])

        kind = response.headers.get("Content-Type", "").split(";")[0].strip().lower()

        if response.status_code != 200 or not kind.startswith("image/"):
            return Answer(404, headers=[("Cache-Control", "no-store")])

        return Answer(
            200,
            response.content,
            kind,
            [
                ("Cache-Control", "private, max-age=300"),
                ("X-Content-Type-Options", "nosniff"),
                ("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox"),
            ],
        )

    def start_delegation(
        self,
        request: Incoming,
        session: Session,
        provider: str,
        prompt: str | None = None,
        max_age: int | None = None,
    ) -> Step[Answer]:
        redirect_uri = self.delegation_uri(request)

        if not redirect_uri:
            raise ValueError("masks: set delegation_redirect_uri to the address a provider connection comes back to")

        actor = yield from self.actor(request, session)

        if not actor.signed_in or not actor.subject:
            return self._login_required(request, session)

        issuer = yield from self.discover(request)
        started = self.flows(request, issuer).start_delegation(provider, redirect_uri, prompt=prompt, max_age=max_age)
        Tracker(session, DELEGATIONS).keep(started.state, request=started.to_dict(), account=actor.subject)

        return Answer.redirect(started.url)

    def finish_delegation(self, request: Incoming, session: Session) -> Step[HeldConnection]:
        pending = Tracker(session, DELEGATIONS).claim(request.query.get("state", ""))

        if request.query.get("error"):
            raise DelegationRefused(request.query["error"], request.query.get("error_description", ""))

        if pending is None or not isinstance(pending.get("request"), dict):
            raise DelegationRefused("invalid_state", "that connection was not started by this browser, or it expired")

        actor = yield from self.actor(request, session)

        if not actor.signed_in or actor.subject != pending.get("account"):
            raise DelegationRefused("access_denied", "someone other than the person signed in finished that connection")

        try:
            issuer = yield from self.discover(request)
            held = yield from self.flows(request, issuer)._finish_delegation(
                AuthorizationRequest.from_dict(pending["request"]), request.query
            )
        except InvalidToken as error:
            raise DelegationRefused("invalid_token", str(error).removeprefix("masks: ")) from error
        except (Error, Unavailable, httpx.HTTPError) as error:
            raise delegation_failure(error, "") from error

        if held.account != actor.subject:
            raise DelegationRefused("access_denied", "masks connected that provider for another account")

        return held

    def backchannel(self, request: Incoming) -> Step[Answer]:
        logout_token = request.form.get("logout_token", "")

        if not logout_token:
            return Answer.json(400, {"error": "invalid_request", "error_description": "logout_token is required"})

        if not self.configured(request):
            return Answer.json(400, {"error": "invalid_request", "error_description": "this app is not connected"})

        try:
            issuer = yield from self.discover(request)
            logout = yield from self.flows(request, issuer)._logout(logout_token)
        except InvalidToken as error:
            return Answer.json(
                400, {"error": "invalid_request", "error_description": str(error).removeprefix("masks: ")}
            )

        seen = keyed("logout", issuer.url, logout.id)
        first = yield Stored("add", seen, "1", logout_memory(logout))

        if not first:
            return Answer.json(
                400, {"error": "invalid_request", "error_description": "that logout token was already used"}
            )

        named = self.issuer_url(request)

        try:
            yield from self._depart(named, logout.subject, logout.sid)
            yield Ending(named, logout.subject, logout.sid)

            if self.config.logged_out is not None:
                self.config.logged_out(logout)
        except Exception:
            yield Stored("delete", seen)
            raise

        return Answer(200, headers=[("Cache-Control", "no-store")])

    def handshake(self, request: Incoming, issuer: Issuer) -> Handshake:
        resource = self.resource(request)

        if not resource:
            raise Refusal(
                self._refuse(request, "invalid_request", "this app names no resource, so it cannot shake hands")
            )

        base = self.base(request)
        delegated = self.delegation_uri(request)
        backchannel = f"{base}{self.path('/logout/backchannel')}"

        return Handshake(
            issuer,
            name=str(resolve(self.config.name, request.native) or "An app"),
            resource=resource,
            redirect_uris=list(dict.fromkeys([self.callback_uri(request), *([delegated] if delegated else [])])),
            return_to=f"{base}{self.path('/handshake/callback')}",
            scope=self.config.approved_scope(),
            backchannel_logout_uri=backchannel,
            post_logout_redirect_uri=self.farewell_uri(request),
        )

    def _guard(self, request: Incoming, session: Session) -> Step[Answer | None]:
        if not self.configured(request):
            return None

        actor = yield from self.actor(request, session)

        if not actor.signed_in:
            if request.wants_json:
                return Answer.json(401, {"signed_in": False, "error": "login_required", "login_url": self.login_url()})

            return Answer.redirect(self.config.after_sign_out)

        if not self.config.manager(actor):
            return self._refuse(
                request, "forbidden", "only somebody this app lets manage its connection can change it", 403
            )

        return None

    def _provenance(self, request: Incoming) -> Answer | None:
        site = request.headers.get("Sec-Fetch-Site", "")
        sent = request.headers.get("Origin", "")

        if site and site not in ("same-origin", "none"):
            return self._refuse(request, "invalid_request", "that request came from another site", 403)

        if sent and (sent == "null" or origin(sent) not in (request.origin, origin(self.base(request)))):
            return self._refuse(request, "invalid_request", "that request came from another site", 403)

        if site or sent:
            return None

        if request.method in ("POST", "DELETE"):
            return self._refuse(request, "invalid_request", "that request came from another site", 403)

        if request.wants_json:
            return self._refuse(request, "invalid_request", "sign out with a POST from this site", 403)

        query = urlsplit(request.url).query
        action = html.escape(self.path("/logout") + (f"?{query}" if query else ""), quote=True)

        return Answer.page(
            200,
            "Sign out",
            "Select Sign out to finish signing out.",
            f'<form method="post" action="{action}"><button type="submit">Sign out</button></form>',
            form_targets=None,
        )

    def handshake_show(self, request: Incoming, session: Session) -> Step[Answer]:
        refused = yield from self._guard(request, session)

        if refused is not None:
            return refused

        if not self.configured(request):
            return (yield from self._begin(request, session))

        held = self.credentials(request)
        status = {
            "connected": True,
            "issuer": self.issuer_url(request),
            "client_id": self.held_credentials(request).get("client_id", ""),
            "can_disconnect": held.writable,
        }

        if request.wants_json:
            return Answer.json(200, status)

        here = html.escape(self.path("/handshake"))
        forms = f"<form method=post action='{here}'><button>Reconnect</button></form>"

        if held.writable:
            leaving = html.escape(self.path("/handshake/disconnect"))
            forms += f"<form method=post action='{leaving}'><button>Disconnect</button></form>"

        return Answer.page(
            200,
            "Connected to masks",
            f"{status['client_id']} at {status['issuer']}",
            forms,
            form_targets=[origin(self.issuer_url(request))],
        )

    def handshake_begin(self, request: Incoming, session: Session) -> Step[Answer]:
        refused = self._provenance(request)

        if refused is not None:
            return refused

        refused = yield from self._guard(request, session)

        return refused if refused is not None else (yield from self._begin(request, session))

    def _begin(self, request: Incoming, session: Session) -> Step[Answer]:
        issuer = yield from self.discover(request)
        shaking = self.handshake(request, issuer)
        state = Tracker(session, HANDSHAKES).open()

        return Answer.redirect(shaking.start(state).url)

    def handshake_callback(self, request: Incoming, session: Session) -> Step[Answer]:
        refused = yield from self._guard(request, session)

        if refused is not None:
            return refused

        state = request.query.get("state", "")

        if Tracker(session, HANDSHAKES).claim(state) is None:
            return self._refuse(
                request, "invalid_state", "that connection request is not one this browser started, or it expired"
            )

        if not self.credentials(request).writable:
            return self._refuse(
                request, "forbidden", "this app cannot save new credentials, so its connection cannot change", 403
            )

        try:
            issuer = yield from self.discover(request)
            registration = yield from self.handshake(request, issuer)._complete(request.query, state)
        except Error as error:
            if outage(error):
                raise

            return self._refuse(request, error.code, error.description)

        self.credentials(request).write(self.issuer_url(request), registration)

        return Answer.redirect(self.path())

    def handshake_disconnect(self, request: Incoming, session: Session) -> Step[Answer]:
        refused = self._provenance(request)

        if refused is not None:
            return refused

        if not self.configured(request):
            return Answer.redirect(self.path("/handshake"))

        refused = yield from self._guard(request, session)

        if refused is not None:
            return refused

        credentials = self.credentials(request)

        if not credentials.writable:
            return self._refuse(
                request, "forbidden", "this app cannot save new credentials, so its connection cannot change", 403
            )

        held = self.held_credentials(request)

        if held.get("registration_client_uri") and held.get("registration_access_token"):
            try:
                issuer = yield from self.discover(request)
                yield from self.flows(request, issuer)._delete_registration(
                    Registration(
                        client_id=held["client_id"],
                        registration_client_uri=held["registration_client_uri"],
                        registration_access_token=held["registration_access_token"],
                    )
                )
            except Error as error:
                if outage(error):
                    return self._refuse(request, "temporarily_unavailable", "masks could not be reached", 503)

                if error.status not in (401, 403, 404):
                    return self._refuse(request, error.code, error.description)
            except (MasksError, httpx.HTTPError):
                return self._refuse(request, "temporarily_unavailable", "masks could not be reached", 503)

        credentials.clear()
        session.renew()

        if request.wants_json:
            return Answer.json(200, {"connected": False, "handshake_url": self.path("/handshake")})

        return Answer.redirect(self.path("/handshake"))

    def session_check(self, request: Incoming, session: Session, names: Sequence[str]) -> Step[Actor | Answer]:
        wanted = scoped(names, self.config.known)

        if not self.configured(request):
            return self._handshake_required(request)

        actor = yield from self.actor(request, session)

        if not actor.signed_in:
            self.forget(session)
            return self._login_required(request, session)

        try:
            for privilege in wanted:
                if privilege.roles or privilege.organization:
                    actor.member(*privilege.roles, organization=privilege.organization)
        except Forbidden as error:
            return self._forbid(request, error)

        missing = [privilege.name for privilege in wanted if not set(privilege.scopes) <= set(actor.scopes)]

        if not missing:
            return actor

        asked = session.pop(STEPPED_UP, None)

        if (
            isinstance(asked, dict)
            and set(missing) <= set(asked.get("privileges") or [])
            and isinstance(asked.get("at"), (int, float))
            and asked["at"] > time.time() - STEP_UP_WITHIN
        ):
            scopes = " ".join(scope for name in missing for scope in self.config.known[name].scopes)

            return self._forbid(
                request,
                Forbidden(
                    "insufficient_scope",
                    f"this account does not hold the {' and '.join(missing)} privilege",
                    scope=scopes,
                ),
            )

        back = request.full_path if request.method == "GET" else referring(request)
        url = self.login_url(return_to=back, privilege=missing)
        session[STEPPED_UP] = {"privileges": missing, "at": time.time()}

        if request.wants_json:
            return Answer.json(403, {"error": "privilege_required", "privileges": missing, "login_url": url})

        return Answer.redirect(url)

    def _forbid(self, request: Incoming, error: Forbidden) -> Answer:
        if request.wants_json:
            return Answer.json(403, {"error": error.code, "error_description": error.description})

        return Answer.page(403, "Not allowed", error.description)

    def by_token(self, request: Incoming, session: Session) -> bool:
        return bool(request.authorization) or HELD not in session

    def metadata(self, request: Incoming) -> dict[str, Any]:
        scopes = self.config.resource_scopes
        found = {
            "resource": self.resource(request),
            "authorization_servers": [self.issuer_url(request)],
            "scopes_supported": list(scopes),
            "scope_descriptions": dict(scopes) if isinstance(scopes, Mapping) else {},
            "bearer_methods_supported": ["header"],
            "dpop_signing_alg_values_supported": list(PROOF_ALGORITHMS),
        }

        return {key: value for key, value in found.items() if value}

    def challenge(
        self, request: Incoming, code: str = "", description: str = "", scope: str = ""
    ) -> list[tuple[str, str]]:
        resource = self.resource(request)
        metadata = f"{origin(resource) if resource else self.base(request)}{METADATA_PATH}"
        named = scope or " ".join(self.config.resource_scopes)
        pairs = [("error", code), ("error_description", description), ("scope", named), ("resource_metadata", metadata)]
        joined = ", ".join(f'{name}="{quoted(value)}"' for name, value in pairs if value)

        return [
            ("WWW-Authenticate", f"Bearer {joined}"),
            ("WWW-Authenticate", f'{DPOP} algs="{" ".join(PROOF_ALGORITHMS)}", {joined}'),
        ]

    def _token_refusal(self, request: Incoming, error: Exception) -> Answer:
        if isinstance(error, Forbidden):
            return Answer.json(
                403,
                {"error": error.code, "error_description": error.description},
                self.challenge(request, error.code, error.description, error.scope),
            )

        if isinstance(error, Unavailable):
            return Answer.json(
                503,
                {"error": "temporarily_unavailable", "error_description": "the token could not be checked just now"},
                [("Retry-After", "5")],
            )

        if not request.authorization:
            return Answer.json(
                401,
                {"error": "invalid_token", "error_description": "a bearer token is required"},
                self.challenge(request),
            )

        said = str(error).removeprefix("masks: ")

        return Answer.json(
            401, {"error": "invalid_token", "error_description": said}, self.challenge(request, "invalid_token", said)
        )

    def _granted(self, request: Incoming, claims: Claims, wanted: Sequence[Privilege]) -> Actor:
        actor = Actor(
            signed_in=True,
            claims=dict(claims.raw),
            scopes=tuple(claims.scopes),
            access_token=request.authorization.partition(" ")[2].strip(),
            expires_at=float(claims.expiry),
            known=self.config.known,
            by_token=True,
        )

        for privilege in wanted:
            for scope in privilege.scopes:
                if not actor.permits(scope):
                    raise Forbidden("insufficient_scope", f"this token does not carry {scope}", scope=scope)

            if privilege.roles or privilege.organization:
                actor.member(*privilege.roles, organization=privilege.organization)

        return actor

    def _audience(self, request: Incoming) -> str:
        resource = self.resource(request)

        if not resource:
            raise ValueError("masks: protecting an API needs a resource, the audience its tokens name")

        return resource

    def verifier(self, request: Incoming, issuer: Issuer) -> Verifier:
        key = (issuer.url, self._audience(request))

        with self._lock:
            if key not in self._verifiers:
                if asynchronous(self.config.store):
                    raise TypeError("masks: an async store needs an async framework, such as FastAPI")

                self._verifiers[key] = Verifier(
                    issuer,
                    key[1],
                    public_url=self.base(request),
                    http=self.http,
                    replay=Replays(cast(Store, self.config.store)),
                )

            return self._verifiers[key]

    def async_verifier(self, request: Incoming, issuer: Issuer) -> AsyncVerifier:
        key = (issuer.url, self._audience(request))

        with self._lock:
            if key not in self._async_verifiers:
                held = self.config.store
                replay = AsyncReplays(cast(AsyncStore, held)) if asynchronous(held) else Replays(cast(Store, held))
                self._async_verifiers[key] = AsyncVerifier(
                    issuer, key[1], public_url=self.base(request), http=self.async_http, replay=replay
                )

            return self._async_verifiers[key]

    def protect(self, request: Incoming, names: Sequence[str]) -> Actor | Answer:
        wanted = scoped(names, self.config.known)

        try:
            issuer = self.run(self.discover(request))
            claims = self.verifier(request, issuer).authenticate(request.method, request.url, request.headers)

            return self._granted(request, claims, wanted)
        except (InvalidToken, Forbidden, Unavailable) as error:
            return self._token_refusal(request, error)
        except (Error, httpx.HTTPError) as error:
            return self._token_refusal(request, Unavailable(str(error)))

    async def aprotect(self, request: Incoming, names: Sequence[str]) -> Actor | Answer:
        wanted = scoped(names, self.config.known)

        try:
            issuer = await self.arun(self.discover(request))
            verifier = self.async_verifier(request, issuer)
            claims = await verifier.authenticate(request.method, request.url, request.headers)

            return self._granted(request, claims, wanted)
        except (InvalidToken, Forbidden, Unavailable) as error:
            return self._token_refusal(request, error)
        except (Error, httpx.HTTPError) as error:
            return self._token_refusal(request, Unavailable(str(error)))

    def authorize(
        self, request: Incoming, session: Session, names: Sequence[str], tokens: bool = False
    ) -> Actor | Answer:
        if tokens and self.by_token(request, session):
            return self.protect(request, names)

        return self.answer(self.session_check(request, session, names))

    async def aauthorize(
        self, request: Incoming, session: Session, names: Sequence[str], tokens: bool = False
    ) -> Actor | Answer:
        if tokens and self.by_token(request, session):
            return await self.aprotect(request, names)

        return await self.aanswer(self.session_check(request, session, names))

    def run(self, flow: Step[T]) -> T:
        return run(flow, self.http, self._other)

    async def arun(self, flow: Step[T]) -> T:
        return await arun(flow, self.async_http, self._aother)

    def answer(self, flow: Step[T]) -> T | Answer:
        try:
            return self.run(flow)
        except Refusal as refusal:
            return refusal.answer
        except (Unavailable, httpx.HTTPError, Error):
            return unreachable()

    async def aanswer(self, flow: Step[T]) -> T | Answer:
        try:
            return await self.arun(flow)
        except Refusal as refusal:
            return refusal.answer
        except (Unavailable, httpx.HTTPError, Error):
            return unreachable()

    def fetch(self, request: httpx.Request) -> httpx.Response:
        return fetch(request, self.http)

    async def afetch(self, request: httpx.Request) -> httpx.Response:
        return await afetch(request, self.async_http)

    def handlers(self) -> dict[str, Callable[[Incoming, Session], Step[Answer]]]:
        return {
            "start": self.start,
            "callback": self.callback,
            "logout": self.logout,
            "logout_return": self.logout_return,
            "session": self.session_answer,
            "avatar": self.avatar,
            "handshake": self.handshake_show,
            "handshake_begin": self.handshake_begin,
            "handshake_callback": self.handshake_callback,
            "handshake_disconnect": self.handshake_disconnect,
        }

    def routes(self) -> list[tuple[str, tuple[str, ...], str]]:
        return [
            (self.path(), ("GET",), "start"),
            (self.path("/callback"), ("GET",), "callback"),
            (self.path("/session"), ("GET",), "session"),
            (self.path("/avatar"), ("GET",), "avatar"),
            (self.path("/logout"), ("GET", "POST", "DELETE"), "logout"),
            (self.path("/logout/return"), ("GET",), "logout_return"),
            (self.path("/logout/backchannel"), ("POST",), "backchannel"),
            (self.path("/handshake"), ("GET",), "handshake"),
            (self.path("/handshake"), ("POST",), "handshake_begin"),
            (self.path("/handshake"), ("DELETE",), "handshake_disconnect"),
            (self.path("/handshake/disconnect"), ("POST",), "handshake_disconnect"),
            (self.path("/handshake/callback"), ("GET",), "handshake_callback"),
        ]


def outage(error: Error) -> bool:
    return error.code in ("server_error", "temporarily_unavailable") or (error.status or 0) >= 500


def logout_memory(logout: Logout) -> int:
    return max(LOGOUT_MEMORY, int(float(logout.raw["exp"]) - time.time()) + LOGOUT_LEEWAY)


def stored(item: Stored) -> tuple[Any, ...]:
    if item.operation in ("get", "delete"):
        return (item.key,)

    return (item.key, item.value, item.expires_in)


def too_large() -> Answer:
    return Answer.json(413, {"error": "invalid_request", "error_description": "the request is too large"})


def unreachable() -> Answer:
    return Answer.page(503, "masks could not be reached", "Try again in a moment.")
