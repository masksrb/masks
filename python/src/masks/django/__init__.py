from __future__ import annotations

import functools
import threading
from collections.abc import Callable, Sequence
from typing import Any, TypeVar, cast

import httpx
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.http import HttpRequest, HttpResponse

from ..client import Client
from ..errors import MasksError
from ..oidc import HeldConnection
from ..web.config import Config
from ..web.core import Answer, Incoming, Refusal
from ..web.core import Masks as Engine
from ..web.person import Person
from ..web.sessions import Session

F = TypeVar("F", bound=Callable[..., Any])

__all__ = [
    "Config",
    "Person",
    "client",
    "connected",
    "engine",
    "finish_delegation",
    "login_required",
    "login_url",
    "person",
    "registered",
    "start_delegation",
    "token_required",
]

_built: dict[str, Any] = {"source": None, "engine": None}
_lock = threading.Lock()


def engine() -> Engine:
    source = getattr(settings, "MASKS", None)

    if source is None:
        raise ImproperlyConfigured("masks: set MASKS in your settings to a masks.web.Config or a dict of its options")

    with _lock:
        if _built["source"] is not source:
            config = source if isinstance(source, Config) else Config(**{"secret": settings.SECRET_KEY, **source})

            if getattr(config.backend, "asynchronous", False):
                raise ImproperlyConfigured("masks: an async session store needs an async framework, such as FastAPI")

            _built["source"] = source
            _built["engine"] = Engine(config)

        return cast(Engine, _built["engine"])


def incoming(request: HttpRequest) -> Incoming:
    return Incoming(
        method=str(request.method),
        url=request.build_absolute_uri(),
        headers=httpx.Headers({str(key): str(value) for key, value in request.headers.items()}),
        query={str(key): str(request.GET.getlist(key)[0]) for key in request.GET},
        form={str(key): str(request.POST.getlist(key)[0]) for key in request.POST} if request.method == "POST" else {},
        native=request,
    )


def response(answer: Answer) -> HttpResponse:
    sent = HttpResponse(answer.body, status=answer.status, content_type=answer.content_type or None)
    joined: dict[str, list[str]] = {}

    for name, value in answer.headers:
        joined.setdefault(name, []).append(value)

    for name, values in joined.items():
        sent[name] = ", ".join(values)

    return sent


def session_of(request: HttpRequest) -> Session:
    found = getattr(request, "masks_session", None)

    if isinstance(found, Session):
        return found

    if not hasattr(request, "masks_cookie"):
        raise ImproperlyConfigured("masks: add masks.django.middleware.MasksMiddleware to MIDDLEWARE")

    found = engine().load(request.masks_cookie)
    request.masks_session = found

    return found


def person(request: HttpRequest) -> Person:
    held = getattr(request, "_masks_person", None)

    if isinstance(held, Person):
        return held

    found = engine().answer(engine().person(incoming(request), session_of(request)))
    held = found if isinstance(found, Person) else Person(known=engine().config.known)
    request._masks_person = held

    return held


def _guard(request: HttpRequest, privileges: Sequence[str], tokens: bool, only_tokens: bool) -> HttpResponse | None:
    held = engine()

    if only_tokens:
        found = held.protect(incoming(request), privileges)
    else:
        session = Session() if tokens and not hasattr(request, "masks_cookie") else session_of(request)
        found = held.authorize(incoming(request), session, privileges, tokens=tokens)

    if isinstance(found, Answer):
        return response(found)

    request._masks_person = found
    request.masked = found

    return None


def login_required(*privileges: str, tokens: bool = False) -> Callable[[F], F]:
    def decorate(view: F) -> F:
        @functools.wraps(view)
        def guarded(request: HttpRequest, *args: Any, **kwargs: Any) -> Any:
            return _guard(request, privileges, tokens, False) or view(request, *args, **kwargs)

        return cast(F, guarded)

    return decorate


def token_required(*privileges: str) -> Callable[[F], F]:
    def decorate(view: F) -> F:
        @functools.wraps(view)
        def guarded(request: HttpRequest, *args: Any, **kwargs: Any) -> Any:
            return _guard(request, privileges, True, True) or view(request, *args, **kwargs)

        return cast(F, guarded)

    return decorate


def client(request: HttpRequest) -> Client:
    held = incoming(request)

    try:
        issuer = engine().run(engine().discover(held))
    except (MasksError, httpx.HTTPError) as error:
        raise Refusal(Answer.page(503, "masks could not be reached", str(error))) from error

    return engine().client(held, issuer)


def start_delegation(
    request: HttpRequest, provider: str, *, prompt: str | None = None, max_age: int | None = None
) -> HttpResponse:
    flow = engine().start_delegation(incoming(request), session_of(request), provider, prompt, max_age)

    return response(engine().answer(flow))


def finish_delegation(request: HttpRequest) -> HeldConnection:
    return engine().run(engine().finish_delegation(incoming(request), session_of(request)))


def connected(request: HttpRequest) -> bool:
    return engine().configured(incoming(request))


def registered(request: HttpRequest) -> bool:
    return engine().run(engine().registered(incoming(request)))


def login_url(return_to: str = "", organization: str = "", privilege: Sequence[str] = ()) -> str:
    return engine().login_url(return_to, organization, privilege)
