# Reference only. These values are set as HCP Terraform workspace variables,
# not committed - which is why envs/*/terraform.tfvars is git-ignored.
#
# In HCP, set them as Terraform variables (not environment variables):
#
#   dbt_service_user_public_key   the one-line public key from
#                                 bootstrap/generate_keypair.sh SVC_DBT <env>
#   resource_monitor_notify_users Snowflake users to email at 75% and 90% of quota

dbt_service_user_public_key   = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A..."
resource_monitor_notify_users = ["PLATFORM_ADMIN"]
