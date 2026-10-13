from __future__ import annotations

from collections.abc import Awaitable, Callable, Sequence
from urllib.parse import parse_qsl

import httpx
from fastapi import APIRouter, FastAPI
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from .client import AsyncClient
from .errors import MasksError
from .web.config import Config
from .web.core import FORM_LIMIT, METADATA_PATH, Answer, Incoming, Refusal, cookie_named, too_large, unshared
from .web.core import Masks as Engine
from .web.person import Person
from .web.sessions import Session

SESSION = "masks.session"

__all__ = ["Config", "Masks", "Person", "Refusal", "SessionMiddleware"]


def cookie_from(scope: Scope, name: str) -> str | None:
    for key, value in scope.get("headers") or []:
        if key == b"cookie":
            found = cookie_named(value.decode("latin-1"), name)

            if found is not None:
                return found

    return None


class SessionMiddleware:
    def __init__(self, app: ASGIApp, masks: Masks) -> None:
        self.app = app
        self.engine = masks.engine

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return

        session = await self.engine.aload(cookie_from(scope, self.engine.cookie_name))
        scope[SESSION] = session
        secure = scope.get("scheme") in ("https", "wss")

        async def sending(message: Message) -> None:
            if message["type"] == "http.response.start":
                header = await self.engine.acookie(session, secure)

                if header is not None:
                    held = list(message.get("headers") or [])
                    cached = b", ".join(value for name, value in held if name.lower() == b"cache-control")
                    message["headers"] = [
                        *(pair for pair in held if pair[0].lower() != b"cache-control"),
                        (b"cache-control", unshared(cached.decode("latin-1")).encode("latin-1")),
                        (b"set-cookie", header.encode("latin-1")),
                    ]

            await send(message)

        await self.app(scope, receive, sending)


def session_of(request: Request) -> Session:
    found = request.scope.get(SESSION)

    if not isinstance(found, Session):
        raise RuntimeError("masks: add masks.fastapi.SessionMiddleware, or call Masks.install, before using sessions")

    return found


async def bounded_body(request: Request) -> bytes:
    body = bytearray()

    async for chunk in request.stream():
        body += chunk

        if len(body) > FORM_LIMIT:
            raise Refusal(too_large())

    return bytes(body)


async def incoming(request: Request, form: bool = False) -> Incoming:
    query = {key: request.query_params.getlist(key)[0] for key in request.query_params}
    held: dict[str, str] = {}

    if form and request.headers.get("content-type", "").startswith("application/x-www-form-urlencoded"):
        held = dict(parse_qsl((await bounded_body(request)).decode("utf-8", "replace"), keep_blank_values=True))

    return Incoming(
        method=request.method,
        url=str(request.url),
        headers=httpx.Headers(request.headers.raw),
        query=query,
        form=held,
        native=request,
    )


def response(answer: Answer) -> Response:
    sent = Response(content=answer.body, status_code=answer.status, media_type=answer.content_type or None)

    for name, value in answer.headers:
        sent.headers.append(name, value)

    return sent


async def refused(_: Request, error: Exception) -> Response:
    assert isinstance(error, Refusal)

    return response(error.answer)


class Masks:
    def __init__(self, config: Config) -> None:
        self.engine = Engine(config)
        self.config = config

    def install(self, app: FastAPI) -> None:
        app.add_middleware(SessionMiddleware, masks=self)
        app.add_exception_handler(Refusal, refused)
        app.include_router(self.router)

    @property
    def router(self) -> APIRouter:
        router = APIRouter()

        for path, methods, name in self.engine.routes():
            router.add_api_route(
                path, self.endpoint(name), methods=list(methods), include_in_schema=False, name=f"masks_{name}"
            )

        router.add_api_route(
            METADATA_PATH, self.metadata, methods=["GET"], include_in_schema=False, name="masks_metadata"
        )

        return router

    def endpoint(self, name: str) -> Callable[[Request], Awaitable[Response]]:
        async def answer(request: Request) -> Response:
            if name == "backchannel":
                try:
                    held = await incoming(request, form=True)
                except Refusal as refusal:
                    return response(refusal.answer)

                found = await self.engine.aanswer(self.engine.backchannel(held))
            else:
                held = await incoming(request)
                found = await self.engine.aanswer(self.engine.handlers()[name](held, session_of(request)))

            return response(found)

        return answer

    async def metadata(self, request: Request) -> Response:
        return JSONResponse(self.engine.metadata(await incoming(request)), headers={"Cache-Control": "max-age=300"})

    async def person(self, request: Request) -> Person:
        held = await incoming(request)
        found = await self.engine.aanswer(self.engine.person(held, session_of(request)))

        return found if isinstance(found, Person) else Person(known=self.config.known)

    async def authorize(self, request: Request, *privileges: str, tokens: bool = False) -> Person:
        held = await incoming(request)
        session = self._session(request, tokens)
        found = await self.engine.aauthorize(held, session, privileges, tokens=tokens)

        if isinstance(found, Answer):
            raise Refusal(found)

        return found

    def _session(self, request: Request, tokens: bool) -> Session:
        found = request.scope.get(SESSION)

        if isinstance(found, Session):
            return found

        return Session() if tokens else session_of(request)

    async def protected(self, request: Request, *privileges: str) -> Person:
        found = await self.engine.aprotect(await incoming(request), privileges)

        if isinstance(found, Answer):
            raise Refusal(found)

        return found

    def require(self, *privileges: str, tokens: bool = False) -> Callable[[Request], Awaitable[Person]]:
        self._known(privileges)

        async def requiring(request: Request) -> Person:
            return await self.authorize(request, *privileges, tokens=tokens)

        return requiring

    def protect(self, *privileges: str) -> Callable[[Request], Awaitable[Person]]:
        self._known(privileges)

        async def protecting(request: Request) -> Person:
            return await self.protected(request, *privileges)

        return protecting

    def _known(self, privileges: Sequence[str]) -> None:
        unknown = [name for name in privileges if name not in self.config.known]

        if unknown:
            raise ValueError(f"masks: no privilege is named {', '.join(unknown)}")

    async def client(self, request: Request) -> AsyncClient:
        held = await incoming(request)

        try:
            issuer = await self.engine.arun(self.engine.discover(held))

            return self.engine.async_client(held, issuer)
        except Refusal:
            raise
        except (MasksError, httpx.HTTPError) as error:
            raise Refusal(Answer.page(503, "masks could not be reached", str(error))) from error

    def login_url(self, return_to: str = "", organization: str = "", privilege: Sequence[str] = ()) -> str:
        return self.engine.login_url(return_to, organization, privilege)

    def logout_url(self) -> str:
        return self.engine.path("/logout")

    async def registered(self, request: Request) -> bool:
        return await self.engine.arun(self.engine.registered(await incoming(request)))

    def session(self, request: Request) -> Session:
        return session_of(request)

    def connected(self, request: Request) -> bool:
        return self.engine.configured(Incoming("GET", str(request.url), httpx.Headers(), native=request))

    async def aclose(self) -> None:
        await self.engine.async_http.aclose()
