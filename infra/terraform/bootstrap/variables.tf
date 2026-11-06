variable "prefix" {
  description = "Short lowercase prefix used in resource names."
  type        = string
  default     = "logistics"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,12}$", var.prefix))
    error_message = "Use 3-13 lowercase letters/digits, starting with a letter."
  }
}

variable "environment" {
  description = "Environment short name."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.environment))
    error_message = "Use 2-6 lowercase letters."
  }
}

variable "location" {
  description = "Azure region for the state storage account."
  type        = string
  default     = "australiaeast"
}

variable "deployer_ip" {
  description = "Public IP/CIDR of the machine running Terraform, for example 203.0.113.10/32. This is a temporary bootstrap allowance."
  type        = string

  validation {
    condition     = can(cidrhost(var.deployer_ip, 0))
    error_message = "Use a valid CIDR such as 203.0.113.10/32."
  }
}

variable "tags" {
  description = "Tags applied to bootstrap resources."
  type        = map(string)
  default = {
    workload           = "logistics"
    environment        = "dev"
    owner              = "platform-team"
    costCenter         = "logistics-platform"
    dataClassification = "internal"
    managedBy          = "terraform"
  }
}
