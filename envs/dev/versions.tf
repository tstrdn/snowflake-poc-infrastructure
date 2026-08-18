terraform {
  required_version = ">= 1.9.0"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.19"
    }
  }

  # State, locking and remote execution live in HCP Terraform. The organization
  # comes from the TF_CLOUD_ORGANIZATION environment variable so this file holds
  # no account-specific identifiers.
  cloud {
    workspaces {
      name = "snowflake-poc-dev"
    }
  }
}

# Every connection setting is supplied through environment variables, which in
# remote execution mode are HCP workspace variables:
#
#   SNOWFLAKE_ORGANIZATION_NAME  organization the account belongs to
#   SNOWFLAKE_ACCOUNT_NAME       account name within the organization
#   SNOWFLAKE_USER               SVC_TERRAFORM
#   SNOWFLAKE_PRIVATE_KEY        PEM private key (sensitive)
#   SNOWFLAKE_AUTHENTICATOR      SNOWFLAKE_JWT
#   SNOWFLAKE_ROLE               ACCOUNTADMIN
#
# Nothing here is environment-specific, which is the point: the same code
# targets a different account purely by which workspace it runs in.
provider "snowflake" {}
