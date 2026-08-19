variable "snowflake_private_key" {
  description = <<-EOT
    PEM private key for SVC_TERRAFORM, including the BEGIN and END lines and
    the line breaks between them.

    Set as a sensitive *Terraform* variable in the HCP workspace, not an
    environment variable - HCP exports those as shell variables and rejects
    newlines, which a PEM necessarily contains.
  EOT
  type        = string
  sensitive   = true
}

variable "dbt_service_user_public_key" {
  description = <<-EOT
    RSA public key for SVC_DBT, one line, no PEM header or trailer.
    Set as a plain (non-sensitive) Terraform variable in the HCP workspace,
    named dbt_service_user_public_key - it is a public key, not a secret.
  EOT
  type        = string
}

variable "resource_monitor_notify_users" {
  description = "Snowflake users to notify when the credit quota approaches its limit."
  type        = list(string)
  default     = []
}
