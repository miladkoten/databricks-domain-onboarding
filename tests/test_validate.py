from __future__ import annotations

import json
from pathlib import Path

import pytest

from dbx_platform.validate import render_tfvars, validate_file, validate_files

VALID = "name: {name}\nowner_group: {name}-owners\ncost_centre: CC-1001\n"


def write(tmp_path: Path, name: str, body: str | None = None) -> Path:
    path = tmp_path / f"{name}.yaml"
    path.write_text(body if body is not None else VALID.format(name=name), encoding="utf-8")
    return path


def test_valid_minimal_request_derives_group_names(tmp_path: Path) -> None:
    result = validate_file(write(tmp_path, "alpha"), "dev")
    assert result.errors == []
    assert result.entry == {
        "owner_group": "alpha-owners",
        "cost_centre": "CC-1001",
        "reader_group_name": "sg-dbx-alpha-dev-reader",
        "engineer_group_name": "sg-dbx-alpha-dev-engineer",
    }


def test_environment_changes_group_names(tmp_path: Path) -> None:
    result = validate_file(write(tmp_path, "alpha"), "prod")
    assert result.entry is not None
    assert result.entry["reader_group_name"] == "sg-dbx-alpha-prod-reader"


def test_optional_fields_pass_through_only_when_given(tmp_path: Path) -> None:
    body = VALID.format(name="alpha") + "max_workers: 6\nallowed_node_types: [Standard_DS3_v2]\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert result.entry is not None
    assert result.entry["max_workers"] == 6
    assert result.entry["allowed_node_types"] == ["Standard_DS3_v2"]
    assert "schemas" not in result.entry


@pytest.mark.parametrize("name", ["Alpha", "al", "1alpha", "alpha_one", "alpha-one", "a" * 17])
def test_bad_domain_names_rejected(tmp_path: Path, name: str) -> None:
    body = f"name: {name}\nowner_group: x-owners\ncost_centre: CC-1001\n"
    result = validate_file(write(tmp_path, name, body), "dev")
    assert any(e.startswith("name:") for e in result.errors)


def test_name_must_match_file_name(tmp_path: Path) -> None:
    body = VALID.format(name="beta")
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any("must match the file name" in e for e in result.errors)


@pytest.mark.parametrize("value", ["CC-100", "cc-1001", "CC-10010", "1001", "CC1001"])
def test_bad_cost_centre_rejected(tmp_path: Path, value: str) -> None:
    body = f"name: alpha\nowner_group: alpha-owners\ncost_centre: {value}\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any(e.startswith("cost_centre:") for e in result.errors)


def test_missing_required_fields_all_reported(tmp_path: Path) -> None:
    result = validate_file(write(tmp_path, "alpha", "name: alpha\n"), "dev")
    assert any(e.startswith("owner_group:") for e in result.errors)
    assert any(e.startswith("cost_centre:") for e in result.errors)


def test_unknown_field_rejected(tmp_path: Path) -> None:
    body = VALID.format(name="alpha") + "max_worker: 50\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any("Unknown field" in e and "max_worker" in e for e in result.errors)


@pytest.mark.parametrize("value", [0, 11, 50, -1, "4", 4.5, True])
def test_max_workers_out_of_range_or_wrong_type(tmp_path: Path, value: object) -> None:
    body = VALID.format(name="alpha") + f"max_workers: {json.dumps(value)}\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any(e.startswith("max_workers:") for e in result.errors)


@pytest.mark.parametrize("value", [1, 4, 10])
def test_max_workers_boundaries_accepted(tmp_path: Path, value: int) -> None:
    body = VALID.format(name="alpha") + f"max_workers: {value}\n"
    assert validate_file(write(tmp_path, "alpha", body), "dev").errors == []


@pytest.mark.parametrize("value", [9, 121])
def test_autotermination_out_of_range(tmp_path: Path, value: int) -> None:
    body = VALID.format(name="alpha") + f"max_autotermination_minutes: {value}\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any(e.startswith("max_autotermination_minutes:") for e in result.errors)


def test_unapproved_node_type_rejected(tmp_path: Path) -> None:
    body = VALID.format(name="alpha") + "allowed_node_types: [Standard_E64s_v5]\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any("not approved" in e for e in result.errors)


def test_empty_node_type_list_rejected(tmp_path: Path) -> None:
    body = VALID.format(name="alpha") + "allowed_node_types: []\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any("must not be empty" in e for e in result.errors)


def test_schemas_must_include_raw_and_curated(tmp_path: Path) -> None:
    body = VALID.format(name="alpha") + "schemas: [raw, sandbox]\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any("missing: curated" in e for e in result.errors)


def test_duplicate_and_invalid_schemas(tmp_path: Path) -> None:
    body = VALID.format(name="alpha") + "schemas: [raw, raw, curated, Bad-Name]\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert any("duplicate" in e for e in result.errors)
    assert any("invalid name" in e for e in result.errors)


def test_all_problems_reported_together(tmp_path: Path) -> None:
    body = "name: alpha\nowner_group: alpha-owners\ncost_centre: nope\nmax_workers: 99\nfoo: 1\n"
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert len(result.errors) == 3


def test_invalid_yaml(tmp_path: Path) -> None:
    result = validate_file(write(tmp_path, "alpha", "name: [unclosed\n"), "dev")
    assert result.errors and "not valid YAML" in result.errors[0]


@pytest.mark.parametrize("body", ["", "- a\n- b\n", "just text\n"])
def test_top_level_must_be_mapping(tmp_path: Path, body: str) -> None:
    result = validate_file(write(tmp_path, "alpha", body), "dev")
    assert result.errors and "mapping" in result.errors[0]


def test_missing_file_reported(tmp_path: Path) -> None:
    result = validate_file(tmp_path / "ghost.yaml", "dev")
    assert result.errors and "Cannot read file" in result.errors[0]


def test_duplicate_names_across_files(tmp_path: Path) -> None:
    first = write(tmp_path, "alpha")
    second_dir = tmp_path / "other"
    second_dir.mkdir()
    second = second_dir / "alpha.yaml"
    second.write_text(VALID.format(name="alpha"), encoding="utf-8")
    domains, problems = validate_files([first, second], "dev")
    assert list(domains) == ["alpha"]
    assert second in problems and "already defined" in problems[second][0]


def test_render_is_deterministic_and_wrapped() -> None:
    a = render_tfvars({"b": {"x": 1}, "a": {"y": 2}})
    b = render_tfvars({"a": {"y": 2}, "b": {"x": 1}})
    assert a == b
    assert list(json.loads(a)) == ["domains"]
    assert a.endswith("\n")
