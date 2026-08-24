# One root configuration, local modules, no module registry (E2/E3). What this
# workspace runs is whatever the checked-out ref contains - deploy.yml checks
# out the immutable release tag, never a moving branch, so "identical
# configuration state to every environment" (P2/P3) is a property of the ref,
# not of a version pin rewritten here.
#
# deploy_version is passed in with -var by the deploy workflow and exists only
# to be stamped into Snowflake (module "environment"'s version_label) so the
# deployed version is queryable directly from the platform (E6), without a
# machine commit back to this repository (E5).

module "environment" {
  source = "../../modules/snowflake-environment"

  env                           = "tst"
  credit_quota                  = 5
  data_retention_days           = 1
  resource_monitor_notify_users = var.resource_monitor_notify_users
  version_label                 = var.deploy_version
}

module "rbac" {
  source = "../../modules/snowflake-rbac"

  env = "tst"

  database_raw       = module.environment.database_raw
  database_analytics = module.environment.database_analytics
  database_ops       = module.environment.database_ops

  warehouse_transform = module.environment.warehouse_transform
  warehouse_reporting = module.environment.warehouse_reporting

  dbt_service_user_public_key = var.dbt_service_user_public_key
  allow_developer_schemas     = false
}
