variable "allowed_public_ip_resource_groups" {
  description = "Resource groups allowed to contain public IP addresses (edge and hub)."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to policy resources."
  type        = map(string)
  default     = {}
}
