variable "name" {
  description = "Application Gateway name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the gateway and public IP."
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

variable "subnet_id" {
  description = "Dedicated App Gateway subnet ID."
  type        = string
}

variable "apim_fqdn" {
  description = "APIM default gateway hostname."
  type        = string
}

variable "hostname" {
  description = "Public hostname on the listener and certificate CN/SAN."
  type        = string
}

variable "ssl_certificate_path" {
  description = "Path to a PFX certificate file."
  type        = string
  default     = "cert.pfx"
}

variable "ssl_certificate_password" {
  description = "PFX password."
  type        = string
  sensitive   = true
  default     = "changeit"
}

variable "waf_mode" {
  description = "Detection first; switch to Prevention after tuning."
  type        = string
  default     = "Detection"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
