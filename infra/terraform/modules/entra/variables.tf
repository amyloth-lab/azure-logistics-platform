variable "display_name" {
  description = "API app registration display name."
  type        = string
  default     = "logistics-api"
}

variable "audience" {
  description = "Application ID URI / token audience."
  type        = string
  default     = "api://logistics-api"
}

variable "assign_roles_to_current_user" {
  description = "Assign the normal-user and manager roles to the Terraform caller."
  type        = bool
  default     = true
}

variable "role_assignment_object_id" {
  description = "Explicit user/group object ID to receive the human app roles. Overrides the Terraform caller."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional notes/tags."
  type        = map(string)
  default     = {}
}
