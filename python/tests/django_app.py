from __future__ import annotations

from typing import Any

from django.http import HttpRequest, JsonResponse
from django.urls import include, path

import masks
from masks.django import finish_delegation, login_required, start_delegation, token_required

from .scenarios import connection


@login_required()
def me(request: HttpRequest) -> Any:
    return JsonResponse(request.masked.to_dict())


@login_required("admin")
def admin(request: HttpRequest) -> Any:
    return JsonResponse({"privileges": request.masked.privileges})


@login_required("billing")
def billing(request: HttpRequest) -> Any:
    held = request.masked.organization

    return JsonResponse({"role": held.role if held else None})


def public(request: HttpRequest) -> Any:
    sent = JsonResponse({"signed_in": request.masked.signed_in})
    sent["Cache-Control"] = "public, max-age=600"

    return sent


def plain(request: HttpRequest) -> Any:
    return JsonResponse({"plain": True})


def connect(request: HttpRequest) -> Any:
    return start_delegation(request, request.GET["provider"])


def connected(request: HttpRequest) -> Any:
    try:
        return JsonResponse(connection(finish_delegation(request)))
    except masks.DelegationRefused as error:
        return JsonResponse({"error": error.code}, status=400)


@token_required("read")
def catalog(request: HttpRequest) -> Any:
    return JsonResponse({"subject": request.masked.subject})


urlpatterns = [
    path("", include("masks.django.urls")),
    path("me", me),
    path("admin", admin),
    path("billing", billing),
    path("public", public),
    path("plain", plain),
    path("connect", connect),
    path("connected", connected),
    path("api/catalog", catalog),
]
