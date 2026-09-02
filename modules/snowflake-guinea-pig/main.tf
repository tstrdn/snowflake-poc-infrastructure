# The guinea pig: proves that the commit which was merged is the commit that is
# live in this account. Self-contained - it borrows nothing from the other
# modules. Rationale and acceptance criteria: docs/guinea-pig.md.

# A resource monitor is not optional: policy rule R3 requires every warehouse to
# have one, together with auto_suspend.
resource "snowflake_resource_monitor" "guinea_pig" {
  name         = "RM_GUINEA_PIG"
  credit_quota = 1

  frequency       = "MONTHLY"
  start_timestamp = "IMMEDIATELY"

  notify_triggers           = [75, 90]
  suspend_trigger           = 95
  suspend_immediate_trigger = 100
}

# What the reader queries with. Terraform writes with WH_TRANSFORM_XS instead -
# see the provider alias in envs/*/versions.tf.
resource "snowflake_warehouse" "guinea_pig" {
  name           = "WH_GUINEA_PIG_XS"
  comment        = "Guinea pig - reads only, carries no workload"
  warehouse_size = "XSMALL"
  warehouse_type = "STANDARD"

  auto_suspend        = 60
  auto_resume         = "true"
  initially_suspended = true

  resource_monitor                    = snowflake_resource_monitor.guinea_pig.name
  statement_timeout_in_seconds        = 300
  statement_queued_timeout_in_seconds = 600
}

resource "snowflake_database" "guinea_pig" {
  name    = "GUINEA_PIG"
  comment = "Guinea pig - pipeline evidence only, no business data"

  # Policy rule R5's minimum, and Standard Edition's ceiling.
  data_retention_time_in_days = 1
}

resource "snowflake_schema" "signal" {
  database = snowflake_database.guinea_pig.name
  name     = "SIGNAL"
  comment  = "Guinea pig - the deployment signal table"
}

resource "snowflake_account_role" "reader" {
  name    = "GUINEA_PIG_READER"
  comment = "Reads the guinea pig. Holds nothing else, anywhere."
}

# Rolls up to SYSADMIN, as module "rbac" does with its functional roles.
resource "snowflake_grant_account_role" "reader_to_sysadmin" {
  role_name        = snowflake_account_role.reader.name
  parent_role_name = "SYSADMIN"
}

locals {
  # snowflake_execute exposes no fully_qualified_name, so this string is the
  # only handle anything else has on the table.
  table = "${snowflake_schema.signal.fully_qualified_name}.\"DEPLOYMENT_SIGNAL\""
}

# Terraform tracks this statement, not the table it creates. Drop the table by
# hand and the next plan reports no changes. What that costs: docs/guinea-pig.md.
resource "snowflake_execute" "deployment_signal" {
  # actual_account and deployed_commit are what make this able to fail; without
  # them the constant rows look identical in every account.
  #
  # No COPY GRANTS: a changed statement forces replacement, and Terraform
  # destroys first, so the table is already gone when this runs. Access survives
  # through the future grant in grants.tf.
  execute = <<-SQL
    CREATE OR REPLACE TABLE ${local.table} AS
    SELECT
        v.subject_id,
        v.subject_name,
        v.subject_country,
        v.subject_rating,
        v.is_active,
        CURRENT_ACCOUNT()        AS actual_account,
        '${var.version_label}'   AS deployed_commit
    FROM (VALUES
        (1001, 'Guinea Pig Company Inc.',       'Germany', 'Low',    TRUE),
        (1002, 'International Guinea Partners', 'India',   'Medium', TRUE),
        (1003, 'Guinea Pig Associations Group', 'Spain',   'High',   FALSE)
    ) AS v (subject_id, subject_name, subject_country, subject_rating, is_active)
  SQL

  # Not validated until it runs, which is at teardown.
  revert = "DROP TABLE IF EXISTS ${local.table}"

  # Re-runs on every refresh, so a missing table shows up as an empty result.
  # It reports only - nothing re-runs on the strength of it.
  query = "SELECT COUNT(*) AS ROW_COUNT, MAX(DEPLOYED_COMMIT) AS DEPLOYED_COMMIT FROM ${local.table}"

  # The future grant must exist before the table, or the first one created here
  # would not pick it up.
  depends_on = [snowflake_grant_privileges_to_account_role.future_tables]
}
