from __future__ import annotations

import ipaddress
import json
from collections.abc import Awaitable, Callable, Generator
from typing import Any, TypeVar, cast
from urllib.parse import urlsplit, urlunsplit

import httpx

from .errors import READ_LIMIT, Error, ForeignOrigin, InsecureURL, refused
from .models import Issuer, Metadata, ResourceMetadata

T = TypeVar("T")

Flow = Generator[httpx.Request, httpx.Response, T]

DISCOVERY_PATH = "/.well-known/openid-configuration"
RESOURCE_PATH = "/.well-known/oauth-protected-resource"
TIMEOUT = 30.0


def loopback(host: str) -> bool:
    if host == "localhost" or host.endswith(".localhost"):
        return True

    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def check(target: str, allow_plain_http: bool = False) -> None:
    held = urlsplit(target)
    host = held.hostname or ""

    if held.scheme == "https" and host:
        return

    if held.scheme == "http" and host and (allow_plain_http or loopback(host)):
        return

    if held.scheme == "http":
        raise InsecureURL(f"masks: plain http is allowed only on this machine: {target}")

    raise InsecureURL(f"masks: {target!r} is not an http or https URL")


def origin(target: str | httpx.URL) -> str:
    held = urlsplit(str(target))
    scheme = held.scheme.lower()
    host = (held.hostname or "").lower()

    if ":" in host:
        host = f"[{host}]"

    if held.port is not None and held.port != {"http": 80, "https": 443}.get(scheme):
        host = f"{host}:{held.port}"

    return f"{scheme}://{host}"


def same_origin(issuer: Issuer, target: str) -> None:
    if origin(target) != origin(issuer.url):
        raise ForeignOrigin(f"masks: that URL belongs to another origin: {target}")


def get(target: str, bearer: str = "") -> httpx.Request:
    headers = {"Accept": "application/json"}

    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"

    return httpx.Request("GET", target, headers=headers)


def send_json(method: str, target: str, bearer: str, body: dict[str, Any] | None) -> httpx.Request:
    headers = (
        {"Accept": "application/json", "Authorization": f"Bearer {bearer}"}
        if bearer
        else {"Accept": "application/json"}
    )

    if body is None:
        return httpx.Request(method, target, headers=headers)

    return httpx.Request(method, target, headers=headers, json=body)


def decoded(response: httpx.Response) -> dict[str, Any] | None:
    if response.status_code >= 300:
        raise refused(response)

    if response.status_code == 204 or not response.content:
        return None

    try:
        body = json.loads(response.content)
    except ValueError as error:
        raise Error("server_error", f"{response.request.url} answered with something other than JSON") from error

    if not isinstance(body, dict):
        raise Error("server_error", f"{response.request.url} answered with something other than a JSON object")

    return body


def required(response: httpx.Response) -> dict[str, Any]:
    body = decoded(response)

    if body is None:
        raise Error("server_error", f"{response.request.url} answered with nothing")

    return body


def discovery(issuer: str, allow_plain_http: bool = False) -> Flow[Issuer]:
    named = issuer.rstrip("/")
    check(named, allow_plain_http)

    body = required((yield get(named + DISCOVERY_PATH)))
    metadata = Metadata.from_dict(body)

    if metadata.issuer.rstrip("/") != named:
        raise Error("invalid_issuer", f"{named} publishes a document naming {metadata.issuer!r}")

    for endpoint in metadata.endpoints():
        check(endpoint, allow_plain_http)

    return Issuer(url=named, metadata=metadata, allow_plain_http=allow_plain_http)


def resource_discovery(resource: str, allow_plain_http: bool = False) -> Flow[ResourceMetadata]:
    named = resource.rstrip("/")
    check(named, allow_plain_http)

    held = urlsplit(named)
    document = urlunsplit((held.scheme, held.netloc, RESOURCE_PATH + held.path, "", ""))

    found = ResourceMetadata.from_dict(required((yield get(document))))

    if found.resource.rstrip("/") != named:
        raise Error("invalid_resource", f"{named} publishes metadata naming {found.resource!r}")

    return found


def bounded(response: httpx.Response, content: bytes) -> httpx.Response:
    return httpx.Response(
        response.status_code,
        headers=response.headers,
        content=content,
        request=response.request,
    )


def fetch(request: httpx.Request, http: httpx.Client) -> httpx.Response:
    response = http.send(request, stream=True, follow_redirects=False)

    try:
        content = bytearray()

        for chunk in response.iter_bytes():
            content += chunk

            if len(content) > READ_LIMIT:
                raise Error("server_error", f"{request.url} answered with more than {READ_LIMIT} bytes")
    finally:
        response.close()

    return bounded(response, bytes(content))


async def afetch(request: httpx.Request, http: httpx.AsyncClient) -> httpx.Response:
    response = await http.send(request, stream=True, follow_redirects=False)

    try:
        content = bytearray()

        async for chunk in response.aiter_bytes():
            content += chunk

            if len(content) > READ_LIMIT:
                raise Error("server_error", f"{request.url} answered with more than {READ_LIMIT} bytes")
    finally:
        await response.aclose()

    return bounded(response, bytes(content))


def run(flow: Generator[Any, Any, T], http: httpx.Client, other: Callable[[Any], Any] | None = None) -> T:
    try:
        item = next(flow)

        while True:
            if not isinstance(item, httpx.Request):
                if other is None:
                    raise TypeError(f"masks: a flow yielded {item!r}, which is not a request")

                try:
                    answered = other(item)
                except Exception as error:
                    item = flow.throw(error)
                    continue

                item = flow.send(answered)
                continue

            try:
                response = fetch(item, http)
            except (httpx.HTTPError, Error) as error:
                item = flow.throw(error)
                continue

            item = flow.send(response)
    except StopIteration as done:
        return cast(T, done.value)


async def arun(
    flow: Generator[Any, Any, T],
    http: httpx.AsyncClient,
    other: Callable[[Any], Awaitable[Any]] | None = None,
) -> T:
    try:
        item = next(flow)

        while True:
            if not isinstance(item, httpx.Request):
                if other is None:
                    raise TypeError(f"masks: a flow yielded {item!r}, which is not a request")

                try:
                    answered = await other(item)
                except Exception as error:
                    item = flow.throw(error)
                    continue

                item = flow.send(answered)
                continue

            try:
                response = await afetch(item, http)
            except (httpx.HTTPError, Error) as error:
                item = flow.throw(error)
                continue

            item = flow.send(response)
    except StopIteration as done:
        return cast(T, done.value)


def default_http() -> httpx.Client:
    return httpx.Client(timeout=TIMEOUT, follow_redirects=False)


def default_async_http() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=False)


def discover(issuer: str, *, http: httpx.Client | None = None, allow_plain_http: bool = False) -> Issuer:
    if http is None:
        with default_http() as held:
            return run(discovery(issuer, allow_plain_http), held)

    return run(discovery(issuer, allow_plain_http), http)


async def adiscover(issuer: str, *, http: httpx.AsyncClient | None = None, allow_plain_http: bool = False) -> Issuer:
    if http is None:
        async with default_async_http() as held:
            return await arun(discovery(issuer, allow_plain_http), held)

    return await arun(discovery(issuer, allow_plain_http), http)


def discover_resource(
    resource: str, *, http: httpx.Client | None = None, allow_plain_http: bool = False
) -> ResourceMetadata:
    if http is None:
        with default_http() as held:
            return run(resource_discovery(resource, allow_plain_http), held)

    return run(resource_discovery(resource, allow_plain_http), http)


async def adiscover_resource(
    resource: str, *, http: httpx.AsyncClient | None = None, allow_plain_http: bool = False
) -> ResourceMetadata:
    if http is None:
        async with default_async_http() as held:
            return await arun(resource_discovery(resource, allow_plain_http), held)

    return await arun(resource_discovery(resource, allow_plain_http), http)
