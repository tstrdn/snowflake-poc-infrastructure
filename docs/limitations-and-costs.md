# Limitations and costs

What the trial tiers constrain, what is genuinely unverified, and what changes
at production scale.

---

## Trial-tier constraints

| Constraint | Effect here | At production scale |
|---|---|---|
| Trial accounts have no External Network Access | `dbt deps` cannot run inside Snowflake, so packages are vendored into the artifact | Vendoring stays — it is what makes the artifact immutable |
| HCP Terraform free: 1 concurrent run per organization | Environment applies queue instead of running in parallel | Paid tiers lift this; three environments rarely apply simultaneously anyway |
| HCP Terraform free: 500 managed resources | Ample — this platform is roughly 60 resources per environment | Watch it as schemas and roles multiply |
| GitHub Free: gates need public repositories | Both repositories are public; `gitleaks` enforces that nothing secret lands | Disappears on Team or Enterprise |
| GitHub Free: 2,000 Actions minutes/month | Not a constraint — Terraform executes on HCP, dbt executes in Snowflake | Runners here mostly orchestrate |
| dbt project limit: 20,000 files | Not close, even with `dbt_packages` vendored | Watch if many large packages accumulate |
| No concurrent `EXECUTE DBT PROJECT` on one object | Deployments to an environment queue via workflow concurrency groups | Deploy duplicate project objects if genuine parallelism is needed |

---

## Snowflake cost profile

Compute is the only meaningful cost. Both warehouses are `XSMALL`, suspend after
60 seconds idle, and start suspended.

| Guardrail | Setting |
|---|---|
| Credit quota | 5/month in dev and test, 10/month in production (`RM_ENV`) |
| Notify | 75% and 90% of quota |
| Suspend, letting queries finish | 95% |
| Suspend immediately, cancelling queries | 100% |
| Statement timeout | 3,600 seconds |

The quota is a hard stop, not an alert. A runaway job cannot silently drain a
trial account.

The costs that surprise people are not the pipeline. They are ephemeral pull
request schemas that never get dropped — which is why teardown runs with
`always()` and `pr-cleanup.yml` exists as a backstop — and Time Travel retention,
set to 1 day in development and test and 7 in production.

---

## Verified, and not

Built and validated without access to your accounts:

- Both Terraform modules pass `terraform fmt`, `terraform validate` and `tflint`
  against the real `snowflakedb/snowflake` v2.19 provider.
- Root-configuration module wiring validates end to end.
- The dbt project parses; `sqlfluff` passes; the full model DAG was executed
  against the seed data in DuckDB with all 25 tests passing.
- The artifact cycle — build, checksum, upload shape, download, verify, unpack,
  parse in isolation — was run locally, including confirming that tampering is
  detected.
- Snowflake CLI flags were taken from `snow --help` on version 3.24.1, not from
  documentation.
- Module publishing to Artifactory, confirmed against the live instance:
  `jf tf p --namespace=snowflakepoc --provider=snowflake` publishes, and the
  registry serves the result at
  `/artifactory/api/terraform/<repo>/v1/modules/<namespace>/<name>/<provider>/<version>`.
- `bootstrap/generate_keypair.sh` and `set_registry_host.sh` were executed,
  including their failure paths.

Verified afterwards against the live development account:

- The full infrastructure pipeline end to end — publish, tag, version-pin
  commit past branch protection, remote apply on HCP, objects created in
  Snowflake.
- Key-pair authentication for `SVC_TERRAFORM`, via the fingerprint check in the
  runbook.

**Not verified, because it needs your accounts:**

- `snow dbt deploy` accepting a credential-free `profiles.yml`. This follows
  Snowflake's documented requirement that profiles define only database, role,
  schema and type, but it is the single most likely thing to need a tweak on
  first run.
- Snowsight Workspaces Git integration, which needs a Git API integration that
  may be restricted on trial accounts. If unavailable, local dbt Core
  development is unaffected.

---

## Found only against a live account

Three things that no amount of local validation could have caught. They are
listed because they are the shape of problem to expect when this pattern is
applied to another platform, not because they remain unfixed.

| Symptom | Cause | Fix |
|---|---|---|
| `Unsupported feature GRANT/REVOKE CREATE MATERIALIZED VIEW ON SCHEMA` | Materialized views are Enterprise Edition; these accounts are Standard | Removed the privilege. Note that Terraform issues all schema privileges as one `GRANT`, so a single unsupported privilege fails the whole statement and masks any others |
| `Invalid object type 'DBT_PROJECT' for privilege 'MODIFY'` | `MODIFY` is not valid for `DBT PROJECT` | Removed the future grant entirely. It was redundant: `TRANSFORMER` creates the project object and therefore owns it |
| `error looking up module versions: 401` | `terraform init` installs modules on the runner even in Remote execution mode | Runner now derives `TF_TOKEN_<host>` from `JF_URL` and authenticates to the registry too |

The first two were only reachable by applying against a real account of a
specific edition. `terraform validate` confirms a configuration is well-formed;
it cannot know which privileges your edition supports, or which apply to an
object type as new as `DBT PROJECT`.

---

## What to change before this is production

Roughly in order of importance:

1. **Narrow `SVC_TERRAFORM`.** It holds `ACCOUNTADMIN`. Replace with
   `SYSADMIN` + `SECURITYADMIN` plus specific account-level privileges.
2. **Remove the branch-protection bypass.** Have the promote workflows open a
   pull request rather than pushing the version pin directly, making promotion
   itself reviewable.
3. **Replace long-lived keys with workload identity.** Snowflake supports
   federated workload identity; GitHub OIDC would remove the stored private keys
   entirely.
4. **Add drift detection.** A scheduled `terraform plan` across all three
   environments catches manual changes made in Snowsight. Deliberately out of
   scope here.
5. **Add orchestration.** Deployment currently runs the project once. Production
   pipelines need a schedule — Snowflake Tasks calling `EXECUTE DBT PROJECT` —
   plus alerting on failure.
6. **Separate the approver from the owner.** The repository owner approves their
   own promotions in this PoC. Real separation of duties needs a distinct group.
7. **Add key rotation.** `generate_keypair.sh` supports rotation via
   `rsa_public_key_2`, but nothing schedules or enforces it.
