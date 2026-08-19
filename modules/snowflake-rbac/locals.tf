locals {
  # Access roles hold privileges on exactly one schema. Nothing is ever granted
  # directly to a user - users receive functional roles, functional roles are
  # composed of access roles, and access roles hold the grants. Adding a schema
  # means adding an entry here, not editing grant blocks.
  access_roles = {
    RAW_RW = {
      database = var.database_raw
      schema   = var.schema_raw
      write    = true
    }
    RAW_RO = {
      database = var.database_raw
      schema   = var.schema_raw
      write    = false
    }
    ANALYTICS_STG_RW = {
      database = var.database_analytics
      schema   = var.schema_staging
      write    = true
    }
    ANALYTICS_STG_RO = {
      database = var.database_analytics
      schema   = var.schema_staging
      write    = false
    }
    ANALYTICS_MARTS_RW = {
      database = var.database_analytics
      schema   = var.schema_marts
      write    = true
    }
    ANALYTICS_MARTS_RO = {
      database = var.database_analytics
      schema   = var.schema_marts
      write    = false
    }
  }

  # Functional roles are what humans and services are actually granted.
  functional_roles = {
    LOADER = {
      comment      = "Loads source data into RAW"
      access_roles = ["RAW_RW"]
      warehouse    = var.warehouse_transform
    }
    TRANSFORMER = {
      comment      = "Builds dbt models: reads RAW, owns ANALYTICS"
      access_roles = ["RAW_RO", "ANALYTICS_STG_RW", "ANALYTICS_MARTS_RW"]
      warehouse    = var.warehouse_transform
    }
    ANALYST = {
      comment      = "Reads dbt output"
      access_roles = ["ANALYTICS_STG_RO", "ANALYTICS_MARTS_RO"]
      warehouse    = var.warehouse_reporting
    }
  }

  schema_privileges_ro = ["USAGE"]

  # CREATE MATERIALIZED VIEW is deliberately absent: materialized views are an
  # Enterprise Edition feature, and Snowflake rejects the whole GRANT statement
  # on a Standard account. dbt does not use them here.
  schema_privileges_rw = [
    "USAGE",
    "MONITOR",
    "CREATE TABLE",
    "CREATE VIEW",
    "CREATE DYNAMIC TABLE",
    "CREATE STAGE",
    "CREATE FILE FORMAT",
    "CREATE SEQUENCE",
    "CREATE FUNCTION",
    "CREATE PROCEDURE",
  ]

  table_privileges_ro = ["SELECT"]
  table_privileges_rw = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES"]

  # One grant resource per (role, object type, current-or-future) combination.
  # Flattened here so the resources below stay a single for_each each.
  object_grants = merge([
    for role_name, cfg in local.access_roles : {
      for key, spec in {
        "tables_all" = {
          plural     = "TABLES"
          future     = false
          privileges = cfg.write ? local.table_privileges_rw : local.table_privileges_ro
        }
        "tables_future" = {
          plural     = "TABLES"
          future     = true
          privileges = cfg.write ? local.table_privileges_rw : local.table_privileges_ro
        }
        "views_all" = {
          plural     = "VIEWS"
          future     = false
          privileges = local.table_privileges_ro
        }
        "views_future" = {
          plural     = "VIEWS"
          future     = true
          privileges = local.table_privileges_ro
        }
        } : "${role_name}__${key}" => {
        role       = role_name
        schema_fqn = "\"${cfg.database}\".\"${cfg.schema}\""
        plural     = spec.plural
        future     = spec.future
        privileges = spec.privileges
      }
    }
  ]...)

  # Flatten functional role -> access role edges for a single for_each.
  functional_to_access = merge([
    for fn_name, cfg in local.functional_roles : {
      for access_name in cfg.access_roles :
      "${fn_name}__${access_name}" => {
        parent = fn_name
        child  = access_name
      }
    }
  ]...)
}
