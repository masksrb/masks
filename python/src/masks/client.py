from __future__ import annotations

import json
import time
from base64 import b64encode
from collections.abc import Callable, Sequence
from dataclasses import replace
from typing import Any
from urllib.parse import quote, quote_plus, urlencode

import anyio
import httpx

from .auth import Auth
from .dpop import DPOP, proof
from .errors import (
    DelegationRefused,
    DelegationUnavailable,
    Error,
    InvalidToken,
    MasksError,
    Unavailable,
    has_code,
)
from .flows import (
    Flow,
    arun,
    decoded,
    default_async_http,
    default_http,
    required,
    run,
    same_origin,
    send_json,
)
from .keys import Key, random_id
from .keyset import KeySet, half_hash, recent, same
from .models import (
    ACCESS_TOKEN_TYPE,
    CLIENT_SECRET_BASIC,
    CLIENT_SECRET_POST,
    GRANT_CLIENT_CREDENTIALS,
    GRANT_DEVICE_CODE,
    GRANT_REFRESH_TOKEN,
    GRANT_TOKEN_EXCHANGE,
    NO_AUTH,
    PRIVATE_KEY_JWT,
    UPSTREAM_ACCESS_TOKEN_TYPE,
    AuthMethod,
    ClientMetadata,
    DeviceAuthorization,
    Enrollment,
    Introspection,
    Issuer,
    Registration,
    Token,
)
from .oidc import (
    CHALLENGE_METHOD,
    DEFAULT_SCOPE,
    DELEGATE_SCOPE,
    LOGOUT_EVENT,
    OPENID,
    AuthorizationRequest,
    HeldConnection,
    Logout,
    SignIn,
    Upstream,
    code_challenge,
    code_verifier,
    flattened,
    organization_key,
)
from .sources import AsyncCachedTokenSource, AsyncTokenSource, CachedTokenSource, TokenSource

ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
ASSERTION_LIFETIME = 60
DEVICE_PAUSE = 5.0
LOGOUT_LEEWAY = 60
DELEGATION_REFUSALS = frozenset(
    {
        "invalid_grant",
        "insufficient_scope",
        "invalid_target",
        "unauthorized_client",
        "access_denied",
        "login_required",
        "interaction_required",
        "consent_required",
        "invalid_scope",
    }
)

Form = list[tuple[str, str]]


def words(value: Sequence[str]) -> list[str]:
    return value.split() if isinstance(value, str) else [str(item) for item in value]


def asked(scope: Sequence[str] = (), resource: Sequence[str] = ()) -> Form:
    form: Form = []
    named = words(scope)

    if named:
        form.append(("scope", " ".join(named)))

    form.extend(("resource", value) for value in words(resource))

    return form


def seconds(value: int | None, named: str) -> list[tuple[str, str]]:
    if value is None:
        return []

    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"masks: {named} is a whole number of seconds above zero")

    return [(named, str(value))]


def asks_for_nonce(response: httpx.Response) -> bool:
    if "use_dpop_nonce" in response.headers.get("WWW-Authenticate", ""):
        return True

    try:
        body = json.loads(response.content)
    except ValueError:
        return False

    return isinstance(body, dict) and body.get("error") == "use_dpop_nonce"


class _Flows:
    def __init__(
        self,
        issuer: Issuer,
        client_id: str,
        *,
        secret: str | None = None,
        method: AuthMethod | None = None,
        key: Key | None = None,
        dpop: Key | None = None,
    ) -> None:
        if not client_id:
            raise ValueError("masks: a client needs its client_id")

        self.issuer = issuer
        self.client_id = client_id
        self.secret = secret
        self.key = key
        self.dpop = dpop
        self.method: AuthMethod = method or (
            CLIENT_SECRET_BASIC if secret else PRIVATE_KEY_JWT if key is not None else NO_AUTH
        )
        self.keys = KeySet(issuer)

    def start(
        self,
        redirect_uri: str,
        *,
        scope: Sequence[str] = DEFAULT_SCOPE,
        resource: Sequence[str] = (),
        state: str | None = None,
        nonce: str | None = None,
        prompt: str | None = None,
        max_age: int | None = None,
        organization: str | None = None,
    ) -> AuthorizationRequest:
        if not redirect_uri:
            raise ValueError("masks: a sign-in needs the redirect_uri masks sends the browser back to")

        scopes = words(scope)
        resources = words(resource)
        verifier = code_verifier()
        state = state or random_id()
        nonce = (nonce or random_id()) if OPENID in scopes else ""
        pairs: Form = [
            ("response_type", "code"),
            ("client_id", self.client_id),
            ("redirect_uri", redirect_uri),
            ("scope", " ".join(scopes)),
            ("state", state),
            ("code_challenge", code_challenge(verifier)),
            ("code_challenge_method", CHALLENGE_METHOD),
        ]

        if nonce:
            pairs.append(("nonce", nonce))

        pairs.extend(("resource", value) for value in resources)

        if prompt:
            pairs.append(("prompt", prompt))

        pairs += seconds(max_age, "max_age") if max_age else []
        named = organization_key(organization)

        if named:
            pairs.append(("organization", named))

        if self.dpop is not None:
            pairs.append(("dpop_jkt", self.dpop.thumbprint))

        return AuthorizationRequest(
            url=f"{self._endpoint('authorization_endpoint')}?{urlencode(pairs)}",
            state=state,
            redirect_uri=redirect_uri,
            verifier=verifier,
            nonce=nonce,
            scope=" ".join(scopes),
            resource=tuple(resources),
            max_age=int(max_age) if max_age else 0,
        )

    def start_delegation(
        self, provider: str, redirect_uri: str, *, prompt: str | None = None, max_age: int | None = None
    ) -> AuthorizationRequest:
        if not provider or any(character.isspace() for character in provider):
            raise ValueError("masks: a delegation names one provider")

        started = self.start(
            redirect_uri,
            scope=[OPENID, "offline_access", f"{DELEGATE_SCOPE}{provider}"],
            prompt=prompt,
            max_age=max_age,
        )

        return replace(started, provider=provider)

    def end_session_url(self, *, post_logout_redirect_uri: str = "", state: str = "", id_token_hint: str = "") -> str:
        pairs: Form = [("client_id", self.client_id)]

        if id_token_hint:
            pairs.append(("id_token_hint", id_token_hint))

        if post_logout_redirect_uri:
            pairs.append(("post_logout_redirect_uri", post_logout_redirect_uri))

        if state:
            pairs.append(("state", state))

        return f"{self._endpoint('end_session_endpoint')}?{urlencode(pairs)}"

    def _endpoint(self, named: str) -> str:
        value = str(getattr(self.issuer.metadata, named))

        if not value:
            raise Error("invalid_issuer", f"{self.issuer.url} publishes no {named}")

        return value

    def _authenticated(self, form: Form) -> tuple[Form, dict[str, str]]:
        held = list(form)
        headers: dict[str, str] = {}

        if self.method == CLIENT_SECRET_BASIC:
            pair = f"{quote_plus(self.client_id, safe='')}:{quote_plus(self.secret or '', safe='')}"
            headers["Authorization"] = "Basic " + b64encode(pair.encode()).decode()
        elif self.method == CLIENT_SECRET_POST:
            held += [("client_id", self.client_id), ("client_secret", self.secret or "")]
        elif self.method == PRIVATE_KEY_JWT:
            if self.key is None:
                raise ValueError("masks: private_key_jwt needs the client's key")

            now = int(time.time())
            assertion = self.key.sign(
                "JWT",
                {
                    "iss": self.client_id,
                    "sub": self.client_id,
                    "aud": self.issuer.url,
                    "jti": random_id(),
                    "iat": now,
                    "exp": now + ASSERTION_LIFETIME,
                },
                embed=False,
            )
            held += [
                ("client_id", self.client_id),
                ("client_assertion_type", ASSERTION_TYPE),
                ("client_assertion", assertion),
            ]
        elif self.method == NO_AUTH:
            held.append(("client_id", self.client_id))
        else:
            raise ValueError(f"masks: {self.method!r} is not a way a client authenticates")

        return held, headers

    def _request(self, method: str, endpoint: str, form: Form, proven: bool, nonce: str) -> httpx.Request:
        held, headers = self._authenticated(form)
        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/x-www-form-urlencoded"

        if proven and self.dpop is not None:
            headers["DPoP"] = proof(self.dpop, method, endpoint, nonce=nonce)

        return httpx.Request(method, endpoint, headers=headers, content=urlencode(held).encode())

    def _post(self, endpoint: str, form: Form, proven: bool) -> Flow[dict[str, Any] | None]:
        return self._send("POST", endpoint, form, proven)

    def _send(self, method: str, endpoint: str, form: Form, proven: bool) -> Flow[dict[str, Any] | None]:
        nonce = ""

        for attempt in (0, 1):
            response = yield self._request(method, endpoint, form, proven, nonce)
            wanted = response.headers.get("DPoP-Nonce", "")

            if (
                proven
                and self.dpop is not None
                and attempt == 0
                and wanted
                and response.status_code >= 400
                and asks_for_nonce(response)
            ):
                nonce = wanted
                continue

            return decoded(response)

        raise AssertionError("unreachable")

    def _token(self, form: Form, held: bool = True) -> Flow[Token]:
        body = yield from self._post(self._endpoint("token_endpoint"), form, True)

        if not body or not body.get("access_token"):
            raise Error("server_error", "the token endpoint answered without an access token")

        token = Token.from_dict(body)

        if held and self.dpop is not None and not token.bound:
            raise Error("invalid_dpop_proof", "the token endpoint answered with a token that is not held to this key")

        return token

    def _client_credentials(self, scope: Sequence[str], resource: Sequence[str]) -> Flow[Token]:
        return self._token([("grant_type", GRANT_CLIENT_CREDENTIALS), *asked(scope, resource)])

    def _refresh(self, refresh_token: str, scope: Sequence[str], resource: Sequence[str]) -> Flow[Token]:
        return self._token(
            [("grant_type", GRANT_REFRESH_TOKEN), ("refresh_token", refresh_token), *asked(scope, resource)]
        )

    def _device_token(self, device: DeviceAuthorization) -> Flow[Token]:
        return self._token([("grant_type", GRANT_DEVICE_CODE), ("device_code", device.device_code)])

    def _device_authorization(self, scope: Sequence[str], resource: Sequence[str]) -> Flow[DeviceAuthorization]:
        endpoint = self._endpoint("device_authorization_endpoint")
        body = yield from self._post(endpoint, [*asked(scope, resource), ("client_id", self.client_id)], False)

        if not body:
            raise Error("server_error", "the device authorization endpoint answered with nothing")

        return DeviceAuthorization.from_dict(body)

    def _revoke(self, token: str, hint: str) -> Flow[None]:
        form: Form = [("token", token)]

        if hint:
            form.append(("token_type_hint", hint))

        yield from self._post(self._endpoint("revocation_endpoint"), form, False)

    def _complete(self, started: AuthorizationRequest, params: Any) -> Flow[SignIn]:
        held = flattened(params)

        if held.get("error"):
            raise Error(held["error"], held.get("error_description", ""))

        if not started.state or not same(held.get("state"), started.state):
            raise Error("invalid_state", "that answer is for a sign-in this browser did not start")

        named = held.get("iss", "")

        if named and named.rstrip("/") != self.issuer.url:
            raise Error("invalid_issuer", f"that answer came from {named}, not {self.issuer.url}")

        if not named and self.issuer.metadata.authorization_response_iss_parameter_supported:
            raise Error("invalid_issuer", "that answer does not name the issuer it came from")

        if not held.get("code"):
            raise Error("invalid_request", "that answer carries no code")

        token = yield from self._token(
            [
                ("grant_type", "authorization_code"),
                ("code", held["code"]),
                ("redirect_uri", started.redirect_uri),
                ("code_verifier", started.verifier),
                *asked((), started.resource),
            ]
        )
        claims: dict[str, Any] = {}

        if OPENID in started.scopes:
            if not token.id_token:
                raise InvalidToken("masks: the token endpoint answered without an ID token")

            claims = yield from self._id_token(
                token.id_token, started.nonce, token.access_token, max_age=started.max_age
            )

        return SignIn(token=token, claims=claims)

    def _id_token(self, id_token: str, nonce: str, access_token: str, *, max_age: int = 0) -> Flow[dict[str, Any]]:
        claims, algorithm = yield from self.keys.verify(
            id_token, accepted=("jwt", ""), audience=self.client_id, require=("iss", "sub", "aud", "exp", "iat")
        )
        audience = claims["aud"]

        if isinstance(audience, list) and len(audience) > 1 and claims.get("azp") != self.client_id:
            raise InvalidToken("masks: that ID token was issued to several clients and names another")

        if nonce and not same(claims.get("nonce"), nonce):
            raise InvalidToken("masks: that ID token was issued for another sign-in")

        if "at_hash" in claims and not same(claims["at_hash"], half_hash(access_token, algorithm)):
            raise InvalidToken("masks: that ID token was issued with another access token")

        if max_age > 0 and not recent(claims.get("auth_time"), max_age):
            raise InvalidToken("masks: the person signed in longer ago than max_age allows")

        return claims

    def _userinfo(self, token: Token | str) -> Flow[dict[str, Any]]:
        held = token if isinstance(token, Token) else Token(access_token=token)
        endpoint = self._endpoint("userinfo_endpoint")
        nonce = ""

        for attempt in (0, 1):
            headers = {"Accept": "application/json"}

            if held.bound:
                if self.dpop is None:
                    raise ValueError("masks: a DPoP token needs the key it is held to")

                headers["Authorization"] = f"{DPOP} {held.access_token}"
                headers["DPoP"] = proof(self.dpop, "GET", endpoint, held.access_token, nonce)
            else:
                headers["Authorization"] = f"Bearer {held.access_token}"

            response = yield httpx.Request("GET", endpoint, headers=headers)
            wanted = response.headers.get("DPoP-Nonce", "")

            if held.bound and attempt == 0 and wanted and response.status_code == 401 and asks_for_nonce(response):
                nonce = wanted
                continue

            return required(response)

        raise AssertionError("unreachable")

    def _logout(self, logout_token: str) -> Flow[Logout]:
        claims, _ = yield from self.keys.verify(
            logout_token, accepted=("logout+jwt",), audience=self.client_id, require=("iss", "aud", "iat", "exp", "jti")
        )
        events = claims.get("events")

        if "nonce" in claims:
            raise InvalidToken("masks: that logout token carries a nonce, so it is an ID token")

        if not claims.get("sub") and not claims.get("sid"):
            raise InvalidToken("masks: that logout token names neither a subject nor a session")

        if not isinstance(claims["iat"], (int, float)) or claims["iat"] > time.time() + LOGOUT_LEEWAY:
            raise InvalidToken("masks: that logout token was issued in the future")

        if not isinstance(events, dict) or not isinstance(events.get(LOGOUT_EVENT), dict):
            raise InvalidToken("masks: that token is not about a logout")

        return Logout(
            subject=str(claims.get("sub") or ""),
            sid=str(claims.get("sid") or ""),
            id=str(claims["jti"]),
            issued_at=int(claims["iat"]),
            raw=claims,
        )

    def _finish_delegation(self, started: AuthorizationRequest, params: Any) -> Flow[HeldConnection]:
        if not started.provider:
            raise ValueError("masks: that request did not start a delegation")

        signed = yield from self._complete(started, params)
        held = next((item for item in signed.token.delegations or [] if item.get("provider") == started.provider), None)

        if held is None:
            raise DelegationRefused("access_denied", f"masks connected nothing for {started.provider}")

        if not signed.token.refresh_token:
            raise DelegationRefused("invalid_grant", "masks issued no refresh token to keep the connection with")

        return HeldConnection(
            connection=str(held.get("connection") or ""),
            provider=str(held.get("provider") or ""),
            provider_name=str(held.get("provider_name") or ""),
            label=str(held.get("label") or ""),
            subject=str(held.get("subject") or ""),
            secret=signed.token.refresh_token,
            account=str(signed.claims.get("sub") or ""),
        )

    def _delegated_token(self, secret: str, connection: str, rotated: list[str]) -> Flow[Upstream]:
        if not secret or not connection:
            raise ValueError("masks: an upstream token needs the connection's secret and id")

        refreshed = yield from self._refresh(secret, (), ())
        rotated[0] = refreshed.refresh_token or secret
        released = yield from self._exchange(
            refreshed.access_token, ACCESS_TOKEN_TYPE, "", "", UPSTREAM_ACCESS_TOKEN_TYPE, [connection], (), None, ()
        )

        return Upstream(
            access_token=released.access_token,
            expires_at=released.expires_at,
            scope=released.scope,
            secret=rotated[0],
        )

    def _introspect(self, token: str, hint: str) -> Flow[Introspection]:
        if not token:
            raise ValueError("masks: introspection needs the token to look up")

        form: Form = [("token", token)]

        if hint:
            form.append(("token_type_hint", hint))

        body = yield from self._post(self._endpoint("introspection_endpoint"), form, False)

        if not body:
            raise Error("server_error", "the introspection endpoint answered with nothing")

        found = Introspection.from_dict(body)

        if found.active and found.issuer.rstrip("/") != self.issuer.url:
            raise Error("invalid_issuer", f"the introspection endpoint describes a token from {found.issuer!r}")

        return found

    def _exchange(
        self,
        subject_token: str,
        subject_token_type: str,
        actor_token: str,
        actor_token_type: str,
        requested_token_type: str,
        audience: Sequence[str],
        scope: Sequence[str],
        requested_lifetime: int | None,
        resource: Sequence[str],
    ) -> Flow[Token]:
        if not subject_token or not subject_token_type:
            raise ValueError("masks: an exchange needs the subject token and its type")

        form: Form = [
            ("grant_type", GRANT_TOKEN_EXCHANGE),
            ("subject_token", subject_token),
            ("subject_token_type", subject_token_type),
        ]

        if actor_token:
            form += [("actor_token", actor_token), ("actor_token_type", actor_token_type or ACCESS_TOKEN_TYPE)]

        if requested_token_type:
            form.append(("requested_token_type", requested_token_type))

        form.extend(("audience", value) for value in words(audience))
        form += seconds(requested_lifetime, "requested_lifetime")
        form += asked(scope, resource)

        return self._token(form, requested_token_type != UPSTREAM_ACCESS_TOKEN_TYPE)

    def _enroll(self, scope: Sequence[str], client_name: str | None, expires_in: int | None) -> Flow[Enrollment]:
        named = words(scope)

        if not named:
            raise ValueError("masks: an enrollment names the scopes its machine is approved for")

        form: Form = [("scope", " ".join(named))]

        if client_name:
            form.append(("client_name", client_name))

        form += seconds(expires_in, "expires_in")

        body = yield from self._post(self._endpoint("enrollment_endpoint"), form, False)

        if not body or not body.get("initial_access_token"):
            raise Error("server_error", "the enrollment endpoint answered without an initial access token")

        return Enrollment.from_dict(body)

    def _unenroll(self, client_id: str) -> Flow[None]:
        if not client_id or client_id in (".", ".."):
            raise ValueError("masks: unenrolling names the machine's client_id")

        target = f"{self._endpoint('enrollment_endpoint').rstrip('/')}/{quote(client_id, safe='')}"

        yield from self._send("DELETE", target, [], False)

    def _read_registration(self, held: Registration) -> Flow[Registration]:
        owned(self.issuer, held)
        body = decoded(
            (yield send_json("GET", held.registration_client_uri or "", held.registration_access_token or "", None))
        )

        return Registration.from_dict(body or {}).kept_from(held)

    def _update_registration(self, held: Registration, metadata: ClientMetadata) -> Flow[Registration]:
        owned(self.issuer, held)
        body = decoded(
            (
                yield send_json(
                    "PUT", held.registration_client_uri or "", held.registration_access_token or "", metadata.to_dict()
                )
            )
        )

        return Registration.from_dict(body or {}).kept_from(held)

    def _delete_registration(self, held: Registration) -> Flow[None]:
        owned(self.issuer, held)
        decoded(
            (yield send_json("DELETE", held.registration_client_uri or "", held.registration_access_token or "", None))
        )

    @staticmethod
    def _registered(issuer: Issuer, metadata: ClientMetadata, initial_access_token: str) -> Flow[Registration]:
        endpoint = issuer.metadata.registration_endpoint

        if not endpoint and initial_access_token:
            endpoint = issuer.url + "/register"

        if not endpoint:
            raise Error("access_denied", f"{issuer.url} registers no clients without an initial access token")

        body = decoded((yield send_json("POST", endpoint, initial_access_token, metadata.to_dict())))
        held = Registration.from_dict(body or {})
        owned(issuer, held)

        return held

    def _client_kwargs(self) -> dict[str, Any]:
        return {"secret": self.secret, "method": self.method, "key": self.key, "dpop": self.dpop}

    def _pause(self, device: DeviceAuthorization) -> float:
        return max(float(device.interval or 0), DEVICE_PAUSE)


def owned(issuer: Issuer, held: Registration) -> None:
    if not held.client_id:
        raise Error("invalid_client_metadata", "the registration names no client_id")

    if not held.registration_client_uri or not held.registration_access_token:
        raise Error("invalid_client_metadata", "the registration holds no registration_client_uri and token")

    same_origin(issuer, held.registration_client_uri)


def delegation_failure(error: Exception, secret: str) -> Exception:
    if isinstance(error, (DelegationRefused, DelegationUnavailable)):
        return error

    if isinstance(error, Error):
        if error.code == "invalid_client":
            return error

        busy = error.code == "temporarily_unavailable" or (error.status or 0) >= 500 or error.status == 429

        if busy and error.code not in DELEGATION_REFUSALS:
            return DelegationUnavailable(f"masks answered {error.status}: {error}", secret=secret)

        return DelegationRefused(error.code, error.description, status=error.status, secret=secret)

    if isinstance(error, (httpx.HTTPError, Unavailable)):
        return DelegationUnavailable(f"masks: {error}", secret=secret)

    return error


def expired() -> Error:
    return Error("expired_token", "the code expired before anyone approved it")


class Client(_Flows):
    def __init__(self, issuer: Issuer, client_id: str, *, http: httpx.Client | None = None, **options: Any) -> None:
        super().__init__(issuer, client_id, **options)
        self.http = http or default_http()

    @classmethod
    def register(
        cls,
        issuer: Issuer,
        metadata: ClientMetadata | None = None,
        initial_access_token: str = "",
        *,
        http: httpx.Client | None = None,
    ) -> Registration:
        flow = cls._registered(issuer, metadata or ClientMetadata(), initial_access_token)

        if http is None:
            with default_http() as held:
                return run(flow, held)

        return run(flow, http)

    @classmethod
    def from_registration(
        cls,
        issuer: Issuer,
        held: Registration,
        *,
        key: Key | None = None,
        dpop: Key | None = None,
        http: httpx.Client | None = None,
    ) -> Client:
        return cls(
            issuer,
            held.client_id,
            secret=held.client_secret,
            method=held.token_endpoint_auth_method,
            key=key,
            dpop=dpop,
            http=http,
        )

    def client_credentials(self, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> Token:
        return run(self._client_credentials(scope, resource), self.http)

    def refresh(self, refresh_token: str, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> Token:
        return run(self._refresh(refresh_token, scope, resource), self.http)

    def device_authorization(self, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> DeviceAuthorization:
        return run(self._device_authorization(scope, resource), self.http)

    def await_device(self, device: DeviceAuthorization, *, timeout: float | None = None) -> Token:
        interval = self._pause(device)
        deadline = None if timeout is None else time.monotonic() + timeout

        while True:
            if device.expires_at is not None and time.time() > device.expires_at:
                raise expired()

            if deadline is not None and time.monotonic() + interval > deadline:
                raise TimeoutError("masks: nobody approved the code in time")

            time.sleep(interval)

            try:
                return run(self._device_token(device), self.http)
            except Error as error:
                if has_code(error, "authorization_pending"):
                    continue

                if has_code(error, "slow_down"):
                    interval += DEVICE_PAUSE
                    continue

                raise

    def revoke(self, token: str, hint: str = "") -> None:
        run(self._revoke(token, hint), self.http)

    def introspect(self, token: str, hint: str = "") -> Introspection:
        return run(self._introspect(token, hint), self.http)

    def complete(self, started: AuthorizationRequest, params: Any) -> SignIn:
        return run(self._complete(started, params), self.http)

    def verify_id_token(self, id_token: str, *, nonce: str = "", access_token: str = "") -> dict[str, Any]:
        return run(self._id_token(id_token, nonce, access_token), self.http)

    def userinfo(self, token: Token | str) -> dict[str, Any]:
        return run(self._userinfo(token), self.http)

    def verify_logout_token(self, logout_token: str) -> Logout:
        return run(self._logout(logout_token), self.http)

    def finish_delegation(self, started: AuthorizationRequest, params: Any) -> HeldConnection:
        try:
            return run(self._finish_delegation(started, params), self.http)
        except (MasksError, httpx.HTTPError) as error:
            raise delegation_failure(error, "") from error

    def delegated_token(self, secret: str, *, connection: str) -> Upstream:
        rotated = [secret]

        try:
            return run(self._delegated_token(secret, connection, rotated), self.http)
        except (MasksError, httpx.HTTPError) as error:
            raise delegation_failure(error, rotated[0] if rotated[0] != secret else "") from error

    def exchange(
        self,
        subject_token: str,
        *,
        subject_token_type: str = ACCESS_TOKEN_TYPE,
        actor_token: str = "",
        actor_token_type: str = ACCESS_TOKEN_TYPE,
        requested_token_type: str = "",
        audience: Sequence[str] = (),
        scope: Sequence[str] = (),
        requested_lifetime: int | None = None,
        resource: Sequence[str] = (),
    ) -> Token:
        return run(
            self._exchange(
                subject_token,
                subject_token_type,
                actor_token,
                actor_token_type,
                requested_token_type,
                audience,
                scope,
                requested_lifetime,
                resource,
            ),
            self.http,
        )

    def enroll(
        self, *, scope: Sequence[str], client_name: str | None = None, expires_in: int | None = None
    ) -> Enrollment:
        return run(self._enroll(scope, client_name, expires_in), self.http)

    def unenroll(self, client_id: str) -> None:
        run(self._unenroll(client_id), self.http)

    def read_registration(self, held: Registration) -> Registration:
        return run(self._read_registration(held), self.http)

    def update_registration(self, held: Registration, metadata: ClientMetadata) -> Registration:
        return run(self._update_registration(held, metadata), self.http)

    def delete_registration(self, held: Registration) -> None:
        run(self._delete_registration(held), self.http)

    def credentials_source(self, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> CachedTokenSource:
        return CachedTokenSource(lambda: self.client_credentials(scope=scope, resource=resource))

    def refresh_source(
        self,
        token: Token,
        *,
        scope: Sequence[str] = (),
        resource: Sequence[str] = (),
        keep: Callable[[Token], None] | None = None,
    ) -> CachedTokenSource:
        current = [token]

        def renew() -> Token:
            renewed = self.refresh(renewal(current[0]), scope=scope, resource=resource)
            current[0] = rotated(current[0], renewed, keep)
            return current[0]

        return CachedTokenSource(renew, token)

    def auth(self, source: TokenSource, *origins: str) -> Auth:
        return Auth(source, *origins, key=self.dpop)

    def http_client(self, source: TokenSource, *origins: str, **options: Any) -> httpx.Client:
        return httpx.Client(auth=self.auth(source, *origins), **options)

    def close(self) -> None:
        self.http.close()

    def __enter__(self) -> Client:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


class AsyncClient(_Flows):
    def __init__(
        self, issuer: Issuer, client_id: str, *, http: httpx.AsyncClient | None = None, **options: Any
    ) -> None:
        super().__init__(issuer, client_id, **options)
        self.http = http or default_async_http()

    @classmethod
    async def register(
        cls,
        issuer: Issuer,
        metadata: ClientMetadata | None = None,
        initial_access_token: str = "",
        *,
        http: httpx.AsyncClient | None = None,
    ) -> Registration:
        flow = cls._registered(issuer, metadata or ClientMetadata(), initial_access_token)

        if http is None:
            async with default_async_http() as held:
                return await arun(flow, held)

        return await arun(flow, http)

    @classmethod
    def from_registration(
        cls,
        issuer: Issuer,
        held: Registration,
        *,
        key: Key | None = None,
        dpop: Key | None = None,
        http: httpx.AsyncClient | None = None,
    ) -> AsyncClient:
        return cls(
            issuer,
            held.client_id,
            secret=held.client_secret,
            method=held.token_endpoint_auth_method,
            key=key,
            dpop=dpop,
            http=http,
        )

    async def client_credentials(self, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> Token:
        return await arun(self._client_credentials(scope, resource), self.http)

    async def refresh(self, refresh_token: str, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> Token:
        return await arun(self._refresh(refresh_token, scope, resource), self.http)

    async def device_authorization(
        self, *, scope: Sequence[str] = (), resource: Sequence[str] = ()
    ) -> DeviceAuthorization:
        return await arun(self._device_authorization(scope, resource), self.http)

    async def await_device(self, device: DeviceAuthorization) -> Token:
        interval = self._pause(device)

        while True:
            if device.expires_at is not None and time.time() > device.expires_at:
                raise expired()

            await anyio.sleep(interval)

            try:
                return await arun(self._device_token(device), self.http)
            except Error as error:
                if has_code(error, "authorization_pending"):
                    continue

                if has_code(error, "slow_down"):
                    interval += DEVICE_PAUSE
                    continue

                raise

    async def revoke(self, token: str, hint: str = "") -> None:
        await arun(self._revoke(token, hint), self.http)

    async def introspect(self, token: str, hint: str = "") -> Introspection:
        return await arun(self._introspect(token, hint), self.http)

    async def complete(self, started: AuthorizationRequest, params: Any) -> SignIn:
        return await arun(self._complete(started, params), self.http)

    async def verify_id_token(self, id_token: str, *, nonce: str = "", access_token: str = "") -> dict[str, Any]:
        return await arun(self._id_token(id_token, nonce, access_token), self.http)

    async def userinfo(self, token: Token | str) -> dict[str, Any]:
        return await arun(self._userinfo(token), self.http)

    async def verify_logout_token(self, logout_token: str) -> Logout:
        return await arun(self._logout(logout_token), self.http)

    async def finish_delegation(self, started: AuthorizationRequest, params: Any) -> HeldConnection:
        try:
            return await arun(self._finish_delegation(started, params), self.http)
        except (MasksError, httpx.HTTPError) as error:
            raise delegation_failure(error, "") from error

    async def delegated_token(self, secret: str, *, connection: str) -> Upstream:
        rotated = [secret]

        try:
            return await arun(self._delegated_token(secret, connection, rotated), self.http)
        except (MasksError, httpx.HTTPError) as error:
            raise delegation_failure(error, rotated[0] if rotated[0] != secret else "") from error

    async def exchange(
        self,
        subject_token: str,
        *,
        subject_token_type: str = ACCESS_TOKEN_TYPE,
        actor_token: str = "",
        actor_token_type: str = ACCESS_TOKEN_TYPE,
        requested_token_type: str = "",
        audience: Sequence[str] = (),
        scope: Sequence[str] = (),
        requested_lifetime: int | None = None,
        resource: Sequence[str] = (),
    ) -> Token:
        return await arun(
            self._exchange(
                subject_token,
                subject_token_type,
                actor_token,
                actor_token_type,
                requested_token_type,
                audience,
                scope,
                requested_lifetime,
                resource,
            ),
            self.http,
        )

    async def enroll(
        self, *, scope: Sequence[str], client_name: str | None = None, expires_in: int | None = None
    ) -> Enrollment:
        return await arun(self._enroll(scope, client_name, expires_in), self.http)

    async def unenroll(self, client_id: str) -> None:
        await arun(self._unenroll(client_id), self.http)

    async def read_registration(self, held: Registration) -> Registration:
        return await arun(self._read_registration(held), self.http)

    async def update_registration(self, held: Registration, metadata: ClientMetadata) -> Registration:
        return await arun(self._update_registration(held, metadata), self.http)

    async def delete_registration(self, held: Registration) -> None:
        await arun(self._delete_registration(held), self.http)

    def credentials_source(self, *, scope: Sequence[str] = (), resource: Sequence[str] = ()) -> AsyncCachedTokenSource:
        async def fetch() -> Token:
            return await self.client_credentials(scope=scope, resource=resource)

        return AsyncCachedTokenSource(fetch)

    def refresh_source(
        self,
        token: Token,
        *,
        scope: Sequence[str] = (),
        resource: Sequence[str] = (),
        keep: Callable[[Token], None] | None = None,
    ) -> AsyncCachedTokenSource:
        current = [token]

        async def renew() -> Token:
            renewed = await self.refresh(renewal(current[0]), scope=scope, resource=resource)
            current[0] = rotated(current[0], renewed, keep)
            return current[0]

        return AsyncCachedTokenSource(renew, token)

    def auth(self, source: AsyncTokenSource, *origins: str) -> Auth:
        return Auth(source, *origins, key=self.dpop)

    def http_client(self, source: AsyncTokenSource, *origins: str, **options: Any) -> httpx.AsyncClient:
        return httpx.AsyncClient(auth=self.auth(source, *origins), **options)

    async def aclose(self) -> None:
        await self.http.aclose()

    async def __aenter__(self) -> AsyncClient:
        return self

    async def __aexit__(self, *_: object) -> None:
        await self.aclose()


def renewal(token: Token) -> str:
    if not token.refresh_token:
        raise Error("invalid_grant", "there is no refresh token to renew this session with")

    return token.refresh_token


def rotated(held: Token, renewed: Token, keep: Callable[[Token], None] | None) -> Token:
    if not renewed.refresh_token:
        renewed.refresh_token = held.refresh_token

    if keep is not None:
        keep(renewed)

    return renewed
