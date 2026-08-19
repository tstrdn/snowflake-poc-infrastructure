# The two version pins below are the deployment record for this environment.
# They are rewritten by .github/workflows/deploy-dev.yml (development) and
# .github/workflows/promote.yml (test and production), committed, and then
# applied - so "which version is production running?" is answered by reading
# this file rather than by digging through run history.
#
# Do not edit these by hand. Use the promote workflow.

module "environment" {
  source  = "trialsnowflake.jfrog.io/snowflake-poc-tf-modules__snowflakepoc/snowflake-environment/snowflake"
  version = "0.1.0" # managed by the deploy and promote workflows

  env                           = "prd"
  credit_quota                  = 10
  data_retention_days           = 7
  resource_monitor_notify_users = var.resource_monitor_notify_users
}

module "rbac" {
  source  = "trialsnowflake.jfrog.io/snowflake-poc-tf-modules__snowflakepoc/snowflake-rbac/snowflake"
  version = "0.1.0" # managed by the deploy and promote workflows

  env = "prd"

  database_raw       = module.environment.database_raw
  database_analytics = module.environment.database_analytics
  database_ops       = module.environment.database_ops

  warehouse_transform = module.environment.warehouse_transform
  warehouse_reporting = module.environment.warehouse_reporting

  dbt_service_user_public_key = var.dbt_service_user_public_key
  allow_developer_schemas     = false
}
