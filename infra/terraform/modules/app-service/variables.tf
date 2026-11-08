variable "name" {
  description = "Globally unique App Service name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the App Service."
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

variable "sku_name" {
  description = "App Service plan SKU. B1 for the lab; P1v3+ for production slots."
  type        = string
  default     = "B1"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "Use a supported App Service plan SKU."
  }
}

variable "outbound_subnet_id" {
  description = "App Service VNet integration subnet."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Workload private endpoint subnet."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of privatelink.azurewebsites.net."
  type        = string
}

variable "tags" {
  description = "Tags applied to App Service resources."
  type        = map(string)
}
