output "table" {
  description = "Fully qualified name of the deployment signal table."
  value       = local.table
}

output "validation_query" {
  description = "Run as reader_role on warehouse. Acceptance criteria in docs/guinea-pig.md."
  value       = "SELECT * FROM ${local.table};"
}

output "reader_role" {
  description = "Role the validation query must be run as; running it as ACCOUNTADMIN proves nothing."
  value       = snowflake_account_role.reader.name
}

output "warehouse" {
  description = "Warehouse the reader role queries on."
  value       = snowflake_warehouse.guinea_pig.name
}

output "state" {
  description = "Row count and deployed commit as of the last refresh. Empty means the read query failed - most likely the table is gone."
  value       = snowflake_execute.deployment_signal.query_results
}

output "expected_commit" {
  description = "What deployed_commit must contain if this run took effect. Compare against Git, not the run's log."
  value       = var.version_label
}
