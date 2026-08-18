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

variable "credit_quota" {
  description = "Monthly credit quota for the environment's resource monitor."
  type        = number
  default     = 10
}

variable "resource_monitor_notify_users" {
  description = "Snowflake user identifiers that receive resource monitor notifications. Empty is valid; notifications are simply not sent."
  type        = list(string)
  default     = []
}

variable "data_retention_days" {
  description = "Time Travel retention for databases. Higher in production."
  type        = number
  default     = 1
}
