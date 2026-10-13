from __future__ import annotations

from collections.abc import Callable

from django.http import HttpRequest, HttpResponse
from django.utils.functional import SimpleLazyObject

from ..web.core import Refusal, unshared
from . import engine, person, response


class MasksMiddleware:
    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        held = engine()
        session = held.load(request.COOKIES.get(held.cookie_name))
        request.masks_session = session
        request.masked = SimpleLazyObject(lambda: person(request))
        sent = self.get_response(request)
        sealed = held.seal(session, request.is_secure())

        if sealed is not None:
            sent["Cache-Control"] = unshared(sent.get("Cache-Control", ""))

        if sealed is not None and sealed.value:
            sent.set_cookie(
                sealed.name,
                sealed.value,
                max_age=sealed.max_age,
                path="/",
                secure=sealed.secure,
                httponly=True,
                samesite="Lax",
            )
        elif sealed is not None:
            sent.delete_cookie(sealed.name, path="/", samesite="Lax")

        return sent

    def process_exception(self, request: HttpRequest, exception: Exception) -> HttpResponse | None:
        if isinstance(exception, Refusal):
            return response(exception.answer)

        return None
