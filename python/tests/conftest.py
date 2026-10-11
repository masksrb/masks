from __future__ import annotations

import pytest

import masks
from masks import client as client_module

from .fake import ISSUER, Fake, FakeClient


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def fake() -> Fake:
    return Fake()


@pytest.fixture
def issuer(fake: Fake) -> masks.Issuer:
    with fake.http() as http:
        return masks.discover(ISSUER, http=http)


@pytest.fixture
def quick_devices(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(client_module, "DEVICE_PAUSE", 0.01)


@pytest.fixture
def keys() -> tuple[masks.Key, masks.Key]:
    return masks.Key.generate(), masks.Key.generate()


@pytest.fixture
def signed(fake: Fake, issuer: masks.Issuer, keys: tuple[masks.Key, masks.Key]) -> masks.Client:
    key, dpop = keys
    fake.add("signed", FakeClient(method="private_key_jwt", jwks=key.jwks(), scope="files:read"))

    return masks.Client(issuer, "signed", key=key, dpop=dpop, http=fake.http())
