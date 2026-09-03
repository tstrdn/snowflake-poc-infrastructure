# Compute governance -----------------------------------------------------------
#
# RM_ENV is created in bootstrap/bootstrap.sql, by hand, as ACCOUNTADMIN:
# resource monitor creation cannot be delegated to any custom role, including
# the PLATFORM_AUTOMATION role Terraform runs as (docs/decisions.md, decision
# 12). Referenced by name below; its credit quota is set per account there.

# Compute ----------------------------------------------------------------------

resource "snowflake_warehouse" "transform" {
  name           = "WH_TRANSFORM_XS"
  comment        = "dbt transformations - ${upper(var.env)}"
  warehouse_size = var.transform_warehouse_size
  warehouse_type = "STANDARD"

  auto_suspend        = var.warehouse_auto_suspend_seconds
  auto_resume         = "true"
  initially_suspended = true

  resource_monitor                    = "RM_ENV"
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

  resource_monitor                    = "RM_ENV"
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
  # The suffix is the version stamp (E6): what is deployed here, queryable
  # directly from Snowflake with SHOW DATABASES LIKE 'OPS' (DESCRIBE DATABASE
  # lists the schemas inside OPS, not OPS's own comment - it is not this),
  # rather than only from CI logs or a repo file.
  comment                     = "Platform operations: dbt project objects, pipeline metadata - ${upper(var.env)}${var.version_label != "" ? " - ${var.version_label}" : ""}"
  data_retention_time_in_days = var.data_retention_days
}

# The three schemas below are managed access schemas, and it is module "rbac"'s
# future grants that require it: on a standard schema, GRANT ... ON FUTURE needs
# the account-wide MANAGE GRANTS privilege, which PLATFORM_AUTOMATION does not
# hold; on a managed access schema the schema owner may set them (decision 12).
# It is also the arrangement rbac already assumes - all access decisions come
# from Terraform, not from whoever happens to create an object.
#
# The consequence to know about: inside these schemas, a role that creates a
# table no longer controls access to it. dbt models built by TRANSFORMER are
# governed by the rbac grants alone.
resource "snowflake_schema" "jaffle_raw" {
  database            = snowflake_database.raw.name
  name                = "JAFFLE_RAW"
  comment             = "Seeded source data for the Jaffle Shop demo"
  with_managed_access = "true"
}

resource "snowflake_schema" "jaffle_stg" {
  database            = snowflake_database.analytics.name
  name                = "JAFFLE_STG"
  comment             = "dbt staging models"
  with_managed_access = "true"
}

resource "snowflake_schema" "jaffle_marts" {
  database            = snowflake_database.analytics.name
  name                = "JAFFLE_MARTS"
  comment             = "dbt mart models"
  with_managed_access = "true"
}

# The DBT PROJECT object lives here, but is created by the dbt pipeline's
# `snow dbt deploy`, not by Terraform. Terraform owns the container and the
# grants; the project object's lifecycle belongs to the repo that produces it.
resource "snowflake_schema" "dbt_projects" {
  database = snowflake_database.ops.name
  name     = "DBT_PROJECTS"
  comment  = "DBT PROJECT objects deployed by the snowflake-poc-dbt pipeline"
}
