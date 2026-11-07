variable "name" {
  description = "Globally unique APIM name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for APIM."
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

variable "publisher_name" {
  description = "APIM publisher name."
  type        = string
  default     = "Logistics Platform"
}

variable "publisher_email" {
  description = "APIM publisher email."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Workload VNet private endpoint subnet."
  type        = string
}

variable "outbound_subnet_id" {
  description = "APIM outbound VNet integration subnet."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of privatelink.azure-api.net."
  type        = string
}

variable "tags" {
  description = "Tags applied to APIM resources."
  type        = map(string)
}
