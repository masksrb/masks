from __future__ import annotations

import os
import stat
from pathlib import Path

import pytest

from masks.models import Registration
from masks.web import FileCredentials

REGISTRATION = Registration(
    client_id="app",
    client_secret="secret",
    registration_access_token="token",
    registration_client_uri="https://id.example/register/app",
)

as_root = pytest.mark.skipif(hasattr(os, "geteuid") and os.geteuid() == 0, reason="root ignores file modes")


def test_the_file_and_its_folder_are_private(tmp_path: Path) -> None:
    held = FileCredentials(tmp_path / "masks" / "masks.json")
    held.write(REGISTRATION)

    assert stat.S_IMODE((tmp_path / "masks").stat().st_mode) == 0o700
    assert stat.S_IMODE((tmp_path / "masks" / "masks.json").stat().st_mode) == 0o600
    assert held.read()["client_secret"] == "secret"
    assert [path.name for path in (tmp_path / "masks").iterdir()] == ["masks.json"]


def test_a_write_from_another_process_is_read_within_the_same_second(tmp_path: Path) -> None:
    path = tmp_path / "masks.json"
    held = FileCredentials(path)
    other = FileCredentials(path)
    held.write(REGISTRATION)
    before = path.stat()

    assert held.read()["client_id"] == "app"

    other.write(Registration(client_id="next", client_secret="secret"))
    os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))

    assert held.read()["client_id"] == "next"


@as_root
def test_a_folder_it_cannot_write_is_not_writable(tmp_path: Path) -> None:
    folder = tmp_path / "locked"
    folder.mkdir()
    folder.chmod(0o500)

    try:
        assert not FileCredentials(folder / "masks.json").writable
        assert FileCredentials(tmp_path / "masks.json").writable
    finally:
        folder.chmod(0o700)


@as_root
def test_a_file_it_cannot_read_is_an_error(tmp_path: Path) -> None:
    path = tmp_path / "masks.json"
    held = FileCredentials(path)
    held.write(REGISTRATION)
    path.chmod(0o000)

    try:
        with pytest.raises(PermissionError):
            FileCredentials(path).read()
    finally:
        path.chmod(0o600)


def test_a_file_that_is_not_json_is_not_connected(tmp_path: Path) -> None:
    path = tmp_path / "masks.json"
    path.write_text("{not json")

    assert FileCredentials(path).read() == {}
