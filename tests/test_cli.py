from __future__ import annotations

import json
from pathlib import Path

import pytest

from dbx_platform.cli import main

VALID = "name: {name}\nowner_group: {name}-owners\ncost_centre: CC-1001\n"


def make(tmp_path: Path, name: str, body: str | None = None) -> Path:
    path = tmp_path / f"{name}.yaml"
    path.write_text(body if body is not None else VALID.format(name=name), encoding="utf-8")
    return path


def test_success_writes_output_file(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    out = tmp_path / "out.json"
    code = main(["validate", str(make(tmp_path, "alpha")), "-e", "dev", "-o", str(out)])
    assert code == 0
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["domains"]["alpha"]["reader_group_name"] == "sg-dbx-alpha-dev-reader"
    assert "OK: 1 domain(s) valid" in capsys.readouterr().err


def test_success_prints_json_to_stdout(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    code = main(["validate", str(make(tmp_path, "alpha")), "-e", "dev"])
    captured = capsys.readouterr()
    assert code == 0
    assert "alpha" in json.loads(captured.out)["domains"]


def test_failure_returns_1_and_writes_nothing(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    good = make(tmp_path, "alpha")
    bad = make(tmp_path, "beta", "name: beta\nowner_group: beta-owners\ncost_centre: oops\n")
    out = tmp_path / "out.json"
    code = main(["validate", str(good), str(bad), "-e", "dev", "-o", str(out)])
    err = capsys.readouterr().err
    assert code == 1
    assert not out.exists()  # all-or-nothing: one bad file blocks the whole output
    assert "beta.yaml" in err and "cost_centre" in err
    assert "Nothing was generated" in err


def test_unknown_environment_exits_2(tmp_path: Path) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["validate", str(make(tmp_path, "alpha")), "-e", "staging"])
    assert exc.value.code == 2


def test_environment_is_required(tmp_path: Path) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["validate", str(make(tmp_path, "alpha"))])
    assert exc.value.code == 2
