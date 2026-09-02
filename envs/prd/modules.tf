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

  env          = "prd"
  credit_quota = 10
  # Standard Edition (what this trial account runs) caps Time Travel
  # retention at 1 day, full stop - Enterprise Edition or higher is required
  # for anything longer. 7 was the target-state value and failed apply here
  # with "Exceeds maximum allowable retention time (1 day(s))"; see
  # docs/limitations-and-costs.md. Revisit if this account is ever upgraded.
  data_retention_days           = 1
  resource_monitor_notify_users = var.resource_monitor_notify_users
  version_label                 = var.TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA
}

module "rbac" {
  source = "../../modules/snowflake-rbac"

  env = "prd"

  database_raw       = module.environment.database_raw
  database_analytics = module.environment.database_analytics
  database_ops       = module.environment.database_ops

  warehouse_transform = module.environment.warehouse_transform
  warehouse_reporting = module.environment.warehouse_reporting

  dbt_service_user_public_key = var.dbt_service_user_public_key
  allow_developer_schemas     = false
}

# docs/guinea-pig.md. Temporary - delete this block and the guinea_pig_*
# outputs to remove it.
module "guinea_pig" {
  source = "../../modules/snowflake-guinea-pig"

  # The alias is the one carrying a session warehouse (versions.tf).
  providers = {
    snowflake = snowflake.guinea_pig
  }

  version_label = var.TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA
}
