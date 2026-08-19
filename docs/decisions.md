# Decision record

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
