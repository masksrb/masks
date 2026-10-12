from __future__ import annotations

from typing import Any

from django.http import HttpRequest, JsonResponse
from django.urls import include, path

from masks.django import login_required, token_required


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


@token_required("read")
def catalog(request: HttpRequest) -> Any:
    return JsonResponse({"subject": request.masked.subject})


urlpatterns = [
    path("", include("masks.django.urls")),
    path("me", me),
    path("admin", admin),
    path("billing", billing),
    path("api/catalog", catalog),
]
