variable "version_label" {
  description = "Deployed commit, from TFC_CONFIGURATION_VERSION_GIT_COMMIT_SHA. Lands in the table and is what lets the guinea pig fail; empty outside a real TFE run."
  type        = string
  default     = ""
}
