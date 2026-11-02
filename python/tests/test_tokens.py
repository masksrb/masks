from __future__ import annotations

import base64
import json
import time
from pathlib import Path
from typing import Any

import httpx
import jwt
import pytest

import masks

CONTRACT = json.loads((Path(__file__).resolve().parents[2] / "test" / "contract" / "tokens.json").read_text())
ISSUER = "https://masks.contract.test"
NAMES = {"issuer": ISSUER, "client_id": CONTRACT["client_id"], "resource": CONTRACT["resource"]}


def placed(value: Any) -> Any:
    if isinstance(value, str):
        for name, held in NAMES.items():
            value = value.replace("{" + name + "}", held)

        return value

    if isinstance(value, list):
        return [placed(held) for held in value]

    if isinstance(value, dict):
        return {key: placed(held) for key, held in value.items()}

    return value


def merged(base: dict[str, Any], overrides: dict[str, Any] | None) -> dict[str, Any]:
    held = dict(base)

    for name, value in (overrides or {}).items():
        if value is None:
            held.pop(name, None)
        else:
            held[name] = value

    return held


def timed(claims: dict[str, Any]) -> dict[str, Any]:
    now = int(time.time())

    return {
        name: value + now if name in CONTRACT["times"] and isinstance(value, int) else value
        for name, value in claims.items()
    }


def encoded(value: Any) -> str:
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")


def signed(case: dict[str, Any]) -> str:
    if "raw" in case:
        return str(case["raw"])

    base = CONTRACT["tokens"][case["token"]]
    header = merged(base["header"], case.get("header"))
    claims = timed(placed(merged(base["claims"], case.get("claims"))))
    key = case.get("key", "signing")

    if key == "none":
        return f"{encoded(header)}.{encoded(claims)}."

    signer = CONTRACT["secret"] if key == "secret" else jwt.PyJWK(CONTRACT["keys"][key]).key
    headers = {name: value for name, value in header.items() if name != "alg"}
    headers.setdefault("typ", None)

    return jwt.encode(claims, signer, algorithm=header["alg"], headers=headers)


def handle(request: httpx.Request) -> httpx.Response:
    if request.url.path == "/.well-known/openid-configuration":
        return httpx.Response(200, json=placed(CONTRACT["discovery"]))

    if request.url.path == "/.well-known/jwks.json":
        return httpx.Response(200, json=CONTRACT["jwks"])

    return httpx.Response(404, json={"error": "not_found"})


@pytest.fixture
def http() -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handle))


@pytest.fixture
def issuer(http: httpx.Client) -> masks.Issuer:
    return masks.discover(ISSUER, http=http)


def verify(case: dict[str, Any], token: str, issuer: masks.Issuer, http: httpx.Client) -> Any:
    expecting = {**CONTRACT["expecting"], **case.get("expecting", {})}
    client = masks.Client(issuer, CONTRACT["client_id"], http=http)

    if case["token"] == "access":
        return masks.Verifier(issuer, CONTRACT["resource"], http=http).verify(token)

    if case["token"] == "id":
        return client.verify_id_token(
            token, nonce=expecting["nonce"], access_token=expecting["access_token"], max_age=expecting["max_age"]
        )

    return client.verify_logout_token(token)


@pytest.mark.parametrize("case", CONTRACT["cases"], ids=[case["name"] for case in CONTRACT["cases"]])
def test_every_token_in_the_contract_ends_as_the_contract_says(
    case: dict[str, Any], issuer: masks.Issuer, http: httpx.Client
) -> None:
    token = signed(case)

    if case["outcome"] == "ok":
        verify(case, token, issuer, http)
        return

    code, description = masks.failure(case["outcome"]["failure"], *placed(case["outcome"].get("values", [])))

    with pytest.raises(masks.InvalidToken) as raised:
        verify(case, token, issuer, http)

    assert (raised.value.code, raised.value.description) == (code, description)
