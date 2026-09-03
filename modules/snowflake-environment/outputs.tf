output "database_raw" {
  description = "Name of the raw/landing database."
  value       = snowflake_database.raw.name
}

output "database_analytics" {
  description = "Name of the dbt-managed database."
  value       = snowflake_database.analytics.name
}

output "database_ops" {
  description = "Name of the platform operations database."
  value       = snowflake_database.ops.name
}

output "schema_jaffle_raw" {
  description = "Fully qualified name of the seeded source schema."
  value       = "${snowflake_database.raw.name}.${snowflake_schema.jaffle_raw.name}"
}

output "schema_dbt_projects" {
  description = "Fully qualified schema the dbt pipeline deploys DBT PROJECT objects into."
  value       = "${snowflake_database.ops.name}.${snowflake_schema.dbt_projects.name}"
}

output "warehouse_transform" {
  description = "Warehouse dbt builds with."
  value       = snowflake_warehouse.transform.name
}

output "warehouse_reporting" {
  description = "Warehouse downstream consumers query with."
  value       = snowflake_warehouse.reporting.name
}

output "resource_monitor" {
  description = "Resource monitor guarding both warehouses. Created in bootstrap.sql, not by this module."
  value       = "RM_ENV"
}

output "deployed_version" {
  description = "Version stamped onto this environment by the deploying workflow (E6). Empty if none was passed."
  value       = var.version_label
}
