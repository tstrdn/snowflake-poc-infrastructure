# Bootstrap runbook

> **Partially superseded.** Two redesigns since this was first written: (1)
> Terraform modules moved from an Artifactory registry to local paths, so
> `envs/*/modules.tf` no longer takes a version pin and there is no machine
> commit back to `main` — Section 3 below still describes the old registry
> and has not been corrected. (2) The three TFE workspaces moved from
> CLI-driven (Terraform runs on the GitHub runner, remotely executed) to
> VCS-driven (TFE plans and applies on its own, watching Git branches
> directly) — Sections 4-6 below **have** been rewritten to match; see
> `docs/decisions.md` for why. `GH_PUSH_TOKEN` is back under Section 5, with
> a narrower purpose than before: moving `env/tst`/`env/prd`, never `main`.


Setting up the platform from nothing. Roughly 60–90 minutes for all three
environments. Work through it once for `dev` and confirm the pipeline runs
end to end before repeating steps 2–4 for `tst` and `prd`.

Everything here is a one-time setup. Nothing in this document is part of the
day-to-day process.

---

## 1. Accounts and external services

| What | Where | Notes |
|---|---|---|
| Three Snowflake accounts | One organization, Azure, same region | `dev`, `tst`, `prd` |
| HCP Terraform organization | app.terraform.io | Free tier is sufficient |
| Artifactory repositories | Your JFrog instance | Two, created in step 3 |
| Two GitHub repositories | Public | `snowflake-poc-infrastructure`, `snowflake-poc-dbt` |

The repositories must be **public**. GitHub Free grants branch protection,
rulesets and environment approval gates only on public repositories, and those
are the gates the whole process depends on. Nothing secret goes in the code —
`gitleaks` runs on every pull request to keep it that way.

---

## 2. Snowflake: bootstrap each account

Per account. Start with development.

```bash
cd snowflake-poc-infrastructure/bootstrap

./generate_keypair.sh SVC_TERRAFORM dev
./generate_keypair.sh SVC_DBT dev
```

This writes to `bootstrap/keys/dev/`, which is git-ignored. Then:

1. Open a Snowsight worksheet in the **development** account as `ACCOUNTADMIN`.
2. Copy `bootstrap.sql`, replace `<PUBLIC_KEY>` with the contents of
   `keys/dev/SVC_TERRAFORM.pub.oneline`, and run it.
3. Confirm `SHOW USERS LIKE 'SVC_TERRAFORM'` returns one row with
   `type = SERVICE` and a non-null RSA key.

`SVC_TERRAFORM` is the only credential created by hand. `SVC_DBT` is created by
Terraform in step 5 — you generated its key pair now only because Terraform
needs the public half as an input.

> **Note on privilege.** `SVC_TERRAFORM` does **not** hold `ACCOUNTADMIN`. The
> script grants it `PLATFORM_AUTOMATION`, a role with four account-level `CREATE`
> privileges and `MODIFY` on the two resource monitors, and nothing else
> (docs/decisions.md, decision 12). The script itself must still be run as
> `ACCOUNTADMIN`, because creating a resource monitor requires it.

---

## 3. Artifactory: create the repositories

> This section describes the Terraform module registry, which no longer
> exists in this repository's design (local module paths replaced it - see
> `docs/decisions.md`). Left as-is rather than rewritten; the dbt artifact
> repository row below is still current. `set_registry_host.sh` and the
> `snowflake-poc-tf-modules` repository it describes should not be created.

Two repositories, no Docker involved:

| Key | Type | Holds |
|---|---|---|
| `snowflake-poc-tf-modules` | Terraform (local) | Published Terraform modules |
| `snowflake-poc-dbt-artifacts` | Generic (local) | `snowflake-poc-dbt-<version>.tgz` and checksums |

Create an **identity token** with read/write on both. That token is
`JF_ACCESS_TOKEN` in the GitHub secrets below.

Then point the Terraform configurations at your host:

```bash
cd snowflake-poc-infrastructure
./bootstrap/set_registry_host.sh mycompany.jfrog.io
git add envs/ && git commit -m "chore: point module sources at the module registry"
```

Terraform requires a module `source` to be a literal string, so the host is
baked into `envs/*/modules.tf` rather than passed as a variable. The script
rewrites all three at once.

---

## 4. Terraform Enterprise: workspaces

Create three workspaces — `snowflake-poc-dev`, `snowflake-poc-tst`,
`snowflake-poc-prd` — each **connected to version control**, not CLI-driven.
This repository moved off CLI-driven runs because the GitHub runner cannot be
assumed to reach TFE directly; see `docs/decisions.md` for the full reasoning
and its one open risk (whether GitHub can reach *this* TFE in reverse — the
direction VCS-driven actually depends on — is not yet confirmed).

For each workspace:

- **VCS provider:** this GitHub repository.
- **VCS branch:**
  - `snowflake-poc-dev` → `main`
  - `snowflake-poc-tst` → `env/tst`
  - `snowflake-poc-prd` → `env/prd`

  `env/tst` and `env/prd` do not exist until the first promotion creates them
  (Section 6) — connecting the workspace to a branch that does not exist yet
  is fine; TFE just has nothing to run until the branch appears.
- **Terraform Working Directory:** `envs/dev`, `envs/tst`, `envs/prd`
  respectively. **Set this at connection time, not after** — a workspace
  without it only sees the directory a CLI-driven run was invoked from, which
  is irrelevant here, but an unset Working Directory on a VCS-driven
  workspace plans the repository root instead of the environment's config and
  fails to find a root module at all.
- **Apply method:** Auto apply for `snowflake-poc-dev`, Manual apply for
  `snowflake-poc-tst` and `snowflake-poc-prd` — matches "never auto-apply in
  production" and gives a human (or promote.yml's operator) a checkpoint
  before test and prod actually change, since GitHub Environment approval no
  longer gates this (see `promote.yml`'s header comment on the PoC's
  approval-gate scope decision).
- **Automatic run triggering:** default ("Always trigger runs") is fine here
  — each workspace only ever sees pushes to the one branch it is connected
  to, so there is no cross-environment noise to filter with trigger patterns.

Per workspace, set these Terraform variables (category matters: HCP/TFE
exports environment variables as shell variables and rejects newlines, which
is why the PEM private key is a Terraform variable and the rest are not):

### Environment variables

| Variable | Sensitive | Value |
|---|---|---|
| `SNOWFLAKE_ORGANIZATION_NAME` | no | Your organization name |
| `SNOWFLAKE_ACCOUNT_NAME` | no | That environment's account name |
| `SNOWFLAKE_USER` | no | `SVC_TERRAFORM` |
| `SNOWFLAKE_AUTHENTICATOR` | no | `SNOWFLAKE_JWT` |

There is deliberately no `SNOWFLAKE_ROLE` here: the role is set in
`envs/*/versions.tf` so that the identity a run applies under is reviewable in
version control rather than in a workspace setting. On a workspace that predates
this, **delete** any `SNOWFLAKE_ROLE` variable — the explicit provider argument
already wins, so a leftover value only misleads whoever reads it next.

### Terraform variables

| Variable | Sensitive | Value |
|---|---|---|
| `snowflake_private_key` | **yes** | Whole `keys/<env>/SVC_TERRAFORM.p8` file, `BEGIN`/`END` lines and line breaks intact |
| `dbt_service_user_public_key` | no | `keys/<env>/SVC_DBT.pub.oneline` — one line, no headers |

Seven variables in total, or eight with the optional one — no `TF_TOKEN_*`
variable and no `TF_API_TOKEN` anymore: nothing in CI calls the TFE API at
all now (policy-check.yml's plan is local and TFE-independent by design —
see `docs/decisions.md`), and there is no module registry left to
authenticate to. There is also deliberately **no `SNOWFLAKE_PRIVATE_KEY`
environment variable** — the provider reads the key from
`var.snowflake_private_key`, wired explicitly in `envs/<env>/versions.tf`.

Two things that reliably go wrong here:

- **The two keys have opposite shapes.** The private key is a multi-line PEM
  *with* headers; the public key is a single line *without* them. Pasting the
  `.pub` instead of the `.pub.oneline` is the common slip.
- **Crossing environments.** Nothing rejects the `tst` key pasted into the `prd`
  workspace; it fails much later as a JWT error. Do one workspace at a time.

---

## 5. GitHub: secrets, variables and gates

### Repository secrets and variables

`snowflake-poc-infrastructure`:

| Name | Kind | Value |
|---|---|---|
| `GH_PUSH_TOKEN` | secret | Fine-grained PAT, Contents: read and write, this repository — moves `env/tst`/`env/prd`, never `main` |
| `DBT_SERVICE_USER_PUBLIC_KEY` | variable | Same value as the `dbt_service_user_public_key` TFE Terraform variable, per environment below |

`JF_URL`/`JF_ACCESS_TOKEN`/`TF_CLOUD_ORGANIZATION`/`TF_API_TOKEN` are not
needed by this repository's workflows — no module registry, no CI-driven TFE
run (Section 4, `docs/decisions.md`).

This repository also needs the **same** `SNOWFLAKE_ORGANIZATION_NAME`,
`SNOWFLAKE_ACCOUNT_NAME`, `SNOWFLAKE_USER` and `SNOWFLAKE_PRIVATE_KEY` values
already set as TFE workspace variables in Section 4, set *again* here as
GitHub Environment secrets — one full set per `dev`/`tst`/`prd` Environment
(below). This is genuine duplication of the same `SVC_TERRAFORM` key
material into two places, not two different credentials: `policy-check.yml`
plans directly against Snowflake, independent of and parallel to the real
TFE-driven plan, precisely because it cannot assume it can reach TFE either
(`docs/decisions.md`).

`snowflake-poc-dbt`:

| Name | Kind | Value |
|---|---|---|
| `JF_URL` | secret | `https://mycompany.jfrog.io` |
| `JF_ACCESS_TOKEN` | secret | JFrog identity token |

### Environments

Create `dev`, `tst` and `prd` in **both** repositories.

In `snowflake-poc-infrastructure`, each environment carries its own copy of
the four `SNOWFLAKE_*` secrets from Section 4 (the `SVC_TERRAFORM` key
material, duplicated so `policy-check.yml` can plan directly against
Snowflake without going through TFE):

| Secret | Value |
|---|---|
| `SNOWFLAKE_ORGANIZATION_NAME` | Your organization name |
| `SNOWFLAKE_ACCOUNT_NAME` | That environment's account name |
| `SNOWFLAKE_USER` | `SVC_TERRAFORM` |
| `SNOWFLAKE_PRIVATE_KEY` | Contents of `keys/<env>/SVC_TERRAFORM.p8` |

In `snowflake-poc-dbt`, each environment carries its own copy of these three
secrets. The names are identical across environments — GitHub resolves the
right value from whichever environment the job declares, which is why the
workflows contain no `_DEV` or `_PRD` suffixes:

| Secret | Value |
|---|---|
| `SF_ACCOUNT` | `<organization>-<account_name>` for that environment |
| `SF_USER` | `SVC_DBT` |
| `SF_PRIVATE_KEY` | Contents of `keys/<env>/SVC_DBT.p8` |

That repository also needs the repository-level secrets `JF_URL` and
`JF_ACCESS_TOKEN` (its artifact publish/download still goes through
Artifactory - only this repository's Terraform track moved off it).

Protection rules:

| Environment | Required reviewers |
|---|---|
| `dev` | none |
| `tst` | repository owner |
| `prd` | repository owner |

### Branch protection

On `main` in both repositories, add a ruleset targeting `main`, Active, that
restricts deletions, blocks force pushes, and requires a pull request with one
approval. **No bypass entry is needed on this ruleset in either repository** —
nothing pushes to `main` from a workflow anymore in either track.

**Leave "Require status checks" off initially.** GitHub only offers checks it has
already seen, and yours have never run. Add them after the first pull request —
in `snowflake-poc-infrastructure`: `Format, lint and scan`, `VERSION bumped`,
`Policy check`.

### `env/tst` and `env/prd`: a second, separate ruleset

`snowflake-poc-infrastructure` only. `promote.yml` moves these two branches by
pushing a new commit (never force-pushing — see its header comment on
rollback), and they exist for no other reason: nobody should commit to them
by hand, since a hand-made commit here would silently become what TFE applies
to test or production.

1. Add a ruleset targeting `env/*`, Active, that restricts deletions, blocks
   force pushes, and **requires a pull request** — this is what stops a
   direct human push, not what `promote.yml` goes through.
2. Create a fine-grained PAT with **Contents: read and write**, scoped to this
   repository. Ninety days is a reasonable expiry.
3. Store it as the `GH_PUSH_TOKEN` repository secret.
4. Add **`Repository admin`** to this ruleset's bypass list (not `main`'s -
   see above). The PAT acts as its owner, who holds that role, and
   `promote.yml` passes it to `actions/checkout` so its later push carries
   that identity.

A deploy key or a dedicated GitHub App installation is the tidier long-term
alternative to a personal PAT here - repo-scoped, non-human, no expiry - at
the cost of extra setup for a PoC. Either way, `env/tst` and `env/prd` end up
writable only by `promote.yml`'s run, not by any person's normal `git push` -
tighter than the old `main`-bypass this section used to describe, not looser.

---

## 6. First run

```bash
cd snowflake-poc-infrastructure
git checkout -b bootstrap-verification
# make a trivial change, e.g. bump data_retention_days in envs/dev/modules.tf
echo "0.1.1" > VERSION
git commit -am "chore: verify the pipeline"
git push -u origin bootstrap-verification
gh pr create --fill
```

Expect, in order:

1. **On the pull request** — format, validate, tflint, Checkov, gitleaks and the
   version-bump check all pass, and `policy-check.yml`'s throwaway plan passes.
   If TFE can in fact reach this GitHub repository (Section 4's open risk),
   TFE's own speculative plan also appears as a status check on the PR,
   independent of anything in this repository's Actions runs.
2. **On merge** — tag `v0.1.1` is created. Nothing in this repository pushes
   anywhere else: `snowflake-poc-dev` is watching `main` directly and applies
   on its own, off this runner. Check its run in the TFE UI.
3. **In Snowsight** — the databases, schemas, warehouses, roles and `SVC_DBT`
   exist in the development account.

Then run the **Promote** workflow for `tst` with version `0.1.1`. This
creates `env/tst` for the first time (Section 4 already has
`snowflake-poc-tst` watching it) and moves it to the tag's tree, which is what
gives `snowflake-poc-tst` its first-ever plan to apply — approve it manually
in the TFE UI, since `tst` is Manual apply. Repeat for `prd`.

Once infrastructure is in place, do the same in `snowflake-poc-dbt`: open a pull
request, watch the ephemeral `ANALYTICS.PR_<n>` schema get built and dropped,
merge, and watch the artifact publish and deploy to development.

---

## 7. Verifying "build once, deploy to all"

After promoting the same dbt artifact version to all three environments, compare
the SHA256 reported in each deployment's job summary. All three must be
identical. That is the proof that production is running exactly what was tested,
rather than a rebuild that merely resembles it.
