# The guinea pig

A deliberately trivial, deliberately temporary change whose only job is to make
one question answerable from Snowflake itself:

> Is the commit that was merged the commit that is live in this account?

It carries no business data, nothing depends on it, and it is meant to be
removed once the pipeline has been demonstrated. It lives in
`modules/snowflake-guinea-pig`, called from all three `envs/*/modules.tf`, and
takes one input: the deployed commit.

## What it proves

It travels the real path — pull request, `main`, TFE run, `promote.yml`, the
next branch. A statement typed into a worksheet proves that Snowflake works,
which was never in doubt; it proves nothing about the pipeline.

A green run plus a passing validation query establishes that Terraform
Enterprise reaches the account and can authenticate to it, that a change
promotes from one account to the next, that grants applied by the pipeline work
for a role that is not `ACCOUNTADMIN`, that a frontend can connect and read —
and, the one that matters, **that the build which is live is the build that was
merged**.

## Why it can fail

Three constant rows return byte-identical output in `dev`, `tst` and `prd`. If
that were all the table contained, a promotion that silently did nothing would
be indistinguishable from one that worked: the query returns rows either way,
and everyone goes home satisfied. A test that cannot fail says nothing when it
passes.

So every row carries two markers:

| Column | Answers | Catches |
|---|---|---|
| `deployed_commit` | which build is here | a promotion that never ran, or ran an older tree |
| `actual_account` | which account this really is, via `CURRENT_ACCOUNT()` | a workspace wired to the wrong account |

`deployed_commit` is the same `TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA` that
module `environment` stamps onto the `OPS` database comment (E6). The guinea pig
does not introduce a second marker — it makes the existing one readable through
an ordinary `SELECT`, which is what a frontend demo needs.

The TFE run history proves what was **sent**. These columns prove what
**arrived**. Only the second is evidence.

## What it does not prove

- **Nothing about performance, cost or concurrency.** Three rows on an XSMALL
  warehouse is not a load test.
- **Nothing about the frontend beyond "it can connect and read".**
- **Nothing about dbt.** The write here is a `CREATE TABLE AS SELECT` issued by
  Terraform under the platform service identity. The real write path is a dbt
  project executing under its own role, and it is not this.

It does exercise the write path in the narrow sense that matters for a go-live
demo: rows are materialised in storage, on a running warehouse, under the
deploying identity.

## What it creates

Everything it needs, and nothing it does not own:

| Object | Name |
|---|---|
| Resource monitor | `RM_GUINEA_PIG` (1 credit) — created by hand in `bootstrap.sql`, not by this module |
| Warehouse | `WH_GUINEA_PIG_XS` (XSMALL, auto-suspend 60s) |
| Database | `GUINEA_PIG` |
| Schema | `GUINEA_PIG.SIGNAL` |
| Table | `GUINEA_PIG.SIGNAL.DEPLOYMENT_SIGNAL` |
| Role | `GUINEA_PIG_READER`, granted to `SYSADMIN` |

It borrows nothing from `module.environment` or `module.rbac`, and takes no
input other than `version_label`. A mistake here, or an untidy removal, cannot
reach the platform's real RBAC or compute.

Deploys as `PLATFORM_AUTOMATION`, not `ACCOUNTADMIN` — a role created once in
`bootstrap.sql` holding only `CREATE DATABASE`, `CREATE WAREHOUSE` and
`CREATE ROLE`, no `MANAGE GRANTS` (docs/decisions.md, decision 11). It owns
everything above and grants the reader role from that ownership, not from an
account-wide grant privilege. The one exception is the resource monitor:
`CREATE RESOURCE MONITOR` cannot be delegated to any custom role, so
`RM_GUINEA_PIG` is the one object here that still requires a manual
`ACCOUNTADMIN` step.

In an account where the guinea pig already deployed under the old, unrestricted
role, switching the provider alias alone is not enough — `PLATFORM_AUTOMATION`
does not retroactively own objects an earlier identity created, and ownership is
where its `CREATE TABLE` on the schema comes from. That account needs a
one-time `GRANT OWNERSHIP` transfer as `ACCOUNTADMIN`; see decision 11 for the
exact statements.

## Acceptance criteria

Run as **`GUINEA_PIG_READER`**, not as `ACCOUNTADMIN` — the privileged role
already holds everything being tested, so it cannot fail the way a real reader
would:

```sql
USE ROLE GUINEA_PIG_READER;
USE WAREHOUSE WH_GUINEA_PIG_XS;
SELECT * FROM GUINEA_PIG.SIGNAL.DEPLOYMENT_SIGNAL;
```

It passes only when all four hold:

1. Three rows come back.
2. `deployed_commit` equals the SHA of the commit that was merged. Compare
   against Git, not against the pipeline's own log.
3. `actual_account` is the account you expect for this environment. Record the
   three account locators once and check against them — this is the failure
   nobody looks for.
4. The query succeeds **as `GUINEA_PIG_READER`**. If it fails with *"Object does
   not exist, or operation cannot be performed"*, the missing privilege is
   almost certainly `USAGE` somewhere on the path: Snowflake hides objects a
   role cannot see, so "not permitted" is reported as "not there".

"The rows came back" is not a pass. "The rows came back and `deployed_commit` is
yesterday's" is a failure, and it is the exact failure the guinea pig exists to
catch.

Outside a real TFE run `TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA` is empty, so
criterion 2 does not apply to a local plan.

## What `snowflake_execute` costs

The table is created by `snowflake_execute` rather than a typed resource. What
that buys is real — rows are actually written, which a view could never do. What
it costs, in descending order of how much it will hurt:

**1. Terraform is blind to what the statement did.** The provider tracks the
*statement*, not the table. Drop the table by hand and the next `plan` reports no
changes, because `execute` is unchanged. This runs directly against the
principle that state is read from the account.

The partial mitigation is the `query` argument, surfaced as the
`guinea_pig_state` output. It re-runs on every refresh, so a missing table shows
up as an empty result — but it only *reports*: nothing re-runs, because the
statement has not changed. **Visibility, not convergence.** A wrong
`guinea_pig_state` is a finding for a human, not something the next apply
repairs.

**2. `revert` is not validated until it runs.** It is invoked on destroy and on
every replacement. A wrong `revert` is discovered at teardown — the least
convenient moment — and the provider's own documentation shows this failure mode
rather than preventing it.

**3. Every promotion drops and recreates the table.** The deployed commit lives
inside `execute`, and any change there forces replacement: `revert` drops the
table, then `execute` rebuilds it. There is a window in which the table does not
exist. For a guinea pig with no consumers that is irrelevant; for anything real
it is precisely why a clone-build-verify-swap pattern exists.

**4. Grants would be lost, and are only saved by a workaround.** Because
replacement destroys first, `COPY GRANTS` has nothing to copy from. `SELECT`
survives only because it is a **future grant on the schema**, not a grant on the
object. Without that, the reader would lose access on every single deployment.

**5. No object identity.** `snowflake_execute` exposes no
`fully_qualified_name`, since the provider cannot know what the statement
created. The table's name is a locally assembled string, and import is by random
UUID rather than by object.

**6. The statement is not treated as sensitive.** `execute`, `revert`, `query`
and `query_results` are unmarked in the provider, so they appear in logs and in
state as written. Harmless here — there are no secrets in it — but not a
property to rely on elsewhere.

A typed `snowflake_view` had none of 1 through 5, and could not write a row. The
trade was made knowingly.

## The session warehouse

Writing rows needs a warehouse in the session, and the default provider
deliberately has none — every other module here does metadata-only DDL.
`snowflake_execute`'s documentation forbids `USE WAREHOUSE` inside a statement
and points at provider aliases instead, so `envs/*/versions.tf` defines a
`snowflake.guinea_pig` alias.

It names `WH_TRANSFORM_XS`, not the guinea pig's own warehouse, because provider
configuration is resolved before any resource exists — naming a warehouse this
same configuration creates would be circular. So: `WH_TRANSFORM_XS` is what
Terraform *writes* with, `WH_GUINEA_PIG_XS` is what the reader *queries* with.

On a brand-new account neither exists yet, so a first bootstrap apply should
exclude the module and add it back afterwards.

## Teardown

Delete the `module "guinea_pig"` block and the `guinea_pig_*` outputs from all
three environments, plus the `snowflake.guinea_pig` provider alias and
`modules/snowflake-guinea-pig`, then let the change promote normally. Removing
the module runs `revert` (`DROP TABLE IF EXISTS`) and destroys the schema,
database, role and warehouse. Nothing else references any of them.

`RM_GUINEA_PIG` and the `PLATFORM_AUTOMATION` role live in `bootstrap.sql`, not
in Terraform state, so they survive the module removal and need a manual
`DROP RESOURCE MONITOR` / `DROP ROLE` as `ACCOUNTADMIN` per account — unless
`PLATFORM_AUTOMATION` has been carried forward as the template for narrowing
`SVC_TERRAFORM` itself, in which case leave it and only drop the monitor.

Agree the teardown date when the guinea pig is agreed. One left running for a
year becomes something someone eventually believes in.
