from __future__ import annotations

import html
import inspect
import json
import re
import threading
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any, TypeVar, cast
from urllib.parse import urlencode, urlsplit

import httpx

from ..client import AsyncClient, Client, _Flows
from ..dpop import DPOP
from ..errors import Error, Forbidden, InvalidToken, MasksError, Unavailable
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
from ..keyset import same
from ..models import Issuer, Registration, Token
from ..oidc import AVATARS_CLAIM, AuthorizationRequest, organization_key
from ..replay import MemoryReplayStore, ReplayStore
from ..verifier import PROOF_ALGORITHMS, AsyncVerifier, Claims, Verifier
from .config import Config, resolve
from .credentials import Credentials
from .person import Person, Privilege, nobody, scoped
from .sessions import ServerSessions, Session

T = TypeVar("T")

HELD = "masks"
REQUESTS = "masks_requests"
HANDSHAKES = "masks_handshakes"
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
    def page(cls, status: int, title: str, said: str, extra: str = "") -> Answer:
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
                ("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'"),
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


def cookie_named(header: str, name: str) -> str | None:
    for part in header.split(";"):
        key, found, value = part.strip().partition("=")

        if found and key == name:
            return value.strip().strip('"')

    return None


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
        key = random_id()
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
        self.replay = config.replay or MemoryReplayStore()
        self._http = config.http
        self._async_http = config.async_http
        self._issuers: dict[str, tuple[Issuer, float]] = {}
        self._verifiers: dict[tuple[str, str], Verifier] = {}
        self._async_verifiers: dict[tuple[str, str], AsyncVerifier] = {}
        self._lock = threading.Lock()

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

    def load(self, cookie: str | None) -> Session:
        return self.config.backend.load(cookie)

    def seal(self, session: Session, secure_request: bool) -> Sealed | None:
        if not session.dirty:
            return None

        backend = self.config.backend
        identity = self._held(session).get("identity") or {}
        tags = {name: str(identity[name]) for name in ("sub", "sid") if identity.get(name)}
        value = backend.save(session, tags)
        secure = self.config.cookie_secure or secure_request
        session.modified = False
        session.renewed = False

        if value is None:
            return Sealed(backend.name, "", 0, secure)

        return Sealed(backend.name, value, max(int(session.issued_at + backend.lifetime - time.time()), 1), secure)

    def cookie(self, session: Session, secure_request: bool) -> str | None:
        sealed = self.seal(session, secure_request)

        return sealed.header if sealed is not None else None

    def issuer_url(self, request: Incoming) -> str:
        found = str(resolve(self.config.issuer, request.native) or "").rstrip("/")

        if not found:
            raise ValueError("masks: no issuer is configured")

        return found

    def credentials(self, request: Incoming) -> Credentials:
        return resolve(self.config.credentials, request.native)

    def configured(self, request: Incoming) -> bool:
        return bool(self.credentials(request).read().get("client_id"))

    def resource(self, request: Incoming) -> str:
        return str(resolve(self.config.resource, request.native) or "")

    def base(self, request: Incoming) -> str:
        named = str(resolve(self.config.base_url, request.native) or "").rstrip("/")
        resource = self.resource(request)

        return named or (origin(resource) if resource else request.origin)

    def callback_uri(self, request: Incoming) -> str:
        return f"{self.base(request)}{self.path('/callback')}"

    def account_url(self, request: Incoming) -> str:
        return f"{self.issuer_url(request)}/"

    def discover(self, request: Incoming) -> Flow[Issuer]:
        named = self.issuer_url(request)
        held = self._issuers.get(named)

        if held is not None and time.monotonic() - held[1] < ISSUER_LIFETIME:
            return held[0]

        found = yield from discovery(named, self.config.allow_plain_http)

        with self._lock:
            self._issuers[named] = (found, time.monotonic())

        return found

    def flows(self, request: Incoming, issuer: Issuer) -> _Flows:
        held = self.credentials(request).read()

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

    def _token(self, session: Session) -> Token | None:
        found = self._held(session).get("token")

        return Token.from_dict(found) if isinstance(found, dict) and found.get("access_token") else None

    def _store(self, session: Session, token: Token, identity: Mapping[str, Any] | None = None) -> None:
        held = {key: value for key, value in token.to_dict().items() if key != "id_token"}
        kept = identity if identity is not None else self._held(session).get("identity") or {}
        session[HELD] = {"token": held, "identity": {key: kept[key] for key in IDENTITY if key in kept}}

    def forget(self, session: Session) -> None:
        if HELD in session:
            del session[HELD]

    def _person(self, request: Incoming, session: Session, token: Token | None, signed_in: bool) -> Person:
        if token is None:
            return nobody(self.config.known)

        identity = self._held(session).get("identity") or {}

        return Person(
            signed_in=signed_in,
            claims=dict(identity),
            scopes=tuple(token.scopes),
            access_token=token.access_token,
            expires_at=token.expires_at,
            account_url=self.account_url(request),
            known=self.config.known,
        )

    def person(self, request: Incoming, session: Session) -> Flow[Person]:
        token = self._token(session)

        if token is None:
            return nobody(self.config.known)

        if token.valid():
            return self._person(request, session, token, True)

        refreshed = yield from self._refresh(request, session, token)

        return self._person(request, session, self._token(session), refreshed)

    def _refresh(self, request: Incoming, session: Session, token: Token) -> Flow[bool]:
        if not token.refresh_token or not self.configured(request):
            return False

        try:
            issuer = yield from self.discover(request)
            flows = self.flows(request, issuer)
            resource = self.resource(request)
            refreshed = yield from flows._refresh(token.refresh_token, (), [resource] if resource else [])
        except Error as error:
            if error.code == "invalid_client":
                self._disconnect(request, session)
            elif error.status is not None and error.status < 500:
                self.forget(session)

            return False
        except (httpx.HTTPError, Unavailable, Refusal):
            return False

        if not refreshed.refresh_token:
            refreshed.refresh_token = token.refresh_token

        identity = dict(self._held(session).get("identity") or {})

        try:
            profile = yield from flows._userinfo(refreshed)
        except (MasksError, httpx.HTTPError, ValueError):
            profile = {}

        if profile.get("sub") == identity.get("sub"):
            identity.update({key: profile[key] for key in IDENTITY if key in profile and key != "sid"})

        self._store(session, refreshed, identity)

        return True

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

    def start(self, request: Incoming, session: Session) -> Flow[Answer]:
        if not self.configured(request):
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

    def callback(self, request: Incoming, session: Session) -> Flow[Answer]:
        pending = Tracker(session, REQUESTS).claim(request.query.get("state", ""))

        if request.query.get("error"):
            if pending is not None:
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
        self._store(session, signed.token, identity)

        return Answer.redirect(local_path(pending.get("return_to")) or self.config.after_sign_in)

    def _stale(self, request: Incoming, session: Session) -> Flow[Answer]:
        person = yield from self.person(request, session)

        if person.signed_in:
            return Answer.redirect(self.config.after_sign_in)

        restarted = session.get(RESTARTED)
        lately = isinstance(restarted, (int, float)) and time.time() - restarted < RESTART_WITHIN

        if not request.wants_json and not lately:
            session[RESTARTED] = time.time()
            return Answer.redirect(self.path())

        return self._refuse(
            request, "invalid_state", "that sign-in request is not one this browser started, or it expired"
        )

    def logout(self, request: Incoming, session: Session) -> Flow[Answer]:
        if request.method != "GET" and not self._same_origin(request):
            return self._refuse(request, "invalid_request", "that request came from another site", 403)

        token = self._token(session)
        upstream = ""

        if self.configured(request):
            try:
                issuer = yield from self.discover(request)
                flows = self.flows(request, issuer)

                if self.config.sign_out_of_issuer or request.query.get("everywhere"):
                    upstream = flows.end_session_url(
                        post_logout_redirect_uri=f"{self.base(request)}{local_path(self.config.after_sign_out) or '/'}",
                        state=random_id(),
                    )

                if token is not None and token.refresh_token:
                    yield from flows._revoke(token.refresh_token, "refresh_token")
            except (MasksError, httpx.HTTPError):
                pass

        session.renew()

        if request.wants_json:
            return Answer.json(200, {"signed_in": False, **({"logout_url": upstream} if upstream else {})})

        return Answer.redirect(upstream or self.config.after_sign_out)

    def session_answer(self, request: Incoming, session: Session) -> Flow[Answer]:
        person = nobody(self.config.known)

        if self.configured(request):
            person = yield from self.person(request, session)

        if person.signed_in:
            return Answer.json(200, person.to_dict())

        self.forget(session)

        if not self.configured(request):
            return Answer.json(
                401, {"signed_in": False, "error": "handshake_required", "handshake_url": self.path("/handshake")}
            )

        return Answer.json(401, {"signed_in": False, "error": "login_required", "login_url": self.login_url()})

    def avatar(self, request: Incoming, session: Session) -> Flow[Answer]:
        person = yield from self.person(request, session)
        photo = person.avatars.get("photo", "")
        home = f"{self.issuer_url(request)}/"

        if not person.signed_in or not photo.startswith(home):
            return Answer(404, headers=[("Cache-Control", "no-store")])

        asked = request.query.get("size", "")

        if asked:
            wanted = int(asked) if asked.isdigit() else AVATAR_SIZES[-1]
            photo = f"{photo}?size={next((size for size in AVATAR_SIZES if size >= wanted), AVATAR_SIZES[-1])}"

        token = self._token(session)
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

    def backchannel(self, request: Incoming) -> Flow[Answer]:
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

        ended = self.config.backend.end(subject=logout.subject, sid=logout.sid)

        if self.config.logged_out is not None:
            self.config.logged_out(logout)

        if ended is None and self.config.logged_out is None:
            return Answer.json(501, {"error": "unsupported", "error_description": "this app cannot end sessions"})

        return Answer(200, headers=[("Cache-Control", "no-store")])

    def ends_sessions(self) -> bool:
        return self.config.logged_out is not None or isinstance(self.config.backend, ServerSessions)

    def handshake(self, request: Incoming, issuer: Issuer) -> Handshake:
        resource = self.resource(request)

        if not resource:
            raise Refusal(
                self._refuse(request, "invalid_request", "this app names no resource, so it cannot shake hands")
            )

        base = self.base(request)
        delegated = str(resolve(self.config.delegation_redirect_uri, request.native) or "")
        backchannel = (
            f"{base}{self.path('/logout/backchannel')}"
            if self.ends_sessions() and issuer.metadata.backchannel_logout_supported
            else ""
        )

        return Handshake(
            issuer,
            name=str(resolve(self.config.name, request.native) or "An app"),
            resource=resource,
            redirect_uris=list(dict.fromkeys([self.callback_uri(request), *([delegated] if delegated else [])])),
            return_to=f"{base}{self.path('/handshake/callback')}",
            scope=self.config.approved_scope(),
            backchannel_logout_uri=backchannel,
        )

    def _guard(self, request: Incoming, session: Session) -> Flow[Answer | None]:
        if not self.configured(request):
            return None

        person = yield from self.person(request, session)

        if not person.signed_in:
            if request.wants_json:
                return Answer.json(401, {"signed_in": False, "error": "login_required", "login_url": self.login_url()})

            return Answer.redirect(self.config.after_sign_out)

        if not self.config.manager(person):
            return self._refuse(
                request, "forbidden", "only somebody this app lets manage its connection can change it", 403
            )

        return None

    def _same_origin(self, request: Incoming) -> bool:
        sent = request.headers.get("Origin", "")

        if not sent:
            return True

        if sent == "null":
            return False

        return origin(sent) in (request.origin, origin(self.base(request)))

    def handshake_show(self, request: Incoming, session: Session) -> Flow[Answer]:
        refused = yield from self._guard(request, session)

        if refused is not None:
            return refused

        if not self.configured(request):
            return (yield from self._begin(request, session))

        held = self.credentials(request)
        status = {
            "connected": True,
            "issuer": self.issuer_url(request),
            "client_id": held.read().get("client_id", ""),
            "can_disconnect": held.writable,
        }

        if request.wants_json:
            return Answer.json(200, status)

        here = html.escape(self.path("/handshake"))
        forms = f"<form method=post action='{here}'><button>Reconnect</button></form>"

        if held.writable:
            leaving = html.escape(self.path("/handshake/disconnect"))
            forms += f"<form method=post action='{leaving}'><button>Disconnect</button></form>"

        return Answer.page(200, "Connected to masks", f"{status['client_id']} at {status['issuer']}", forms)

    def handshake_begin(self, request: Incoming, session: Session) -> Flow[Answer]:
        if not self._same_origin(request):
            return self._refuse(request, "invalid_request", "that request came from another site", 403)

        refused = yield from self._guard(request, session)

        return refused if refused is not None else (yield from self._begin(request, session))

    def _begin(self, request: Incoming, session: Session) -> Flow[Answer]:
        issuer = yield from self.discover(request)
        shaking = self.handshake(request, issuer)
        state = Tracker(session, HANDSHAKES).open()

        return Answer.redirect(shaking.start(state).url)

    def handshake_callback(self, request: Incoming, session: Session) -> Flow[Answer]:
        refused = yield from self._guard(request, session)

        if refused is not None:
            return refused

        state = request.query.get("state", "")

        if Tracker(session, HANDSHAKES).claim(state) is None:
            return self._refuse(
                request, "invalid_state", "that connection request is not one this browser started, or it expired"
            )

        try:
            issuer = yield from self.discover(request)
            registration = yield from self.handshake(request, issuer)._complete(request.query, state)
        except Error as error:
            return self._refuse(request, error.code, error.description)

        self.credentials(request).write(registration)

        return Answer.redirect(self.path())

    def handshake_disconnect(self, request: Incoming, session: Session) -> Flow[Answer]:
        if not self._same_origin(request):
            return self._refuse(request, "invalid_request", "that request came from another site", 403)

        if not self.configured(request):
            return Answer.redirect(self.path("/handshake"))

        refused = yield from self._guard(request, session)

        if refused is not None:
            return refused

        credentials = self.credentials(request)

        if not credentials.writable:
            return self._refuse(request, "forbidden", "these credentials come from configuration", 403)

        held = credentials.read()

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
                if error.status not in (401, 403, 404):
                    return self._refuse(request, error.code, error.description)
            except (MasksError, httpx.HTTPError):
                return self._refuse(request, "temporarily_unavailable", "masks could not be reached", 503)

        credentials.clear()
        session.renew()

        if request.wants_json:
            return Answer.json(200, {"connected": False, "handshake_url": self.path("/handshake")})

        return Answer.redirect(self.path("/handshake"))

    def session_check(self, request: Incoming, session: Session, names: Sequence[str]) -> Flow[Person | Answer]:
        wanted = scoped(names, self.config.known)

        if not self.configured(request):
            return self._handshake_required(request)

        person = yield from self.person(request, session)

        if not person.signed_in:
            self.forget(session)
            return self._login_required(request, session)

        try:
            for privilege in wanted:
                if privilege.roles or privilege.organization:
                    person.member(*privilege.roles, organization=privilege.organization)
        except Forbidden as error:
            return self._forbid(request, error)

        missing = [privilege.name for privilege in wanted if not set(privilege.scopes) <= set(person.scopes)]

        if not missing:
            return person

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

    def _granted(self, request: Incoming, claims: Claims, wanted: Sequence[Privilege]) -> Person:
        person = Person(
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
                if not person.permits(scope):
                    raise Forbidden("insufficient_scope", f"this token does not carry {scope}", scope=scope)

            if privilege.roles or privilege.organization:
                person.member(*privilege.roles, organization=privilege.organization)

        return person

    def _audience(self, request: Incoming) -> str:
        resource = self.resource(request)

        if not resource:
            raise ValueError("masks: protecting an API needs a resource, the audience its tokens name")

        return resource

    def verifier(self, request: Incoming, issuer: Issuer) -> Verifier:
        key = (issuer.url, self._audience(request))

        with self._lock:
            if key not in self._verifiers:
                if inspect.iscoroutinefunction(getattr(self.replay, "first", None)):
                    raise TypeError("masks: an async replay store needs an async framework")

                self._verifiers[key] = Verifier(
                    issuer,
                    key[1],
                    public_url=self.base(request),
                    http=self.http,
                    replay=cast(ReplayStore, self.replay),
                )

            return self._verifiers[key]

    def async_verifier(self, request: Incoming, issuer: Issuer) -> AsyncVerifier:
        key = (issuer.url, self._audience(request))

        with self._lock:
            if key not in self._async_verifiers:
                self._async_verifiers[key] = AsyncVerifier(
                    issuer, key[1], public_url=self.base(request), http=self.async_http, replay=self.replay
                )

            return self._async_verifiers[key]

    def protect(self, request: Incoming, names: Sequence[str]) -> Person | Answer:
        wanted = scoped(names, self.config.known)

        try:
            issuer = self.run(self.discover(request))
            claims = self.verifier(request, issuer).authenticate(request.method, request.url, request.headers)

            return self._granted(request, claims, wanted)
        except (InvalidToken, Forbidden, Unavailable) as error:
            return self._token_refusal(request, error)
        except (Error, httpx.HTTPError) as error:
            return self._token_refusal(request, Unavailable(str(error)))

    async def aprotect(self, request: Incoming, names: Sequence[str]) -> Person | Answer:
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
    ) -> Person | Answer:
        if tokens and self.by_token(request, session):
            return self.protect(request, names)

        return self.answer(self.session_check(request, session, names))

    async def aauthorize(
        self, request: Incoming, session: Session, names: Sequence[str], tokens: bool = False
    ) -> Person | Answer:
        if tokens and self.by_token(request, session):
            return await self.aprotect(request, names)

        return await self.aanswer(self.session_check(request, session, names))

    def run(self, flow: Flow[T]) -> T:
        return run(flow, self.http)

    async def arun(self, flow: Flow[T]) -> T:
        return await arun(flow, self.async_http)

    def answer(self, flow: Flow[T]) -> T | Answer:
        try:
            return self.run(flow)
        except Refusal as refusal:
            return refusal.answer
        except (Unavailable, httpx.HTTPError, Error):
            return unreachable()

    async def aanswer(self, flow: Flow[T]) -> T | Answer:
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

    def handlers(self) -> dict[str, Callable[[Incoming, Session], Flow[Answer]]]:
        return {
            "start": self.start,
            "callback": self.callback,
            "logout": self.logout,
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
            (self.path("/logout/backchannel"), ("POST",), "backchannel"),
            (self.path("/handshake"), ("GET",), "handshake"),
            (self.path("/handshake"), ("POST",), "handshake_begin"),
            (self.path("/handshake"), ("DELETE",), "handshake_disconnect"),
            (self.path("/handshake/disconnect"), ("POST",), "handshake_disconnect"),
            (self.path("/handshake/callback"), ("GET",), "handshake_callback"),
        ]


def unreachable() -> Answer:
    return Answer.page(503, "masks could not be reached", "Try again in a moment.")
