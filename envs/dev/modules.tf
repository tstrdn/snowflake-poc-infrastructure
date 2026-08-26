# One root configuration, local modules, no module registry (E2/E3). This
# workspace is VCS-driven (docs/decisions.md) and watches one branch only -
# dev watches `main`, tst watches env/tst, prd watches env/prd. What it runs
# is always whatever that branch's HEAD contains; promote.yml moves env/tst
# and env/prd to a release tag's tree, never anything this file pins.
#
# TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA is auto-injected by TFE on every
# real run and exists only to be stamped into Snowflake (module
# "environment"'s version_label) so the deployed commit is queryable
# directly from the platform (E6), without a machine commit back to this
# repository (E5).

module "environment" {
  source = "../../modules/snowflake-environment"

  env                           = "dev"
  credit_quota                  = 6
  data_retention_days           = 1
  resource_monitor_notify_users = var.resource_monitor_notify_users
  version_label                 = var.TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA
}

module "rbac" {
  source = "../../modules/snowflake-rbac"

  env = "dev"

  database_raw       = module.environment.database_raw
  database_analytics = module.environment.database_analytics
  database_ops       = module.environment.database_ops

  warehouse_transform = module.environment.warehouse_transform
  warehouse_reporting = module.environment.warehouse_reporting

  dbt_service_user_public_key = var.dbt_service_user_public_key
  allow_developer_schemas     = true
}
