from __future__ import annotations

import functools
from collections.abc import Callable, Sequence
from typing import Any, TypeVar, cast

import httpx
from flask import Blueprint, Flask, Response, current_app, g, jsonify, request
from werkzeug.exceptions import RequestEntityTooLarge
from werkzeug.local import LocalProxy

from .client import Client
from .errors import MasksError
from .oidc import HeldConnection
from .web.config import Config
from .web.core import FORM_LIMIT, METADATA_PATH, Answer, Incoming, Refusal, cookie_named, too_large, unshared
from .web.core import Masks as Engine
from .web.person import Person
from .web.sessions import Session

F = TypeVar("F", bound=Callable[..., Any])

__all__ = ["Config", "Masks", "Person", "masked"]


def incoming() -> Incoming:
    return Incoming(
        method=request.method,
        url=request.url,
        headers=httpx.Headers(list(request.headers.items())),
        query={key: request.args.getlist(key)[0] for key in request.args},
        form={key: request.form.getlist(key)[0] for key in request.form} if request.method == "POST" else {},
        native=request,
    )


def response(answer: Answer) -> Response:
    sent = Response(answer.body, status=answer.status, content_type=answer.content_type or None)

    for name, value in answer.headers:
        sent.headers.add(name, value)

    return sent


def refused(error: Refusal) -> Response:
    return response(error.answer)


class Masks:
    def __init__(self, app: Flask | None = None, config: Config | None = None, **options: Any) -> None:
        self._config = config
        self._options = options
        self._engine: Engine | None = None
        self._named: set[str] = set()

        if app is not None:
            self.init_app(app)

    @property
    def engine(self) -> Engine:
        if self._engine is None:
            raise RuntimeError("masks: call Masks.init_app before using it")

        return self._engine

    def init_app(self, app: Flask) -> None:
        config = self._config or Config(**{"secret": app.secret_key or "", **self._options})
        if getattr(config.backend, "asynchronous", False):
            raise TypeError("masks: an async session store needs an async framework, such as FastAPI")

        self._engine = Engine(config)
        self._known(sorted(self._named))
        app.extensions["masks"] = self

        blueprint = Blueprint("masks", __name__)

        for path, methods, name in self._engine.routes():
            blueprint.add_url_rule(
                path, f"{name}_{'_'.join(methods).lower()}", self._endpoint(name), methods=list(methods)
            )

        blueprint.add_url_rule(METADATA_PATH, "metadata", self._metadata, methods=["GET"])
        app.register_blueprint(blueprint)
        app.after_request(self._save)
        app.register_error_handler(Refusal, refused)

    def _save(self, sent: Response) -> Response:
        session = g.get("masks_session")

        if isinstance(session, Session):
            header = self.engine.cookie(session, request.is_secure)

            if header is not None:
                sent.headers["Cache-Control"] = unshared(", ".join(sent.headers.getlist("Cache-Control")))
                sent.headers.add("Set-Cookie", header)

        return sent

    def session(self) -> Session:
        found = g.get("masks_session")

        if not isinstance(found, Session):
            found = self.engine.load(cookie_named(request.headers.get("Cookie", ""), self.engine.cookie_name))
            g.masks_session = found

        return found

    def _endpoint(self, name: str) -> Callable[[], Response]:
        def answer() -> Response:
            if name == "backchannel":
                request.max_content_length = FORM_LIMIT
                request.max_form_memory_size = FORM_LIMIT

                try:
                    held = incoming()
                except RequestEntityTooLarge:
                    return response(too_large())

                found = self.engine.answer(self.engine.backchannel(held))
            else:
                found = self.engine.answer(self.engine.handlers()[name](incoming(), self.session()))

            return response(found)

        return answer

    def _metadata(self) -> Response:
        sent = jsonify(self.engine.metadata(incoming()))
        sent.headers["Cache-Control"] = "max-age=300"

        return sent

    @property
    def person(self) -> Person:
        if "masked" not in g:
            found = self.engine.answer(self.engine.person(incoming(), self.session()))
            g.masked = found if isinstance(found, Person) else Person(known=self.engine.config.known)

        return cast(Person, g.masked)

    def required(self, *privileges: str, tokens: bool = False) -> Callable[[F], F]:
        self._known(privileges)

        def decorate(view: F) -> F:
            @functools.wraps(view)
            def guarded(*args: Any, **kwargs: Any) -> Any:
                found = self.engine.authorize(incoming(), self.session(), privileges, tokens=tokens)

                if isinstance(found, Answer):
                    return response(found)

                g.masked = found

                return view(*args, **kwargs)

            return cast(F, guarded)

        return decorate

    def protected(self, *privileges: str) -> Callable[[F], F]:
        self._known(privileges)

        def decorate(view: F) -> F:
            @functools.wraps(view)
            def guarded(*args: Any, **kwargs: Any) -> Any:
                found = self.engine.protect(incoming(), privileges)

                if isinstance(found, Answer):
                    return response(found)

                g.masked = found

                return view(*args, **kwargs)

            return cast(F, guarded)

        return decorate

    def authorize(self, *privileges: str, tokens: bool = False) -> Person:
        found = self.engine.authorize(incoming(), self.session(), privileges, tokens=tokens)

        if isinstance(found, Answer):
            raise Refusal(found)

        g.masked = found

        return found

    def _known(self, privileges: Sequence[str]) -> None:
        if self._engine is None:
            self._named.update(privileges)
            return

        unknown = [name for name in privileges if name not in self._engine.config.known]

        if unknown:
            raise ValueError(f"masks: no privilege is named {', '.join(unknown)}")

    def client(self) -> Client:
        held = incoming()

        try:
            issuer = self.engine.run(self.engine.discover(held))
        except (MasksError, httpx.HTTPError) as error:
            raise Refusal(Answer.page(503, "masks could not be reached", str(error))) from error

        return self.engine.client(held, issuer)

    def start_delegation(self, provider: str, *, prompt: str | None = None, max_age: int | None = None) -> Response:
        flow = self.engine.start_delegation(incoming(), self.session(), provider, prompt, max_age)

        return response(self.engine.answer(flow))

    def finish_delegation(self) -> HeldConnection:
        return self.engine.run(self.engine.finish_delegation(incoming(), self.session()))

    def login_url(self, return_to: str = "", organization: str = "", privilege: Sequence[str] = ()) -> str:
        return self.engine.login_url(return_to, organization, privilege)

    def logout_url(self) -> str:
        return self.engine.path("/logout")

    def registered(self) -> bool:
        return self.engine.run(self.engine.registered(incoming()))

    def connected(self) -> bool:
        return self.engine.configured(incoming())


def current() -> Masks:
    return cast(Masks, current_app.extensions["masks"])


masked: Person = cast(Person, LocalProxy(lambda: current().person))
