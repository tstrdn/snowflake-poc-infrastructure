# Developer guide

For data engineers working on models day to day. Nothing here involves
Terraform — infrastructure changes go through `snowflake-poc-infrastructure`.

---

## Two ways to develop

Both build into **your own schema in the development account**, never into the
shared `JAFFLE_STG` or `JAFFLE_MARTS`. The `generate_schema_name` macro enforces
this: for the `sandbox` and `ci` targets it collapses the custom schemas into
the single target schema, so your work physically cannot land in a shared one.

### Snowsight Workspaces

A Git-connected browser IDE inside Snowflake. Edit models, preview results, run
and test against your own schema, commit and open a pull request — no local
setup at all.

Connect the workspace to `snowflake-poc-dbt` and work on a feature branch. This
depends on a Git API integration being available on the account; if it is not,
use the local path below.

### Local dbt Core

```bash
git clone https://github.com/<org>/snowflake-poc-dbt
cd snowflake-poc-dbt

python -m venv .venv && source .venv/bin/activate
pip install -r requirements-ci.txt

cp dev/profiles.yml.example dev/profiles.yml
# edit dev/profiles.yml: account, user, and your schema DBT_<YOURNAME>

dbt deps
dbt build --profiles-dir dev --target sandbox
```

`dev/profiles.yml` is git-ignored. Credentials never belong in the repository —
`gitleaks` runs on every pull request, and the repository is public.

> The root `profiles.yml` is deliberately credential-free: it is deployed into
> Snowflake as part of the artifact, where the connection comes from the session
> that invoked the project. That is why local development uses a separate file.

---

## The everyday loop

```bash
git checkout -b feature/add-customer-segments

dbt build --profiles-dir dev --target sandbox --select +my_new_model
sqlfluff lint models/ --templater jinja

echo "0.2.0" > VERSION        # required: artifacts are immutable
git commit -am "feat: add customer segment model"
gh pr create --fill
```

On the pull request, CI lints and parses, then deploys your branch as
`JAFFLE_SHOP_PR_<n>` and runs a full `dbt build` into `ANALYTICS.PR_<n>` in the
development account — seeds, models and tests. Both are dropped when the run
finishes, and again when the pull request closes.

After merge, the artifact publishes and deploys to development automatically.
Test and production are separate, approval-gated promotions.

---

## Useful selectors

```bash
dbt build --select my_model+          # the model and everything downstream
dbt build --select +my_model          # the model and everything it depends on
dbt build --select state:modified+    # what changed and its dependents
dbt test  --select marts              # tests for one layer
dbt run   --full-refresh --select my_model
```

---

## Conventions

| | |
|---|---|
| Staging models | `stg_<source>`, one per source table, renaming and casting only |
| Mart models | Business nouns: `customers`, `orders` |
| Materialization | Staging is a view, marts are tables — set in `dbt_project.yml`, not per model |
| Every model | Needs a description and a tested primary key |
| Personal schema | `DBT_<YOURNAME>` |
| SQL style | lowercase keywords, leading commas avoided, `sqlfluff` is the arbiter |

Payment methods are driven by the `payment_methods` variable in
`dbt_project.yml`. Adding one adds a column to the `orders` mart — change it in
one place, not in the SQL.

---

## When something fails

| Symptom | Cause |
|---|---|
| `VERSION must increase` | Bump `VERSION`; artifacts are immutable |
| `Object does not exist` for a schema | Schema creation is Terraform's job — open a PR on the infrastructure repository |
| Pull request build fails on a grant | `TRANSFORMER` lacks a privilege; also an infrastructure change |
| `sqlfluff` disagrees with you | `sqlfluff fix models/ --templater jinja` |
| Checksum mismatch on deploy | Stop. The artifact is not what was published — do not retry, investigate |
