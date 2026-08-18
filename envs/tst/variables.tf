variable "dbt_service_user_public_key" {
  description = <<-EOT
    RSA public key for SVC_DBT, one line, no PEM header or trailer.
    Set as a plain (non-sensitive) HCP workspace variable named
    TF_VAR_dbt_service_user_public_key - it is a public key.
  EOT
  type        = string
}

variable "resource_monitor_notify_users" {
  description = "Snowflake users to notify when the credit quota approaches its limit."
  type        = list(string)
  default     = []
}
