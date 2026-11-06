variable "resource_group_name" {
  description = "Resource group for Bastion."
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

variable "bastion_subnet_id" {
  description = "ID of AzureBastionSubnet."
  type        = string
}

variable "tags" {
  description = "Tags applied to Bastion resources."
  type        = map(string)
}
