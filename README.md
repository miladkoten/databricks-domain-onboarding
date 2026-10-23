# Databricks domain onboarding (proof of concept)

Self-service onboarding of data domains onto a shared Azure Databricks platform.
A team requests a domain by adding one YAML file. A validator checks the request, Terraform
builds the storage, Unity Catalog objects, access groups and a cost-tagged cluster policy,
and every change goes through a pull request.

This is a proof of concept on a sandbox subscription with synthetic data only.
The section [Sandbox versus production](#sandbox-versus-production) lists what would change
for a real platform.

## Status

| Area | State |
|---|---|
| Remote state (Azure blob, lease locking, versioning) | Done, bootstrapped by `bootstrap/bootstrap.sh` |
| Terraform module `domain_onboarding` (Azure + Unity Catalog + grants + cluster policy) | Done, applied, destroyed and rebuilt from scratch successfully |
| Two domains driven from one `for_each` loop | Done |
| Python validator `dbx-platform validate` (46 tests, ruff clean) | Done |
| CI: PR checks, plan comment, gated apply | Workflows written and linted, **not yet activated**: pipeline identity is being set up |
| Four-eyes approval | Design decided, see [Approval gate](#approval-gate-and-its-limit) |
| Architecture decision records | Not written yet |
| Phase 4 (audit, import, asset bundle, budget alert) | Roadmap only, see the end of this file |

## How onboarding works

```
domains/<name>.yaml  --PR-->  dbx-platform validate  -->  domains.auto.tfvars.json
                                                                  |
                          terraform plan (posted on the PR)  <----+
                                      |
                       approval  -->  merge  -->  terraform apply
```

1. A team opens a pull request that adds `domains/<name>.yaml` (see [domains/README.md](domains/README.md)).
2. The validator checks naming, compute ceilings, owner and cost centre, and the node-type allowlist. It reports every problem at once and generates the Terraform input only if all files are valid.
3. `terraform plan` runs against the environment and is posted on the PR.
4. After approval and merge, `terraform apply` runs.

## What a domain gets

For a domain `alpha` in environment `dev`:

| Resource | Name / shape |
|---|---|
| ADLS container | `domain-alpha`, private, tagged through metadata |
| Access Connector | system-assigned managed identity, role `Storage Blob Data Contributor` scoped to that one container |
| Unity Catalog storage credential and external location | point at the container |
| Catalog | `alpha_dev`, with `storage_root` set to the external location (the metastore has no default storage root) |
| Schemas | `raw`, `curated` by default |
| Volume | managed volume `landing` in `raw` |
| Groups | `sg-dbx-alpha-dev-reader`, `sg-dbx-alpha-dev-engineer` (Entra groups, see below) |
| Grants | readers: `USE_CATALOG`, `USE_SCHEMA`, `SELECT`, `READ_VOLUME`. Engineers additionally `CREATE_TABLE`, `MODIFY`, `WRITE_VOLUME` |
| Cluster policy | node-type allowlist, autoscale and worker cap, autotermination, enforced tags `cost_centre`, `domain`, `environment`, `owner`. Only engineers may use it. |

## Repository layout

```
bootstrap/bootstrap.sh          one-off creation of the remote state backend
envs/dev/                       one folder = one environment = one state file
modules/domain_onboarding/      everything that is specific to one domain
domains/                        domain requests (YAML), one file per domain
src/dbx_platform/               validator package (rules, validation, CLI)
tests/                          pytest suite for the validator
```

## Design decisions

- **Three control planes, three provider configurations.** Azure Resource Manager (storage, access connector, role assignments), the Databricks *account* (groups, workspace assignment) and the Databricks *workspace* (catalogs, grants, policies). The module receives the providers from the caller through aliases.
- **The module owns only what is specific to one domain.** The storage account, workspace and resource group belong to the caller and are passed in. Removing a domain from the map therefore destroys that domain's resources and nothing shared.
- **One state file per environment**, selected with `-backend-config` files. The backend block cannot use variables.
- **Groups are owned by the identity process, not by this repo.** The module looks Entra groups up by name (read only) and registers them in the Databricks account with the Entra object ID as `external_id`. Group membership is managed in Entra. The pipeline identity therefore needs no directory write rights.
- **Grants are authoritative** (`databricks_grants`). Anything granted by hand outside Terraform on these objects will be removed on the next apply.
- **Ceilings are enforced in three places.** The validator (fast, readable feedback in the PR), module variable validation (defence if someone bypasses the validator) and the cluster policy (what Databricks actually enforces at runtime).
  The numbers are duplicated between the validator and the module. Production would generate one from the other or keep them in one policy file.
- **The node-type allowlist** is enforced by the validator and the cluster policy. The module only checks that the list is not empty.

## Operator guide

### Prerequisites

- Azure CLI signed in to the correct tenant and subscription, Terraform `>= 1.9`, Python `>= 3.9`.
- An existing Premium Azure Databricks workspace attached to a Unity Catalog metastore in the same region.
- Rights for the person (later: the pipeline identity) that applies:
  `Contributor` and `User Access Administrator` on the resource group, `Storage Blob Data Contributor` on the state storage,
  Databricks account admin, and admin rights in the workspace and metastore.
- Entra security groups for each domain, created by the identity process **before** the request is merged (names are in [domains/README.md](domains/README.md)).
  Automatic Identity Management must be enabled so that Entra groups can be used in Databricks.

### First run

```bash
az login
./bootstrap/bootstrap.sh            # creates the state backend, once per platform
cp envs/dev/terraform.tfvars.example envs/dev/terraform.tfvars   # fill in your values, the file is gitignored
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
dbx-platform validate domains/*.yaml -e dev -o envs/dev/domains.auto.tfvars.json
cd envs/dev && terraform init && terraform plan
```

Adjust the backend names in `envs/dev/backend.tf` to the storage account that the bootstrap script created.

### Developing the validator

```bash
pytest -q && ruff check . && ruff format --check .
```

## Known behaviour

- **Destroying a domain needs `force_destroy` in state first.** Terraform destroys with the values recorded in state. A Unity Catalog external location cannot be deleted while dependent objects exist (dropped managed volumes count). `allow_force_destroy` (default `true` in the sandbox, `false` in the module) sets `force_destroy` on the catalog and external location. Apply that setting before you destroy.
- **Entra groups appear in Databricks on demand.** With Automatic Identity Management, a group is synced when it is first referenced. The module registers it explicitly through `databricks_group`.
- **Role assignments can take a short time to propagate.** The role assignment sets `principal_type = "ServicePrincipal"`, which avoids most retries.
- **Region.** The sandbox runs in `germanywestcentral`. The Unity Catalog metastore is regional, so every workspace attached to it must be in the same region.

## Approval gate and its limit

The intended control is four-eyes: a pull request needs one approval from someone other than its author, and the apply job waits for approval of a protected `dev` environment.
GitHub does not allow the author of a pull request to approve it. This proof of concept has one person, so the branch protection rule is configured with an administrator bypass,
and the environment reviewer is the same person. **That is a manual checkpoint, not four-eyes.** With a second reviewer, the bypass is removed and nothing else changes.

## Sandbox versus production

| Topic | This PoC | Production |
|---|---|---|
| Storage redundancy | LRS | ZRS or GRS |
| Storage keys | shared key access still enabled | `shared_access_key_enabled = false` |
| Deletion safety | `force_destroy` available | `prevent_destroy`, `force_destroy = false` |
| Networking | Databricks-managed VNet, public access | VNet injection, private endpoints. Cannot be retrofitted onto an existing workspace. |
| Encryption keys | Microsoft-managed | Customer-managed keys. DBFS root encryption also cannot be added later. |
| Environments | `dev` only | separate state and credentials per environment |
| Modules | local path | versioned, from a registry or tagged repository |
| CI identity | one service principal, two federated credentials | separate plan (read) and apply (write) identities |
| Compute entitlements | not changed | remove cluster-create entitlement from the default `users` group, so policies cannot be bypassed |
| Plan hand-off | apply job plans again | reviewed plan stored in private storage and applied as is |
| Action versions | tags | pinned to commit SHAs |

## Non-goals

Real data, ETL, dbt, streaming, dashboards, multi-region, private endpoints and VNet injection, Entra ID Premium features.

## Roadmap (not built)

- `dbx-platform audit`: compare what exists in the workspace with what the repository declares and report drift.
- `terraform import` runbook for resources created by hand before this repository existed.
- A Databricks Asset Bundle as the consumer-side deployment path for jobs.
- A budget alert per cost centre, using the `cost_centre` tag.
