variable "resource_group_name" {
  description = "Resource group for the data services."
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

variable "data_private_endpoints_subnet_id" {
  description = "Data VNet private endpoint subnet."
  type        = string
}

variable "private_dns_zone_ids" {
  description = "Map of private DNS zone name to ID."
  type        = map(string)
}

variable "sql_server_name" {
  description = "Globally unique SQL server name."
  type        = string
}

variable "sql_admin_object_id" {
  description = "Entra object ID of the SQL administrator."
  type        = string
}

variable "sql_admin_login" {
  description = "Login name recorded for the Entra SQL administrator."
  type        = string
  default     = "logistics-sql-admin"
}

variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique storage account name."
  type        = string
}

variable "servicebus_namespace_name" {
  description = "Globally unique Service Bus namespace name."
  type        = string
}

variable "redis_name" {
  description = "Globally unique Managed Redis name."
  type        = string
}

variable "tags" {
  description = "Tags applied to data resources."
  type        = map(string)
}
