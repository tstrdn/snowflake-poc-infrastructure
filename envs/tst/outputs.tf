output "dbt_service_user" {
  description = "Service user the dbt pipeline authenticates as."
  value       = module.rbac.dbt_service_user
}

output "dbt_role" {
  description = "Role the dbt pipeline runs under."
  value       = module.rbac.dbt_role
}

output "dbt_project_schema" {
  description = "Schema the dbt pipeline deploys DBT PROJECT objects into."
  value       = module.environment.schema_dbt_projects
}

output "warehouse_transform" {
  description = "Warehouse dbt builds with."
  value       = module.environment.warehouse_transform
}

output "guinea_pig_table" {
  description = "Table proving what is deployed in this account."
  value       = module.guinea_pig.table
}

output "guinea_pig_validation_query" {
  description = "Run as guinea_pig_reader_role on guinea_pig_warehouse. Criteria in docs/guinea-pig.md."
  value       = module.guinea_pig.validation_query
}

output "guinea_pig_reader_role" {
  description = "Role the guinea pig validation query must be run as."
  value       = module.guinea_pig.reader_role
}

output "guinea_pig_warehouse" {
  description = "Warehouse the guinea pig reader role queries on."
  value       = module.guinea_pig.warehouse
}

output "guinea_pig_state" {
  description = "Row count and deployed commit as of the last refresh. Empty means the table is probably gone; Terraform will not rebuild it on that basis."
  value       = module.guinea_pig.state
}

output "guinea_pig_expected_commit" {
  description = "What deployed_commit must contain if this run took effect."
  value       = module.guinea_pig.expected_commit
}
