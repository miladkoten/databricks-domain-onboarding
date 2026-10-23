"""Parse and validate domain request files, and render the Terraform variables.

Design rule: collect every problem in a file and report them together, so a team
fixes its request in one round instead of one error per pull-request push.
"""

from __future__ import annotations

import json
import re
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from dbx_platform import rules

REQUIRED_FIELDS = ("name", "owner_group", "cost_centre")
OPTIONAL_FIELDS = ("schemas", "allowed_node_types", "max_workers", "max_autotermination_minutes")
ALLOWED_FIELDS = REQUIRED_FIELDS + OPTIONAL_FIELDS


@dataclass
class ValidationResult:
    name: str | None = None
    entry: dict[str, Any] | None = None
    errors: list[str] = field(default_factory=list)


def _is_whole_number(value: object) -> bool:
    # bool is a subclass of int in Python, and "max_workers: true" must not pass.
    return isinstance(value, int) and not isinstance(value, bool)


def _check_text(
    label: str, value: object, pattern: re.Pattern[str], hint: str, errors: list[str]
) -> None:
    if not isinstance(value, str):
        errors.append(f"{label}: must be text, got {value!r}. {hint}")
    elif not pattern.fullmatch(value):
        errors.append(f"{label}: {value!r} is not valid. {hint}")


def _check_range(label: str, value: object, bounds: tuple[int, int], errors: list[str]) -> None:
    low, high = bounds
    if not _is_whole_number(value):
        errors.append(f"{label}: must be a whole number between {low} and {high}, got {value!r}.")
    elif value > high:  # type: ignore[operator]
        errors.append(
            f"{label}: {value} exceeds the platform ceiling of {high}. "
            f"Choose a value between {low} and {high}."
        )
    elif value < low:  # type: ignore[operator]
        errors.append(
            f"{label}: {value} is below the minimum of {low}. "
            f"Choose a value between {low} and {high}."
        )


def _check_schemas(value: object, errors: list[str]) -> None:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        errors.append("schemas: must be a list of schema names, for example [raw, curated].")
        return
    missing = [name for name in rules.REQUIRED_SCHEMAS if name not in value]
    if missing:
        errors.append(
            f"schemas: must include {', '.join(rules.REQUIRED_SCHEMAS)}; "
            f"missing: {', '.join(missing)}."
        )
    invalid = [name for name in value if not rules.SCHEMA_NAME_RE.fullmatch(name)]
    if invalid:
        errors.append(
            f"schemas: invalid name(s): {', '.join(repr(n) for n in invalid)}. "
            "Use 2-32 lowercase letters, digits or underscores, starting with a letter."
        )
    duplicates = sorted({name for name in value if value.count(name) > 1})
    if duplicates:
        errors.append(f"schemas: duplicate name(s): {', '.join(duplicates)}.")


def _check_node_types(value: object, errors: list[str]) -> None:
    approved = ", ".join(rules.APPROVED_NODE_TYPES)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        errors.append(
            f"allowed_node_types: must be a list of VM sizes. Approved sizes: {approved}."
        )
    elif not value:
        errors.append(f"allowed_node_types: must not be empty. Approved sizes: {approved}.")
    else:
        unapproved = [item for item in value if item not in rules.APPROVED_NODE_TYPES]
        if unapproved:
            errors.append(
                f"allowed_node_types: not approved: {', '.join(unapproved)}. "
                f"Approved sizes: {approved}."
            )


def validate_file(path: Path, environment: str) -> ValidationResult:
    """Validate one domain request. `environment` only shapes the derived group names."""
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError) as exc:
        return ValidationResult(errors=[f"Cannot read file: {exc}"])
    except yaml.YAMLError as exc:
        return ValidationResult(errors=[f"File is not valid YAML: {exc}"])
    if not isinstance(raw, dict):
        return ValidationResult(
            errors=["File must contain a YAML mapping (key: value pairs) at the top level."]
        )

    errors: list[str] = []

    # A misspelt optional field would otherwise be ignored and silently replaced by the default.
    unknown = sorted(str(key) for key in raw if key not in ALLOWED_FIELDS)
    if unknown:
        errors.append(
            f"Unknown field(s): {', '.join(unknown)}. Allowed fields: {', '.join(ALLOWED_FIELDS)}."
        )

    for key in REQUIRED_FIELDS:
        if raw.get(key) in (None, ""):
            errors.append(f"{key}: required, but missing or empty.")

    name = raw.get("name")
    if name not in (None, ""):
        _check_text(
            "name",
            name,
            rules.DOMAIN_NAME_RE,
            "Use 3-16 lowercase letters or digits, starting with a letter (for example 'alpha'). "
            "Underscores and hyphens are not allowed because the name appears in container "
            "and catalog names.",
            errors,
        )
        if isinstance(name, str) and name != path.stem:
            errors.append(
                f"name: {name!r} must match the file name. "
                f"Rename the file to '{name}.yaml' or change the name."
            )

    owner = raw.get("owner_group")
    if owner not in (None, ""):
        _check_text(
            "owner_group",
            owner,
            rules.OWNER_GROUP_RE,
            "Use 3-40 lowercase letters, digits or hyphens, for example 'alpha-owners'.",
            errors,
        )

    cost_centre = raw.get("cost_centre")
    if cost_centre not in (None, ""):
        _check_text(
            "cost_centre",
            cost_centre,
            rules.COST_CENTRE_RE,
            "Use the form CC-1234 (CC, a hyphen, four digits).",
            errors,
        )

    if "schemas" in raw:
        _check_schemas(raw["schemas"], errors)
    if "allowed_node_types" in raw:
        _check_node_types(raw["allowed_node_types"], errors)
    if "max_workers" in raw:
        _check_range("max_workers", raw["max_workers"], rules.MAX_WORKERS_RANGE, errors)
    if "max_autotermination_minutes" in raw:
        _check_range(
            "max_autotermination_minutes",
            raw["max_autotermination_minutes"],
            rules.AUTOTERMINATION_RANGE,
            errors,
        )

    if errors:
        return ValidationResult(name=name if isinstance(name, str) else None, errors=errors)

    reader, engineer = rules.group_names(name, environment)
    entry: dict[str, Any] = {
        "owner_group": owner,
        "cost_centre": cost_centre,
        "reader_group_name": reader,
        "engineer_group_name": engineer,
    }
    # Optional fields are passed through only when given, so Terraform's module defaults apply.
    for key in OPTIONAL_FIELDS:
        if key in raw:
            entry[key] = raw[key]
    return ValidationResult(name=name, entry=entry)


def validate_files(
    paths: Sequence[Path], environment: str
) -> tuple[dict[str, dict[str, Any]], dict[Path, list[str]]]:
    """Validate many files. Returns (valid domains by name, problems by file)."""
    domains: dict[str, dict[str, Any]] = {}
    sources: dict[str, Path] = {}
    problems: dict[Path, list[str]] = {}
    for path in paths:
        result = validate_file(path, environment)
        name, entry = result.name, result.entry
        if result.errors or name is None or entry is None:
            problems[path] = result.errors or ["Internal error: no result produced."]
            continue
        if name in domains:
            problems[path] = [
                f"name: {name!r} is already defined by {sources[name]}. "
                "Domain names must be unique."
            ]
            continue
        domains[name] = entry
        sources[name] = path
    return domains, problems


def render_tfvars(domains: dict[str, dict[str, Any]]) -> str:
    """Terraform loads *.auto.tfvars.json natively. Sorted keys keep diffs stable in review."""
    return json.dumps({"domains": domains}, indent=2, sort_keys=True) + "\n"
