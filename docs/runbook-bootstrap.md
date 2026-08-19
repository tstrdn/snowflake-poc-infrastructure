# Bootstrap runbook

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

> **Note on privilege.** `bootstrap.sql` grants `ACCOUNTADMIN` to
> `SVC_TERRAFORM` so the PoC bootstrap is one reliable step. Narrowing this to
> `SYSADMIN` + `SECURITYADMIN` plus specific account-level privileges is the
> first hardening task beyond a proof of concept.

---

## 3. Artifactory: create the repositories

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

## 4. HCP Terraform: workspaces

Create three workspaces — `snowflake-poc-dev`, `snowflake-poc-tst`,
`snowflake-poc-prd` — each with:

- **Execution mode:** Remote. This is what keeps Snowflake private keys off the
  GitHub runner.
- **Version control:** none. Runs are triggered by GitHub Actions via the API,
  so that the whole process has one front door.

Per workspace, set these variables. **Category is not cosmetic** — HCP exports
environment variables as shell variables and rejects newlines in them, which is
why the PEM private key is a Terraform variable and everything else is not.

### Environment variables

| Variable | Sensitive | Value |
|---|---|---|
| `SNOWFLAKE_ORGANIZATION_NAME` | no | Your organization name |
| `SNOWFLAKE_ACCOUNT_NAME` | no | That environment's account name |
| `SNOWFLAKE_USER` | no | `SVC_TERRAFORM` |
| `SNOWFLAKE_AUTHENTICATOR` | no | `SNOWFLAKE_JWT` |
| `SNOWFLAKE_ROLE` | no | `ACCOUNTADMIN` |
| `TF_TOKEN_mycompany_jfrog_io` | **yes** | JFrog identity token |

### Terraform variables

| Variable | Sensitive | Value |
|---|---|---|
| `snowflake_private_key` | **yes** | Whole `keys/<env>/SVC_TERRAFORM.p8` file, `BEGIN`/`END` lines and line breaks intact |
| `dbt_service_user_public_key` | no | `keys/<env>/SVC_DBT.pub.oneline` — one line, no headers |
| `resource_monitor_notify_users` | no | Optional. e.g. `["PLATFORM_ADMIN"]`, HCL format enabled |

Eight variables in total, or nine with the optional one. There is deliberately
**no `SNOWFLAKE_PRIVATE_KEY` environment variable** — the provider reads the key
from `var.snowflake_private_key`, wired explicitly in `envs/<env>/versions.tf`.

Three things that reliably go wrong here:

- **`TF_TOKEN_*`** is how Terraform authenticates to the module registry, and the
  name encodes the host: dots become underscores, no scheme, no trailing slash.
  `mycompany.jfrog.io` becomes `TF_TOKEN_mycompany_jfrog_io`.
- **The two keys have opposite shapes.** The private key is a multi-line PEM
  *with* headers; the public key is a single line *without* them. Pasting the
  `.pub` instead of the `.pub.oneline` is the common slip.
- **Crossing environments.** Nothing rejects the `tst` key pasted into the `prd`
  workspace; it fails much later as a JWT error. Do one workspace at a time.

Finally, create a **user API token** in your HCP account settings — that is
`TF_API_TOKEN` below.

---

## 5. GitHub: secrets, variables and gates

### Repository secrets and variables

`snowflake-poc-infrastructure`:

| Name | Kind | Value |
|---|---|---|
| `TF_API_TOKEN` | secret | HCP user API token |
| `JF_URL` | secret | `https://mycompany.jfrog.io` |
| `JF_ACCESS_TOKEN` | secret | JFrog identity token |
| `GH_PUSH_TOKEN` | secret | Fine-grained PAT, Contents: read and write, both repositories |
| `TF_CLOUD_ORGANIZATION` | variable | Your HCP organization name |

`snowflake-poc-dbt`:

| Name | Kind | Value |
|---|---|---|
| `JF_URL` | secret | `https://mycompany.jfrog.io` |
| `JF_ACCESS_TOKEN` | secret | JFrog identity token |

### Environments

Create `dev`, `tst` and `prd` in **both** repositories.

In `snowflake-poc-dbt`, each environment carries its own copy of these three
secrets. The names are identical across environments — GitHub resolves the
right value from whichever environment the job declares, which is why the
workflows contain no `_DEV` or `_PRD` suffixes:

| Secret | Value |
|---|---|
| `SF_ACCOUNT` | `<organization>-<account_name>` for that environment |
| `SF_USER` | `SVC_DBT` |
| `SF_PRIVATE_KEY` | Contents of `keys/<env>/SVC_DBT.p8` |

This repository also needs the repository-level secrets `JF_URL`,
`JF_ACCESS_TOKEN` and `GH_PUSH_TOKEN`.

Protection rules:

| Environment | Required reviewers |
|---|---|
| `dev` | none |
| `tst` | repository owner |
| `prd` | repository owner |

### Branch protection

On `main` in both repositories, add a ruleset targeting `main`, Active, that
restricts deletions, blocks force pushes, and requires a pull request with one
approval.

**Leave "Require status checks" off initially.** GitHub only offers checks it has
already seen, and yours have never run. Add them after the first pull request:
`Format, lint and scan`, `Module version bumped`, `Plan against development`.

### The bypass

The deploy workflows commit the deployed version back to `main` —
`envs/<env>/modules.tf` here, `deploy/<env>.version` in the dbt repository — and
that commit *is* the deployment record. Something has to be allowed to push it.

`github-actions[bot]` **cannot** be a bypass actor on a free, user-owned
repository; it is not offered in the bypass list. The usable entries there are
`Deploy keys` and the role entries (`Repository admin`, `Maintain`, `Write`).

This PoC therefore uses a fine-grained personal access token:

1. Create a fine-grained PAT with **Contents: read and write**, scoped to both
   repositories. Ninety days is a reasonable expiry.
2. Store it as the `GH_PUSH_TOKEN` secret in both repositories.
3. Add **`Repository admin`** to the ruleset bypass list. The PAT acts as its
   owner, who holds that role.

`deploy.yml` passes `GH_PUSH_TOKEN` to `actions/checkout`, which persists the
credential so the later push uses it. `release.yml` is untouched: it pushes a
*tag*, and a branch ruleset does not restrict tags. Do not add a tag ruleset, or
that breaks too.

A deploy key per repository is the tidier alternative — repo-scoped, non-human,
no expiry — at the cost of SSH plumbing in the workflows.

Either way you now have an automation identity that can push to `main` without
review. That is a genuine weakening of the branch rules, accepted here because
the alternative is a deployment whose record depends on run history. Removing it
is hardening item 2 in `limitations-and-costs.md`.

---

## 6. First run

```bash
cd snowflake-poc-infrastructure
git checkout -b bootstrap-verification
# make a trivial change, e.g. bump credit_quota in modules/snowflake-environment
echo "0.1.1" > VERSION
git commit -am "chore: verify the pipeline"
git push -u origin bootstrap-verification
gh pr create --fill
```

Expect, in order:

1. **On the pull request** — format, validate, tflint, Checkov, gitleaks and the
   version-bump check all pass, and a Terraform plan appears as a comment.
2. **On merge** — modules publish to Artifactory, tag `v0.1.1` is created,
   `envs/dev/modules.tf` is bumped and committed, development applies.
3. **In Snowsight** — the databases, schemas, warehouses, roles and `SVC_DBT`
   exist in the development account.

Then repeat steps 2 and 4 for `tst` and `prd`, and use the **Promote** workflow
to roll `v0.1.1` to each. The approval gate should hold the job until you
approve it.

Once infrastructure is in place, do the same in `snowflake-poc-dbt`: open a pull
request, watch the ephemeral `ANALYTICS.PR_<n>` schema get built and dropped,
merge, and watch the artifact publish and deploy to development.

---

## 7. Verifying "build once, deploy to all"

After promoting the same dbt artifact version to all three environments, compare
the SHA256 reported in each deployment's job summary. All three must be
identical. That is the proof that production is running exactly what was tested,
rather than a rebuild that merely resembles it.
