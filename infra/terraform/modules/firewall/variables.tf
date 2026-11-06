variable "resource_group_name" {
  description = "Resource group for the firewall."
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

variable "firewall_subnet_id" {
  description = "ID of AzureFirewallSubnet."
  type        = string
}

variable "firewall_management_subnet_id" {
  description = "ID of AzureFirewallManagementSubnet. Required for Basic SKU; ignored for Standard/Premium."
  type        = string
}

variable "sku_tier" {
  description = "Azure Firewall SKU tier. Use Basic for the lab, Premium for production."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Basic, Standard, or Premium."
  }
}

variable "threat_intelligence_mode" {
  description = "Threat intelligence mode. Basic supports Alert only."
  type        = string
  default     = "Alert"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.threat_intelligence_mode)
    error_message = "Use Off, Alert, or Deny."
  }
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for firewall diagnostics. Required; diagnostics are always enabled."
  type        = string
}

variable "tags" {
  description = "Tags applied to firewall resources."
  type        = map(string)
}
