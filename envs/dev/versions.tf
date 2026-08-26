terraform {
  required_version = ">= 1.9.0"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.19"
    }
  }

  # State, locking and execution live in Terraform Enterprise. This workspace
  # is VCS-driven (docs/decisions.md), connected to this repository directly
  # in the TFE UI - that connection is what resolves organization and
  # workspace for every real run, not anything in this block or a CI
  # environment variable. No workflow sets one anymore.
  #
  # The block still matters for one thing: `terraform login` and a local
  # `terraform plan` against this workspace's real state, if you want that
  # for manual troubleshooting. policy-check.yml's plan does not use this
  # backend at all - it strips this whole block first (docs/decisions.md).
  cloud {
    workspaces {
      name = "snowflake-poc-dev"
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
