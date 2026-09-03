variable "env" {
  description = "Environment short name. Drives comments and tagging only - object names are identical across accounts, since each environment is a separate Snowflake account."
  type        = string

  validation {
    condition     = contains(["dev", "tst", "prd"], var.env)
    error_message = "env must be one of: dev, tst, prd."
  }
}

variable "transform_warehouse_size" {
  description = "Size of the warehouse dbt builds with."
  type        = string
  default     = "XSMALL"
}

variable "reporting_warehouse_size" {
  description = "Size of the warehouse downstream consumers query with."
  type        = string
  default     = "XSMALL"
}

variable "warehouse_auto_suspend_seconds" {
  description = "Idle seconds before a warehouse suspends. Kept low to protect trial credits."
  type        = number
  default     = 60
}

variable "statement_timeout_seconds" {
  description = "Hard ceiling on any single statement, so a runaway query cannot drain the credit quota."
  type        = number
  default     = 3600
}

variable "data_retention_days" {
  description = "Time Travel retention for databases. Higher in production."
  type        = number
  default     = 1
}

variable "version_label" {
  description = <<-EOT
    Identifier for what is deployed to this environment - normally a Git
    commit SHA (the root config wires this from
    TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA, auto-injected by TFE), sometimes
    a version tag when the caller is a throwaway local plan rather than a
    real TFE run. Stamped onto the OPS database comment (E6) so "what is this
    environment running?" can be answered by querying Snowflake directly,
    without trusting a pipeline log. Empty by default so the module remains
    usable without it (e.g. local terraform plan during development).
  EOT
  type        = string
  default     = ""
}
