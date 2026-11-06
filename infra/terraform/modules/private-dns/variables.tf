variable "resource_group_name" {
  description = "Resource group for the private DNS zones."
  type        = string
}

variable "hub_vnet_id" {
  description = "Hub VNet to link the zones to."
  type        = string
}

variable "zones" {
  description = "Private DNS zones required by the platform."
  type        = list(string)
  default = [
    "privatelink.azure-api.net",
    "privatelink.azurewebsites.net",
    "privatelink.database.windows.net",
    "privatelink.redis.azure.net",
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.servicebus.windows.net",
    "privatelink.azurecr.io",
    "privatelink.australiaeast.azmk8s.io"
  ]
}

variable "tags" {
  description = "Tags applied to DNS resources."
  type        = map(string)
}
