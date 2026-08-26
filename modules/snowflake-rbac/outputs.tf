output "functional_roles" {
  description = "Names of the functional roles users and services are granted."
  value       = { for k, v in snowflake_account_role.functional : k => v.name }
}

output "access_roles" {
  description = "Names of the access roles holding schema privileges."
  value       = { for k, v in snowflake_account_role.access : k => v.name }
}

output "dbt_service_user" {
  description = "Service user the dbt pipeline authenticates as."
  value       = snowflake_service_user.dbt.name
}

output "dbt_role" {
  description = "Role the dbt pipeline runs under."
  value       = snowflake_account_role.functional["TRANSFORMER"].name
}
