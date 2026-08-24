# Compute governance -----------------------------------------------------------
#
# The monitor is created before the warehouses and referenced by them, so the
# credit ceiling exists from the first apply rather than being bolted on later.

resource "snowflake_resource_monitor" "env" {
  name         = "RM_ENV"
  credit_quota = var.credit_quota

  frequency       = "MONTHLY"
  start_timestamp = "IMMEDIATELY"

  notify_triggers           = [75, 90]
  suspend_trigger           = 95
  suspend_immediate_trigger = 100

  notify_users = var.resource_monitor_notify_users
}

# Compute ----------------------------------------------------------------------

resource "snowflake_warehouse" "transform" {
  name           = "WH_TRANSFORM_XS"
  comment        = "dbt transformations - ${upper(var.env)}"
  warehouse_size = var.transform_warehouse_size
  warehouse_type = "STANDARD"

  auto_suspend        = var.warehouse_auto_suspend_seconds
  auto_resume         = "true"
  initially_suspended = true

  resource_monitor                    = snowflake_resource_monitor.env.name
  statement_timeout_in_seconds        = var.statement_timeout_seconds
  statement_queued_timeout_in_seconds = 600
}

resource "snowflake_warehouse" "reporting" {
  name           = "WH_REPORTING_XS"
  comment        = "Downstream consumers and BI - ${upper(var.env)}"
  warehouse_size = var.reporting_warehouse_size
  warehouse_type = "STANDARD"

  auto_suspend        = var.warehouse_auto_suspend_seconds
  auto_resume         = "true"
  initially_suspended = true

  resource_monitor                    = snowflake_resource_monitor.env.name
  statement_timeout_in_seconds        = var.statement_timeout_seconds
  statement_queued_timeout_in_seconds = 600
}

# Storage ----------------------------------------------------------------------

resource "snowflake_database" "raw" {
  name                        = "RAW"
  comment                     = "Landing zone for source data - ${upper(var.env)}"
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_database" "analytics" {
  name                        = "ANALYTICS"
  comment                     = "dbt-managed models - ${upper(var.env)}"
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_database" "ops" {
  name = "OPS"
  # The version suffix is the version stamp (E6): the deployed infrastructure
  # version, queryable directly from Snowflake with DESCRIBE DATABASE OPS or
  # SHOW DATABASES LIKE 'OPS', rather than only from CI logs or a repo file.
  comment                     = "Platform operations: dbt project objects, pipeline metadata - ${upper(var.env)}${var.version_label != "" ? " - v${var.version_label}" : ""}"
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_schema" "jaffle_raw" {
  database = snowflake_database.raw.name
  name     = "JAFFLE_RAW"
  comment  = "Seeded source data for the Jaffle Shop demo"
}

resource "snowflake_schema" "jaffle_stg" {
  database = snowflake_database.analytics.name
  name     = "JAFFLE_STG"
  comment  = "dbt staging models"
}

resource "snowflake_schema" "jaffle_marts" {
  database = snowflake_database.analytics.name
  name     = "JAFFLE_MARTS"
  comment  = "dbt mart models"
}

# The DBT PROJECT object lives here, but is created by the dbt pipeline's
# `snow dbt deploy`, not by Terraform. Terraform owns the container and the
# grants; the project object's lifecycle belongs to the repo that produces it.
resource "snowflake_schema" "dbt_projects" {
  database = snowflake_database.ops.name
  name     = "DBT_PROJECTS"
  comment  = "DBT PROJECT objects deployed by the snowflake-poc-dbt pipeline"
}
