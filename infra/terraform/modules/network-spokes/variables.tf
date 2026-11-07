variable "hub_resource_group_name" {
  description = "Resource group that contains the hub VNet."
  type        = string
}

variable "hub_vnet_name" {
  description = "Hub VNet name."
  type        = string
}

variable "hub_vnet_id" {
  description = "Hub VNet ID."
  type        = string
}

variable "firewall_private_ip" {
  description = "Azure Firewall private IP used as the default next hop."
  type        = string
}

variable "bastion_subnet_cidr" {
  description = "Hub AzureBastionSubnet CIDR allowed to SSH to management VMs."
  type        = string
  default     = "10.0.1.0/26"
}

variable "environment" {
  description = "Environment short name."
  type        = string
}

variable "tags" {
  description = "Tags applied to spoke resources."
  type        = map(string)
}
