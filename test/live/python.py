from __future__ import annotations

import json
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qsl, urlsplit

import masks


class LiveApp:
    def __init__(self, port: int, bind: str) -> None:
        self.port = port
        self.bind = bind
        self.logouts: queue.Queue[masks.Logout] = queue.Queue()
        self.issuer: masks.Issuer | None = None
        self.pairing: masks.Handshake | None = None
        self.handshake_state = ""
        self.redirect_uri = ""
        self.scope: list[str] = []
        self.signin_scope: list[str] = []
        self.registration: masks.Registration | None = None
        self.client: masks.Client | None = None
        self.started: masks.AuthorizationRequest | None = None
        self.token: masks.Token | None = None

        app = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(length).decode()
                status = 404

                if self.path == "/backchannel" and app.client is not None:
                    form = dict(parse_qsl(body))

                    try:
                        app.logouts.put(
                            app.client.verify_logout_token(form.get("logout_token", ""))
                        )
                        status = 200
                    except masks.MasksError as error:
                        print(f"python live app: {error!r}", file=sys.stderr)
                        status = 400

                self.send_response(status)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def do_GET(self) -> None:
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, format: str, *args: Any) -> None:
                return

        self.server = ThreadingHTTPServer((self.bind, port), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def run(self) -> None:
        self.answer({"ready": True})

        for line in sys.stdin:
            asked = json.loads(line)
            step = asked["step"]

            if step == "quit":
                break

            try:
                answer = getattr(self, step.replace(":", "_"))(asked)
            except Exception as error:  # noqa: BLE001
                answer = {"error": f"{type(error).__name__}: {error}"}

            self.answer(answer)

        self.server.shutdown()

    def answer(self, value: dict[str, Any]) -> None:
        print(json.dumps(value), flush=True)

    def handshake(self, asked: dict[str, Any]) -> dict[str, Any]:
        self.issuer = masks.discover(asked["issuer"])
        self.redirect_uri = asked["redirect_uri"]
        self.scope = list(asked["scope"])
        self.signin_scope = list(asked.get("signin_scope") or self.scope)
        self.pairing = masks.Handshake(
            self.issuer,
            name=asked["name"],
            resource=asked["resource"],
            redirect_uris=[asked["redirect_uri"]],
            return_to=asked["return_to"],
            scope=self.scope,
            backchannel_logout_uri=asked["backchannel_logout_uri"],
        )
        started = self.pairing.start()
        self.handshake_state = started.state

        return {"url": started.url, "state": started.state}

    def handshake_complete(self, asked: dict[str, Any]) -> dict[str, Any]:
        assert self.pairing is not None and self.issuer is not None
        self.registration = self.pairing.complete(
            query(asked["url"]), self.handshake_state
        )
        self.client = masks.Client.from_registration(self.issuer, self.registration)

        return {"client_id": self.registration.client_id}

    def signin(self, asked: dict[str, Any]) -> dict[str, Any]:
        assert self.client is not None
        self.started = self.client.start(
            self.redirect_uri,
            scope=self.signin_scope,
            prompt=asked.get("prompt"),
            max_age=asked.get("max_age"),
        )

        return {"url": self.started.url}

    def signin_complete(self, asked: dict[str, Any]) -> dict[str, Any]:
        assert self.client is not None and self.started is not None
        signed = self.client.complete(self.started, query(asked["url"]))
        self.token = signed.token

        return {
            "sub": signed.claims.get("sub"),
            "sid": signed.claims.get("sid"),
            "auth_time": signed.claims.get("auth_time"),
            "amr": signed.claims.get("amr"),
            "refresh_token": bool(signed.token.refresh_token),
            "id_token": bool(signed.token.id_token),
        }

    def refresh(self, asked: dict[str, Any]) -> dict[str, Any]:
        assert self.client is not None and self.token is not None
        renewed = self.client.refresh(self.token.refresh_token or "")
        rotated = (
            bool(renewed.refresh_token)
            and renewed.refresh_token != self.token.refresh_token
            and renewed.access_token != self.token.access_token
        )
        self.token = renewed

        if renewed.id_token:
            sub = self.client.verify_id_token(
                renewed.id_token, access_token=renewed.access_token
            ).get("sub")
        else:
            sub = self.client.userinfo(renewed).get("sub")

        return {"rotated": rotated, "sub": sub}

    def logout(self, asked: dict[str, Any]) -> dict[str, Any]:
        deadline = time.monotonic() + float(asked.get("timeout", 30))

        while True:
            remaining = deadline - time.monotonic()

            if remaining <= 0:
                raise RuntimeError("no logout token arrived")

            try:
                received = self.logouts.get(timeout=min(remaining, 0.5))
            except queue.Empty:
                continue

            return {"sid": received.sid, "sub": received.subject}

    def machine(self, asked: dict[str, Any]) -> dict[str, Any]:
        assert self.client is not None and self.issuer is not None
        scope = asked["scope"]
        enrollment = self.client.enroll(scope=[scope], client_name="live machine")
        key = masks.Key.generate()
        dpop = masks.Key.generate()
        registered = masks.Client.register(
            self.issuer,
            masks.ClientMetadata(
                client_name="live machine",
                grant_types=["client_credentials"],
                scope=scope,
                token_endpoint_auth_method=masks.PRIVATE_KEY_JWT,
                jwks=key.jwks(),
                dpop_bound_access_tokens=True,
            ),
            enrollment.initial_access_token,
        )
        machine = masks.Client.from_registration(
            self.issuer, registered, key=key, dpop=dpop
        )
        token = machine.client_credentials(scope=[scope], resource=[asked["resource"]])
        introspected = self.client.introspect(token.access_token)

        return {
            "client_id": registered.client_id,
            "bound": token.bound,
            "active": introspected.active,
            "scope": token.scope,
            "jkt": introspected.thumbprint == dpop.thumbprint,
        }


def query(url: str) -> dict[str, str]:
    return dict(parse_qsl(urlsplit(url).query))


def main() -> None:
    port = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else 4413
    bind = (
        sys.argv[sys.argv.index("--bind") + 1] if "--bind" in sys.argv else "127.0.0.1"
    )
    LiveApp(port, bind).run()


if __name__ == "__main__":
    main()
