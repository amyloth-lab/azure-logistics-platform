variable "resource_group_name" {
  description = "Resource group for the hub network."
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

variable "address_space" {
  description = "Hub VNet address space."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "tags" {
  description = "Tags applied to hub resources."
  type        = map(string)
}
