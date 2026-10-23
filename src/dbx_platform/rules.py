"""Platform policy: the one place where naming rules and ceilings live in this package.

The ceilings mirror the variable validation in modules/domain_onboarding/variables.tf.
If you change a number here, change it there too (the README explains why they are
duplicated and what production would do instead).
"""

from __future__ import annotations

import re

# fullmatch is used everywhere, so a trailing newline can never slip through "$".
DOMAIN_NAME_RE = re.compile(r"[a-z][a-z0-9]{2,15}")
OWNER_GROUP_RE = re.compile(r"[a-z0-9][a-z0-9-]{2,39}")
COST_CENTRE_RE = re.compile(r"CC-[0-9]{4}")
SCHEMA_NAME_RE = re.compile(r"[a-z][a-z0-9_]{1,31}")

REQUIRED_SCHEMAS = ("raw", "curated")

MAX_WORKERS_RANGE = (1, 10)
AUTOTERMINATION_RANGE = (10, 120)

APPROVED_NODE_TYPES = ("Standard_DS3_v2", "Standard_D4ds_v5", "Standard_D8ds_v5")

ENVIRONMENTS = ("dev", "acc", "prod")


def group_names(domain: str, environment: str) -> tuple[str, str]:
    """Entra group names by platform convention: sg-dbx-<domain>-<environment>-<role>."""
    prefix = f"sg-dbx-{domain}-{environment}"
    return f"{prefix}-reader", f"{prefix}-engineer"
