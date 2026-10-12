from __future__ import annotations

import json
import time
from base64 import b64encode
from collections.abc import Callable, Sequence
from typing import Any
from urllib.parse import quote, quote_plus, urlencode

import anyio
import httpx

from .auth import Auth
from .dpop import proof
from .errors import Error, has_code
from .flows import (
    Flow,
    arun,
    decoded,
    default_async_http,
    default_http,
    run,
    same_origin,
    send_json,
)
from .keys import Key, random_id
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
from .sources import AsyncCachedTokenSource, AsyncTokenSource, CachedTokenSource, TokenSource

ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
ASSERTION_LIFETIME = 60
DEVICE_PAUSE = 5.0

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
