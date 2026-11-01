from __future__ import annotations

import json
import re
from pathlib import Path

import masks

TABLE = json.loads((Path(__file__).resolve().parents[2] / "test" / "contract" / "errors.json").read_text())
KINDS = {
    name: getattr(masks, name)
    for name in (
        "Refused",
        "InvalidToken",
        "Forbidden",
        "Unavailable",
        "Insecure",
        "Foreign",
        "DelegationRefused",
        "DelegationUnavailable",
    )
}


def test_every_kind_in_the_contract_is_a_masks_error_with_its_own_name() -> None:
    for kind in TABLE["kinds"]:
        assert kind["names"]["python"] == f"masks.{kind['name']}"
        assert issubclass(KINDS[kind["name"]], masks.MasksError)


def test_every_failure_in_the_contract_is_raised_with_its_code_and_description() -> None:
    for key, held in TABLE["failures"].items():
        names = re.findall(r"\{[a-z_]+\}", held["description"])
        values = [name[1:-1].upper() for name in names]
        description = held["description"]

        for name, value in zip(names, values, strict=True):
            description = description.replace(name, value, 1)

        assert masks.failure(key, *values) == (held["code"], description), key

        error = KINDS[held["kind"]].of(key, *values)

        assert isinstance(error, masks.MasksError), key
        assert type(error).__name__ == held["kind"], key
        assert error.code == held["code"], key
        assert error.description == description, key
        assert str(error) == f"masks: {held['code']}: {description}", key
        assert masks.has_code(error, held["code"]), key


def test_a_missing_token_is_the_one_failure_that_says_so() -> None:
    assert masks.InvalidToken.of("no_token").missing
    assert not masks.InvalidToken.of("expired").missing
