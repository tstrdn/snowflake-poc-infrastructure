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
