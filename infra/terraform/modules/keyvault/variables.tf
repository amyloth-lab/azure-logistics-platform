variable "name" {
  description = "Globally unique Key Vault name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the vault."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Data VNet private endpoint subnet."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of privatelink.vaultcore.azure.net."
  type        = string
}

variable "tags" {
  description = "Tags applied to Key Vault resources."
  type        = map(string)
}
