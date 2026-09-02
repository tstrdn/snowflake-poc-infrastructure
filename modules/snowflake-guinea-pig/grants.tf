resource "snowflake_grant_privileges_to_account_role" "database" {
  account_role_name = snowflake_account_role.reader.name
  privileges        = ["USAGE"] # upper-case: the field is case-sensitive

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.guinea_pig.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema" {
  account_role_name = snowflake_account_role.reader.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = snowflake_schema.signal.fully_qualified_name
  }
}

# Without this the table is visible and the query still fails, with an error
# saying the object does not exist rather than that the role may not read it.
resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  account_role_name = snowflake_account_role.reader.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.guinea_pig.name
  }
}

# Future, not on the object: the table is recreated on every promotion, and a
# grant on the object would go with it each time.
resource "snowflake_grant_privileges_to_account_role" "future_tables" {
  account_role_name = snowflake_account_role.reader.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.signal.fully_qualified_name
    }
  }
}
