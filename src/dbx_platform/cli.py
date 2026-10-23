"""Command line entry point: `dbx-platform validate ...`."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from dbx_platform import rules
from dbx_platform.validate import render_tfvars, validate_files


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="dbx-platform",
        description="Self-service front door for the shared Databricks platform.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    validate = subcommands.add_parser(
        "validate",
        help="Validate domain request files and generate the Terraform variables.",
    )
    validate.add_argument("files", nargs="+", type=Path, metavar="domain.yaml")
    validate.add_argument(
        "--environment",
        "-e",
        required=True,
        choices=rules.ENVIRONMENTS,
        help="Target environment. Used only to derive the Entra group names.",
    )
    validate.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Write the Terraform variables (JSON) to this file. Without it, print to stdout.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    domains, problems = validate_files(args.files, args.environment)

    if problems:
        total = 0
        for path, messages in problems.items():
            for message in messages:
                print(f"{path}: {message}", file=sys.stderr)
                total += 1
        print(
            f"\nValidation failed: {total} problem(s) in {len(problems)} file(s). "
            "Nothing was generated.",
            file=sys.stderr,
        )
        return 1

    tfvars = render_tfvars(domains)
    if args.output:
        args.output.write_text(tfvars, encoding="utf-8")
        print(f"OK: {len(domains)} domain(s) valid. Wrote {args.output}", file=sys.stderr)
    else:
        print(tfvars, end="")
        print(f"OK: {len(domains)} domain(s) valid.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
