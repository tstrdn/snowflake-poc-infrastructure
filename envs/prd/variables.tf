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

variable "TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA" {
  description = <<-EOT
    Auto-injected by TFE on every VCS-driven run, if a variable with this
    exact name is declared - the full commit SHA of the configuration version
    being planned/applied (see docs/decisions.md). Not used for any
    conditional logic - it only flows through to module
    "environment".version_label, which stamps it onto a Snowflake object
    comment so the deployed commit is queryable directly from the platform
    (E6) instead of needing a machine commit back to this repository.

    Empty outside a real TFE run - policy-check.yml's throwaway local plan
    has no TFE run to inject it from, and passes its own value (a version
    tag, not a commit SHA) purely for a readable plan; that plan is never
    applied, so the mismatch in what the string represents does not matter.
  EOT
  type        = string
  default     = ""
}
