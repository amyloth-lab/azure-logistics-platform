variable "name" {
  description = "Globally unique ACR name (lowercase alphanumeric)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the registry."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Management VNet private endpoint subnet."
  type        = string
}

variable "public_network_access_enabled" {
  description = "Allow the public ACR endpoint. Lab-only exception for Microsoft-hosted build agents."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "ID of privatelink.azurecr.io."
  type        = string
}

variable "tags" {
  description = "Tags applied to ACR resources."
  type        = map(string)
}
