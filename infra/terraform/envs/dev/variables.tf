variable "prefix" {
  description = "Short lowercase prefix used in resource names."
  type        = string
  default     = "logistics"
}

variable "environment" {
  description = "Environment short name."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "australiaeast"
}

variable "firewall_sku_tier" {
  description = "Basic for the lab; Premium for production."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "Use Basic, Standard, or Premium."
  }
}

variable "firewall_threat_intelligence_mode" {
  description = "Basic supports Alert only. Premium can Deny."
  type        = string
  default     = "Alert"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_threat_intelligence_mode)
    error_message = "Use Off, Alert, or Deny."
  }
}

variable "enable_app_service" {
  description = "Set true only after App Service VM quota is available. The current subscription is ineligible for a quota increase."
  type        = bool
  default     = false
}

variable "app_service_sku" {
  description = "App Service plan SKU. B1 for the lab; P1v3+ for production slots."
  type        = string
  default     = "B1"
}

variable "apim_publisher_name" {
  description = "APIM publisher name."
  type        = string
  default     = "Logistics Platform"
}

variable "apim_publisher_email" {
  description = "APIM publisher email. Must be a valid email format."
  type        = string
  default     = "whrsoft@gmail.com"
}

variable "sql_admin_login" {
  description = "Login name recorded for the Entra SQL administrator. Use your UPN if Azure rejects the default."
  type        = string
  default     = "logistics-sql-admin"
}

variable "log_retention_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily cap in GB."
  type        = number
  default     = 1
}

variable "budget_amount_usd" {
  description = "Monthly subscription budget in USD. Set 0 to disable."
  type        = number
  default     = 150
}

variable "budget_contact_emails" {
  description = "Emails for budget alerts. Empty disables the budget."
  type        = list(string)
  default     = []
}

variable "budget_start_date" {
  description = "Budget start date in RFC3339. Must be the first day of a month."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default = {
    workload           = "logistics"
    environment        = "dev"
    owner              = "platform-team"
    costCenter         = "logistics-platform"
    dataClassification = "internal"
    managedBy          = "terraform"
  }
}
