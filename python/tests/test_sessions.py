from __future__ import annotations

import secrets

import pytest

from masks.web import Config, MemorySessionStore, ServerSessions
from masks.web.core import Masks
from masks.web.sessions import COOKIE_PIECE

SECRET = "s" * 32


def engine(**changes: object) -> Masks:
    return Masks(Config(**{"issuer": "https://id.example", "secret": SECRET, **changes}))


def header(sent: list[str]) -> str:
    return "; ".join(cookie.split(";")[0] for cookie in sent)


def test_a_large_session_comes_back_whole() -> None:
    held = engine()
    session = held.load("")
    session["note"] = secrets.token_urlsafe(3 * COOKIE_PIECE)
    sent = held.cookies(session, True)

    assert len(sent) > 1
    assert held.load(f"other=1; {header(sent)}")["note"] == session["note"]


def test_a_session_too_large_for_cookies_is_refused() -> None:
    held = engine()
    session = held.load("")
    session["note"] = secrets.token_urlsafe(9 * COOKIE_PIECE)

    with pytest.raises(ValueError, match="keep sessions on the server"):
        held.cookies(session, True)


def test_a_missing_or_changed_piece_is_a_signed_out_visitor() -> None:
    held = engine()
    session = held.load("")
    session["note"] = secrets.token_urlsafe(3 * COOKIE_PIECE)
    pieces = [cookie.split(";")[0] for cookie in held.cookies(session, True)]

    assert dict(held.load("; ".join(pieces[:1] + pieces[2:]))) == {}
    assert dict(held.load("; ".join([*pieces[:-1], pieces[-1][:-2] + "AA"]))) == {}


def test_a_session_moved_to_the_server_clears_the_old_pieces() -> None:
    before = engine()
    session = before.load("")
    session["note"] = secrets.token_urlsafe(3 * COOKIE_PIECE)
    pieces = header(before.cookies(session, True))
    after = engine(sessions=ServerSessions(MemorySessionStore()))
    moved = after.load(pieces)
    moved["note"] = "short"
    sent = after.cookies(moved, True)

    assert [cookie.split("=")[0] for cookie in sent if "Max-Age=0" not in cookie] == ["__Host-masks"]
    assert len([cookie for cookie in sent if "Max-Age=0" in cookie]) == len(pieces.split("; ")) - 1


def test_an_unchanged_session_sets_no_cookie() -> None:
    held = engine()
    session = held.load("")
    session["note"] = "kept"
    loaded = held.load(header(held.cookies(session, True)))

    assert loaded["note"] == "kept"
    assert held.cookies(loaded, True) == []
