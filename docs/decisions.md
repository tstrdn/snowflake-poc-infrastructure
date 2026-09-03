# Decision record

> **Partially superseded.** The promotion model changed twice since most of
> this was written: modules moved from an Artifactory registry to local
> paths (some prose below still assumes the registry), and this repository's
> Terraform Enterprise workspaces moved from CLI-driven to VCS-driven - see
> decision 9 below, which **is** current.


The choices worth arguing about, and what would change them.

---

## 1. dbt runs natively in Snowflake, not on CI runners or dbt Cloud

**Decision.** Use dbt Projects on Snowflake: a `DBT PROJECT` object deployed
with `snow dbt deploy` and run with `EXECUTE DBT PROJECT`.

**Why.** No runner infrastructure to maintain, no dbt Cloud licence, and
engineers get a Git-connected browser IDE in Snowsight alongside the local
dbt Core path. Execution happens where the data is, under the role that invoked
it, so the security model is Snowflake's rather than a second one bolted on.

**Cost.** It is a newer capability (GA June 2026), and the Snowflake CLI's
surface is still moving — `--env-vars` and `--env-file-dir` appear in the
documentation but not in CLI 3.24.1, which is why per-environment values are
carried in `profiles.yml` targets instead.

**Revisit if.** You need dbt features the managed runtime does not support, or
you need to run dbt against something other than Snowflake.

---

## 2. HCP Terraform in Remote execution mode, triggered from GitHub Actions

**Decision.** GitHub Actions triggers runs; Terraform executes on HCP.

**Why.** Snowflake private keys stay in HCP workspace variables and never reach
the runner. Triggering and approval stay in GitHub, so the process has one front
door and one place to look for history.

**Alternative rejected.** VCS-driven runs, where HCP watches the repository
itself. It showcases HCP more fully but splits the process across two systems
with two approval mechanisms — a worse story to explain to a review board.

**Cost.** The free tier allows one concurrent run per organization, so
environment applies queue.

---

## 3. Promotion is a committed version pin, not a re-run of the build

**Decision.** Each environment's deployed version is a file in `main`:
`envs/<env>/modules.tf` for infrastructure, `deploy/<env>.version` for dbt. The
deploy workflows rewrite it, commit it, then deploy.

**Why.** "What is running in production?" should be answerable by reading the
repository. Run history rots, gets truncated, and cannot be diffed.

**Cost.** Something must be allowed to push those commits past branch
protection. `github-actions[bot]` cannot be a ruleset bypass actor on a free,
user-owned repository, so this uses a fine-grained PAT held as `GH_PUSH_TOKEN`
and the `Repository admin` bypass entry. Either way it is a real weakening of
the branch rules, accepted because the alternative — a deployment whose record
depends on run history — is worse.

**Alternative worth considering.** Have the promote workflow open a pull request
instead of pushing, making promotion itself reviewable and removing the bypass
entirely. Rejected here only because it adds a second approval step to a process
the brief asked to keep at dispatch-plus-approve.

**Two consequences reviewers ask about.** Both are properties of publishing and
then pinning, not defects, but they are easy to mistake for defects:

*The pull request plan does not preview module changes.* The speculative plan
runs against `envs/dev`, which pins the currently published module version — so
a change under `modules/` cannot appear in it, because it has not been published
yet. A module change is reviewed as code on the pull request, and as a plan when
it deploys to development. Pointing the plan at the local module source instead
would preview something other than what actually gets deployed, which is worse:
a plan you cannot trust is more dangerous than no plan.

*Environment-level parameters need a version bump to take effect.* Arguments in
`envs/<env>/modules.tf`, such as `credit_quota`, are only applied when a
deployment runs, and deployments are driven by releases. Changing one without
bumping `VERSION` leaves it committed but unapplied. Adding `envs/**` to the
release trigger would fix this, at the cost of making "a release" mean two
different things.

---

## 4. dbt dependencies are vendored into the artifact

**Decision.** CI runs `dbt deps` and ships `dbt_packages/` inside the tarball.

**Why.** Forced: `dbt deps` inside Snowflake requires External Network Access,
which trial accounts do not have. But it is also correct — a tarball that
resolves its own dependencies at deploy time is not immutable, because the same
version can mean different code later.

**Cost.** Artifacts are larger, and a package upgrade requires a new artifact
version rather than a silent re-resolve. Both are features.

---

## 5. Terraform modules are versioned as one set

**Decision.** `snowflake-environment` and `snowflake-rbac` share one `VERSION`
and publish together.

**Why.** RBAC grants reference objects the environment module creates. Allowing
independent versions would let an environment run a combination that was never
tested as a pair, and the failure mode — a grant against an object that does not
exist — is discovered at apply time in whichever environment drifted.

**Revisit if.** The module set grows past a handful and their release cadences
genuinely diverge.

**One suppressed policy check.** Checkov's `CKV_TF_1` demands a git commit hash
in every module source. It targets `git::` sources, where a tag can be moved and
a reference silently changes meaning. A registry source with `version = "0.1.4"`
provides the same guarantee by a different mechanism, so the check is skipped in
`pr-validate.yml` with that reasoning recorded inline.

Worth being precise about what is and is not guaranteed: `release.yml` refuses
to republish a version whose git tag already exists, which prevents the pipeline
from doing it. It does not prevent someone with Artifactory credentials from
overwriting a published version by hand. Turning on immutability for the
`snowflake-poc-tf-modules` repository is what would make the pin a storage-level
guarantee rather than a convention — and it is the honest answer to the question
`CKV_TF_1` is really asking.

---

## 6. Repositories are public

**Decision.** Both repositories are public.

**Why.** GitHub Free grants branch protection, rulesets and environment approval
gates only on public repositories, and those gates are the process. A private
repository would demonstrate a pipeline with the governance removed.

**Cost.** Nothing secret can ever be committed. `gitleaks` runs on every pull
request in both repositories to enforce that.

**Revisit if.** The organization moves to GitHub Team or Enterprise, at which
point this constraint disappears entirely.

---

## 7. One hand-made credential per account

**Decision.** `SVC_TERRAFORM` is created by `bootstrap.sql`. Everything else,
including `SVC_DBT`, is managed by Terraform.

**Why.** Terraform cannot create the identity it authenticates as, so exactly
one credential must be bootstrapped. Creating both service users by hand would
mean six manual setups across three accounts and would put the dbt service user
outside code review.

**Cost.** `SVC_DBT`'s public key passes through an HCP variable. It is a public
key, so this is not a secrecy problem, but it is a manual wiring step.

**Known weakness.** `bootstrap.sql` grants `ACCOUNTADMIN` to `SVC_TERRAFORM`.
Narrowing that to `SYSADMIN` + `SECURITYADMIN` plus specific account-level
privileges is the first hardening task beyond a proof of concept.

---

## 8. Static checks in CI use a separate throwaway profile

**Decision.** `ci/profiles.yml` exists purely so `dbt parse` and `sqlfluff` can
run on a runner.

**Why.** The deployed `profiles.yml` has no `account`, `user` or password,
because Snowflake's managed runtime supplies the connection. dbt Core running
standalone refuses to load a Snowflake profile without an `account`.

**Cost.** The deployed `profiles.yml` is not validated until deploy time. The
failure is immediate and obvious when it happens, so this is accepted rather
than worked around.

---

## 9. VCS-driven Terraform Enterprise, not CLI-driven or API-driven

**Decision.** Each of the three TFE workspaces is connected directly to this
GitHub repository and watches one branch: `snowflake-poc-dev` watches `main`,
`snowflake-poc-tst` watches `env/tst`, `snowflake-poc-prd` watches `env/prd`.
TFE plans and applies on its own, off any GitHub Actions runner, the moment a
watched branch moves. `promote.yml` no longer runs `terraform apply`, or even
`terraform plan` against the real workspace - it moves the target
environment's branch (Git only) and stops.

**Why.** This repository originally used CLI-driven runs: `terraform
init/plan/apply` executed on the GitHub runner, remotely against TFE, which
requires the *runner* to reach TFE directly. That connectivity cannot be
assumed here - see the open risk below. VCS-driven flips which party needs
to reach which: TFE reaches out to GitHub on its own (to clone, and to post
run status back as a commit/PR check), and GitHub calls TFE inbound only via
the webhook it registered when the workspace was connected. The runner is not
on either path - it never needs to reach TFE for a deployment to happen.

Promoting to test or production is now "move a Git branch to a chosen tag's
tree," not "run `terraform apply` with that tag checked out." Each promotion,
including a rollback, is a new commit (never a force-push) so the branch's
history stays a complete, append-only promotion log - see `promote.yml`'s
header comment.

**Cost - the CI-side G2 policy check lost its input.** It used to inspect the
JSON from the real `terraform plan` GitHub Actions ran directly. There is no
such plan on this runner anymore - TFE computes the real one, itself,
somewhere this runner cannot see. `policy-check.yml` now runs its own
throwaway local plan (cloud block stripped, fresh empty local state, real
Snowflake credentials duplicated into GitHub Environment secrets purely for
this) solely to read resource attributes for the five rules. It is checking
the same configuration the real run will apply, but it is a second, separate
plan, not the one TFE actually uses - a gap that would matter more if this
repository had TFE Sentinel/OPA policies (the actual, non-bypassable G2) to
fall back to; it does not, on this tier.

**Open risk - the untested direction.** VCS-driven trades "GitHub runner
reaches TFE" for "GitHub.com reaches TFE" (webhook delivery) and "TFE reaches
GitHub.com" (clone, status posting). Neither has been confirmed working in
this deployment - TFE runs privately in GCP, and whether GitHub's webhook
infrastructure can reach it, or whether TFE's egress can reach github.com,
is unverified as of this decision. If webhook delivery turns out not to
work, VCS-driven workspaces still function for on-demand runs (a human
starting one from the TFE UI, assuming the UI itself is reachable), but lose
the automatic "push and TFE reacts" behavior the whole design assumes. This
is not this repository's problem to solve; see `docs/limitations-and-costs.md`.

**Revisit if.** The GitHub-runner-to-TFE network path turns out to be the
easier one to open after all, or the org standardizes on API-driven runs
with a purpose-built trigger service positioned to reach TFE directly - in
either case, CLI/API-driven is a smaller workflow surface than what is here
now.

---

## 10. The guinea pig is a self-contained module

**Decision.** The change that demonstrates the first go-live is
`modules/snowflake-guinea-pig`, called from all three `envs/*/modules.tf`. It
creates its own resource monitor, warehouse, database, schema, table and role,
borrows nothing from module "environment" or module "rbac", and takes exactly
one input: the deployed commit.

**Why it is in this repository.** Its whole claim is that *this* delivery path
works. A separate repository with freshly created workspaces would demonstrate
that *a* path works, and would touch none of what is actually uncertain:
`promote.yml`, the branch-per-environment mechanic of decision 9, branch
protection, the release tag, the existing credentials. A guinea pig that avoids
the machinery it is meant to test is theatre.

**Why self-contained.** An earlier revision read through ANALYST and
`WH_REPORTING_XS`, which entangled a throwaway with the platform's real RBAC and
compute: a mistake in it, or an untidy removal, could reach objects that matter.
Its own role and its own warehouse mean the blast radius is the guinea pig and
nothing else, and teardown is one module block per environment. It also restores
a point the borrowed version had lost - the reader needs `USAGE` on a warehouse,
the privilege most often forgotten, and the one whose absence Snowflake reports
as "object does not exist" rather than "not permitted".

**Why one variable and not none.** `version_label` is what makes the guinea pig
able to fail: without it, three constant rows return identical output in every
account and a promotion that silently did nothing looks like one that worked. It
is runtime metadata injected by TFE, not a configuration knob, and a child
module cannot read a root variable - so it has to be passed. Nothing else is
parameterised.

**Cost - `snowflake_execute`.** The table is built by a `CREATE TABLE AS
SELECT`, not by a typed resource, so the guinea pig genuinely writes: storage, a
running warehouse, the deploying identity. The price is that Terraform tracks the
*statement*, not the table - drop the table by hand and the next plan reports no
changes. The `query` argument surfaces that as an empty `guinea_pig_state`
output, but nothing re-runs on the strength of it: visibility, not convergence.
This runs against the principle that state is read from the account, and is
accepted only because the object is a throwaway with no consumers. Three further
costs - an unvalidated `revert`, a drop-and-recreate window on every promotion,
and grants that survive only because they are future grants on the schema rather
than on the object - are in `docs/guinea-pig.md`. The pattern does not scale past
a guinea pig, and is not a precedent for real objects.

**Cost - a session warehouse.** Every other module here does metadata-only DDL,
which needs none; writing rows does. `envs/*/versions.tf` gains a
`snowflake.guinea_pig` provider alias carrying `WH_TRANSFORM_XS` as a literal,
because `snowflake_execute` forbids `USE WAREHOUSE` inside a statement. It names
the platform's transform warehouse rather than the guinea pig's own, because
provider configuration is resolved before any resource exists and naming a
warehouse this configuration creates would be circular. The default provider is
untouched, so no other module's session changes. On a brand-new account
`WH_TRANSFORM_XS` does not exist yet either, so a first bootstrap apply should
exclude the module.

---

## 11. Least privilege for the guinea pig

**Decision.** The `snowflake.guinea_pig` provider alias (`envs/*/versions.tf`)
runs as `PLATFORM_AUTOMATION`, not as the default provider's `ACCOUNTADMIN`.
`PLATFORM_AUTOMATION` is created once by hand in `bootstrap.sql`, rolled up to
`SYSADMIN`, and holds only `CREATE DATABASE` and `CREATE WAREHOUSE` on the
account - nothing else, and specifically not `MANAGE GRANTS`.

**Why this is enough without `MANAGE GRANTS`.** In a regular (non-managed-access)
schema, the role that owns an object can grant privileges on it to other roles by
virtue of `OWNERSHIP` alone - Snowflake's own documentation is explicit on this.
`PLATFORM_AUTOMATION` owns every object the guinea pig creates, so the reader
role's grants in `grants.tf`, including the future grant on the schema, need no
account-wide grant privilege. `MANAGE GRANTS` would let a role grant *any*
privilege on *any* object account-wide - close to `ACCOUNTADMIN` in practice -
and the guinea pig needs none of that reach.

**Why the resource monitor still is not delegated.** `CREATE RESOURCE MONITOR`
is exclusive to `ACCOUNTADMIN` and cannot be granted to any custom role, so
`RM_GUINEA_PIG` is created once in `bootstrap.sql` instead of in
`modules/snowflake-guinea-pig`. `PLATFORM_AUTOMATION` receives `MODIFY` on it,
which is enough for the warehouse resource to reference it and for Terraform to
manage its thresholds - just not to have created it. This is the one place the
module still depends on a manual, one-time ACCOUNTADMIN step.

**Why this is scoped to the guinea pig, not the platform.** The default provider
- everything in `envs/*` except this one alias - keeps running as `SVC_TERRAFORM`
/ `ACCOUNTADMIN`; narrowing that is explicitly out of scope here (`bootstrap.sql`
still calls it out as the first thing to do beyond a PoC). The guinea pig is
disposable and isolated by design (decision 10), which makes it the place to
trial a narrower role without risking the platform's own modules. If
`PLATFORM_AUTOMATION` proves out here, the same shape - an owning role scoped to
what it actually needs, plus a bootstrap-managed resource monitor - is the
template for narrowing `SVC_TERRAFORM` itself.
