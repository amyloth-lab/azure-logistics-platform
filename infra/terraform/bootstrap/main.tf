data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  state_resource_group = "rg-${var.prefix}-tfstate"
  state_storage_name   = substr(lower("st${var.prefix}${var.environment}${random_string.suffix.result}"), 0, 24)
  state_container      = "tfstate"
}

resource "azurerm_resource_group" "tfstate" {
  name     = local.state_resource_group
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                = local.state_storage_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GRS"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  infrastructure_encryption_enabled = true
  is_hns_enabled                    = false

  # Bootstrap exception: the local Terraform backend needs a data-plane path
  # before the hub/private endpoint exists. Access is restricted to the
  # deployer's public IP and Entra ID; shared keys are disabled. Day 3 adds the
  # private endpoint and disables public network access.
  public_network_access_enabled = true

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    #ip_rules       = [var.deployer_ip]
    ip_rules = [trimsuffix(var.deployer_ip, "/32")]
  }

  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# The identity running Terraform needs data-plane access before the container
# can be created. Grant at the account scope so the assignment exists first.
resource "azurerm_role_assignment" "state_rw" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC propagation is eventually consistent. Give it a short window before the
# backend migration and first state write.
resource "time_sleep" "wait_for_rbac" {
  create_duration = "45s"

  depends_on = [azurerm_role_assignment.state_rw]
}

# azurerm_storage_container uses the storage data plane, which can still
# require shared-key auth even when storage_use_azuread is enabled. Create the
# container through the ARM control plane instead, so shared keys can stay off.
resource "azapi_resource" "tfstate" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = local.state_container
  parent_id = "${azurerm_storage_account.tfstate.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }

  depends_on = [time_sleep.wait_for_rbac]

  lifecycle {
    prevent_destroy = true
  }
}

output "resource_group_name" {
  value = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "container_name" {
  value = azapi_resource.tfstate.name
}

output "backend_config" {
  description = "Paste this into bootstrap/backend.hcl after the first apply, then run terraform init -migrate-state."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azapi_resource.tfstate.name}"
    key                  = "bootstrap/terraform.tfstate"
    use_azuread_auth     = true
  EOT
}
