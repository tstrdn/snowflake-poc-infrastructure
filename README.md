# snowflake-poc-infrastructure

Terraform for the Snowflake platform: warehouses, databases, schemas, the role
hierarchy, and credit guardrails. One of the two promotion pipelines in this
proof of concept — the other is [`snowflake-poc-dbt`](../snowflake-poc-dbt).

## How a change reaches production

```
feature branch → PR (validate + plan) → merge → publish modules → DEV (auto)
                                                       ↓
                                         Promote workflow → TST (approval)
                                                       ↓
                                         Promote workflow → PRD (approval)
```

Modules are published to Artifactory as an immutable versioned set. Each
environment pins a version in `envs/<env>/modules.tf`, and the deploy workflows
rewrite that pin, commit it, then apply — so **the repository is the record of
what each environment runs**.

Rollback is the Promote workflow with an older version. There is no separate
rollback path because there is no separate operation.

## Layout

```
modules/
  snowflake-environment/   databases, schemas, warehouses, resource monitor
  snowflake-rbac/          access + functional roles, grants, SVC_DBT
envs/
  dev/ tst/ prd/           one HCP workspace each; differ only in tfvars
bootstrap/                 one-time per-account setup (not part of the process)
docs/                      architecture, process, decisions, runbook
VERSION                    the module set version — bump it when modules change
```

## Making a change

```bash
git checkout -b feature/add-reporting-warehouse
# edit modules/…
echo "0.2.0" > VERSION          # required: published versions are immutable
terraform fmt -recursive
git commit -am "feat: add a dedicated reporting warehouse"
gh pr create --fill
```

The pull request runs `fmt`, `validate`, `tflint`, Checkov and `gitleaks`,
checks that `VERSION` increased, and posts a speculative Terraform plan against
development as a comment. On merge, modules publish and development applies
automatically.

## Documentation

| | |
|---|---|
| [Architecture](docs/architecture.md) | Topology, object model, role model, service identities |
| [Process](docs/process.md) | Both pipelines, gates, rollback |
| [Bootstrap runbook](docs/runbook-bootstrap.md) | One-time setup, start here |
| [Decisions](docs/decisions.md) | Why it is built this way, and what would change it |
| [Limitations and costs](docs/limitations-and-costs.md) | Trial constraints, what is verified, what to fix before production |

## Setup

See the [bootstrap runbook](docs/runbook-bootstrap.md). In short: generate key
pairs, run `bootstrap.sql` once per account, create three HCP workspaces, create
two Artifactory repositories, then set GitHub secrets, environments and branch
protection.

## Requirements

Terraform ≥ 1.9, `snowflakedb/snowflake` provider ~> 2.19, an HCP Terraform
organization, and an Artifactory instance with a Terraform repository.
