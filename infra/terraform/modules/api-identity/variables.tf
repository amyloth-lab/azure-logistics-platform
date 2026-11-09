variable "name" {
  description = "User-assigned identity name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer URL."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace."
  type        = string
  default     = "logistics"
}

variable "service_account" {
  description = "Kubernetes service account."
  type        = string
  default     = "logistics-api"
}

variable "storage_account_id" {
  description = "Storage account for blob access."
  type        = string
}

variable "servicebus_namespace_id" {
  description = "Service Bus namespace for sender/receiver roles."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
