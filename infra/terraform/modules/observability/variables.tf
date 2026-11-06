variable "resource_group_name" {
  description = "Resource group for the workspace."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "environment" {
  description = "Environment short name."
  type        = string
}

variable "retention_in_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB. Use 1 for the lab."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags applied to observability resources."
  type        = map(string)
}
