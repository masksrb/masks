from __future__ import annotations

from collections.abc import Callable

from django.http import HttpRequest, HttpResponse
from django.utils.functional import SimpleLazyObject

from ..web.core import Refusal, unshared
from ..web.sessions import Session
from . import actor, engine, response


class MasksMiddleware:
    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        held = engine()
        request.masks_cookie = request.META.get("HTTP_COOKIE", "")
        request.masked = SimpleLazyObject(lambda: actor(request))
        sent = self.get_response(request)
        session = getattr(request, "masks_session", None)
        written = held.seal(session, request.is_secure()) if isinstance(session, Session) else []

        if written:
            sent["Cache-Control"] = unshared(sent.get("Cache-Control", ""))

        for sealed in written:
            sent.set_cookie(
                sealed.name,
                sealed.value,
                max_age=sealed.max_age,
                path="/",
                secure=sealed.secure,
                httponly=True,
                samesite="Lax",
            )

        return sent

    def process_exception(self, request: HttpRequest, exception: Exception) -> HttpResponse | None:
        if isinstance(exception, Refusal):
            return response(exception.answer)

        return None
