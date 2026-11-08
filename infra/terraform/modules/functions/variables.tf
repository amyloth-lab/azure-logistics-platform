variable "name" {
  description = "Function App name (max 32 characters)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
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

variable "storage_account_id" {
  description = "Storage account ID for deployment packages."
  type        = string
}

variable "storage_container_endpoint" {
  description = "Full blob container endpoint for deployment packages."
  type        = string
}

variable "functions_subnet_id" {
  description = "Functions VNet integration subnet."
  type        = string
}

variable "servicebus_namespace_id" {
  description = "Service Bus namespace ID for the receiver role."
  type        = string
}

variable "servicebus_namespace_fqdn" {
  description = "Service Bus namespace FQDN."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
