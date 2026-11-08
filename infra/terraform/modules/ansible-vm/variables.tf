variable "name" {
  description = "Ansible control VM name."
  type        = string
}

variable "resource_group_name" {
  description = "Management resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Management VNet Ansible subnet."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the azureuser account."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
