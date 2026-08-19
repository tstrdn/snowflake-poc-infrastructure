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
      name = "snowflake-poc-prd"
    }
  }
}

# Connection settings come from HCP workspace variables. Most are environment
# variables:
#
#   SNOWFLAKE_ORGANIZATION_NAME  organization the account belongs to
#   SNOWFLAKE_ACCOUNT_NAME       account name within the organization
#   SNOWFLAKE_USER               SVC_TERRAFORM
#   SNOWFLAKE_AUTHENTICATOR      SNOWFLAKE_JWT
#   SNOWFLAKE_ROLE               ACCOUNTADMIN
#
# The private key cannot be one. HCP exports environment variables as shell
# variables and rejects newlines, so a PEM has to arrive as a Terraform
# variable and be wired in explicitly below.
#
# Nothing here is environment-specific, which is the point: the same code
# targets a different account purely by which workspace it runs in.
provider "snowflake" {
  private_key = var.snowflake_private_key
}
