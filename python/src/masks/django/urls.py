from __future__ import annotations

from collections.abc import Callable
from typing import Any

from django.http import HttpRequest, HttpResponse, JsonResponse
from django.urls import path
from django.views.decorators.csrf import csrf_exempt

from ..web.core import FORM_LIMIT, FORM_ROUTES, METADATA_PATH, too_large
from . import engine, incoming, response, session_of


def dispatching(methods: dict[str, str]) -> Callable[[HttpRequest], HttpResponse]:
    def view(request: HttpRequest) -> HttpResponse:
        name = methods.get(str(request.method))

        if name is None:
            refused = HttpResponse(status=405)
            refused["Allow"] = ", ".join(sorted(methods))

            return refused

        held = engine()

        if name in FORM_ROUTES and int(request.META.get("CONTENT_LENGTH") or 0) > FORM_LIMIT:
            return response(too_large())

        found = incoming(request, form=name in FORM_ROUTES)

        if name == "backchannel":
            return response(held.answer(held.backchannel(found)))

        return response(held.answer(held.handlers()[name](found, session_of(request))))

    return view


def metadata(request: HttpRequest) -> HttpResponse:
    sent = JsonResponse(engine().metadata(incoming(request)))
    sent["Cache-Control"] = "max-age=300"

    return sent


def patterns() -> list[Any]:
    grouped: dict[str, dict[str, str]] = {}

    for route, verbs, name in engine().routes():
        for verb in verbs:
            grouped.setdefault(route, {})[verb] = name

    found = []

    for route, methods in grouped.items():
        view = csrf_exempt(dispatching(methods))
        found.append(path(route.lstrip("/"), view, name=f"masks_{route.strip('/').replace('/', '_') or 'start'}"))

    found.append(path(METADATA_PATH.lstrip("/"), metadata, name="masks_metadata"))

    return found


urlpatterns = patterns()
