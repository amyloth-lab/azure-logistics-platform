variable "name" {
  description = "AKS cluster name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster."
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

variable "dns_prefix" {
  description = "AKS DNS prefix."
  type        = string
}

variable "kubernetes_version" {
  description = "Optional Kubernetes version. Null uses the AKS default."
  type        = string
  default     = null
}

variable "system_subnet_id" {
  description = "Subnet for the system node pool."
  type        = string
}

variable "user_subnet_id" {
  description = "Subnet for the user node pool."
  type        = string
}

variable "workload_vnet_id" {
  description = "Workload VNet ID for the AKS identity network role."
  type        = string
}

variable "acr_id" {
  description = "ACR ID for AcrPull."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for the OMS agent."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Existing privatelink.<region>.azmk8s.io zone ID."
  type        = string
}

variable "tags" {
  description = "Tags applied to AKS resources."
  type        = map(string)
}
