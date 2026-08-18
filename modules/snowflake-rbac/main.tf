# Roles ------------------------------------------------------------------------

resource "snowflake_account_role" "access" {
  for_each = local.access_roles

  name    = each.key
  comment = "Access role: ${each.value.write ? "read/write" : "read-only"} on ${each.value.database}.${each.value.schema} - ${upper(var.env)}"
}

resource "snowflake_account_role" "functional" {
  for_each = local.functional_roles

  name    = each.key
  comment = "${each.value.comment} - ${upper(var.env)}"
}

# Role hierarchy: access roles are granted to functional roles.
resource "snowflake_grant_account_role" "functional_to_access" {
  for_each = local.functional_to_access

  role_name        = snowflake_account_role.access[each.value.child].name
  parent_role_name = snowflake_account_role.functional[each.value.parent].name
}

# Functional roles roll up to SYSADMIN so account administrators retain a path
# to everything the platform creates without being granted objects directly.
resource "snowflake_grant_account_role" "functional_to_sysadmin" {
  for_each = local.functional_roles

  role_name        = snowflake_account_role.functional[each.key].name
  parent_role_name = "SYSADMIN"
}

# Database and schema privileges ------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  for_each = local.access_roles

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = each.value.database
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema" {
  for_each = local.access_roles

  account_role_name = snowflake_account_role.access[each.key].name
  privileges        = each.value.write ? local.schema_privileges_rw : local.schema_privileges_ro

  on_schema {
    schema_name = "\"${each.value.database}\".\"${each.value.schema}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "objects" {
  for_each = local.object_grants

  account_role_name = snowflake_account_role.access[each.value.role].name
  privileges        = each.value.privileges

  on_schema_object {
    dynamic "all" {
      for_each = each.value.future ? [] : [1]
      content {
        object_type_plural = each.value.plural
        in_schema          = each.value.schema_fqn
      }
    }

    dynamic "future" {
      for_each = each.value.future ? [1] : []
      content {
        object_type_plural = each.value.plural
        in_schema          = each.value.schema_fqn
      }
    }
  }
}

# Warehouse privileges ----------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  for_each = local.functional_roles

  account_role_name = snowflake_account_role.functional[each.key].name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = each.value.warehouse
  }
}

# dbt project objects -----------------------------------------------------------
#
# TRANSFORMER must be able to create and execute DBT PROJECT objects, because
# the dbt pipeline authenticates as SVC_DBT and `snow dbt deploy` creates the
# object. Terraform grants the capability; the pipeline creates the object.

resource "snowflake_grant_privileges_to_account_role" "ops_database_usage" {
  account_role_name = snowflake_account_role.functional["TRANSFORMER"].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_ops
  }
}

resource "snowflake_grant_privileges_to_account_role" "dbt_projects_schema" {
  account_role_name = snowflake_account_role.functional["TRANSFORMER"].name
  privileges        = ["USAGE", "MONITOR", "CREATE DBT PROJECT"]

  on_schema {
    schema_name = "\"${var.database_ops}\".\"${var.schema_dbt_projects}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "dbt_projects_future" {
  account_role_name = snowflake_account_role.functional["TRANSFORMER"].name
  privileges        = ["USAGE", "MONITOR", "MODIFY"]

  on_schema_object {
    future {
      object_type_plural = "DBT PROJECTS"
      in_schema          = "\"${var.database_ops}\".\"${var.schema_dbt_projects}\""
    }
  }
}

# Developer and CI schemas ------------------------------------------------------
#
# Development only. Lets engineers build into ANALYTICS.DBT_<USER> and lets PR
# validation create and drop ANALYTICS.PR_<n> without a Terraform round trip.

resource "snowflake_grant_privileges_to_account_role" "developer_schema_creation" {
  count = var.allow_developer_schemas ? 1 : 0

  account_role_name = snowflake_account_role.functional["TRANSFORMER"].name
  privileges        = ["USAGE", "MONITOR", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_analytics
  }
}

# Service user ------------------------------------------------------------------
#
# SVC_TERRAFORM is created by bootstrap/bootstrap.sql and deliberately stays out
# of state - it is the credential Terraform itself authenticates with. Every
# other service identity is code, and this is the one.

resource "snowflake_service_user" "dbt" {
  name         = "SVC_DBT"
  comment      = "dbt deployment and execution pipeline - ${upper(var.env)}. Managed by Terraform; do not edit in Snowsight."
  login_name   = "SVC_DBT"
  display_name = "SVC_DBT (${upper(var.env)})"

  rsa_public_key = var.dbt_service_user_public_key

  default_role                   = snowflake_account_role.functional["TRANSFORMER"].name
  default_warehouse              = var.warehouse_transform
  default_namespace              = var.database_analytics
  default_secondary_roles_option = "ALL"

  # dbt emits its own timeouts; this is a backstop against a hung deployment
  # holding the warehouse open.
  statement_timeout_in_seconds = 3600
}

resource "snowflake_grant_account_role" "dbt_transformer" {
  role_name = snowflake_account_role.functional["TRANSFORMER"].name
  user_name = snowflake_service_user.dbt.name
}
