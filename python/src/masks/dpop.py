from __future__ import annotations

import hashlib
import time
from urllib.parse import urlsplit, urlunsplit

from .keys import Key, encode, random_id

DPOP = "DPoP"
PROOF_TYPE = "dpop+jwt"
DEFAULT_PORTS = {"http": 80, "https": 443}


def token_hash(access_token: str) -> str:
    return encode(hashlib.sha256(access_token.encode()).digest())


def without_query(target: str) -> str:
    held = urlsplit(target)

    return urlunsplit((held.scheme, held.netloc, held.path, "", ""))


def tidied(target: str) -> str:
    held = urlsplit(target)
    scheme = held.scheme.lower()
    host = (held.hostname or "").lower()

    if ":" in host:
        host = f"[{host}]"

    port = held.port

    if port is not None and port != DEFAULT_PORTS.get(scheme):
        host = f"{host}:{port}"

    path = "" if held.path == "/" else held.path

    return urlunsplit((scheme, host, path, "", ""))


def proof(key: Key, method: str, target: str, access_token: str = "", nonce: str = "") -> str:
    claims: dict[str, object] = {
        "jti": random_id(),
        "htm": method.upper(),
        "htu": without_query(target),
        "iat": int(time.time()),
    }

    if access_token:
        claims["ath"] = token_hash(access_token)

    if nonce:
        claims["nonce"] = nonce

    return key.sign(PROOF_TYPE, claims, embed=True)
