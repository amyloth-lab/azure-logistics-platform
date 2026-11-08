resource "azurerm_service_plan" "this" {
  name                = "asp-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Grant storage access before the Function App is created so Flex Consumption
# can read its deployment package container during provisioning.
resource "azurerm_role_assignment" "storage" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = var.storage_container_endpoint
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.this.id

  runtime_name           = "python"
  runtime_version        = "3.12"
  maximum_instance_count = 20
  instance_memory_in_mb  = 2048

  virtual_network_subnet_id     = var.functions_subnet_id
  public_network_access_enabled = false
  https_only                    = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    vnet_route_all_enabled = true
  }

  app_settings = {
    "ServiceBusConnection__fullyQualifiedNamespace" = var.servicebus_namespace_fqdn
    "ServiceBusConnection__credential"              = "managedidentity"
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.storage]
}

resource "azurerm_role_assignment" "servicebus_receiver" {
  scope                = var.servicebus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

output "id" {
  value = azurerm_function_app_flex_consumption.this.id
}

output "default_hostname" {
  value = azurerm_function_app_flex_consumption.this.default_hostname
}

output "principal_id" {
  value = azurerm_user_assigned_identity.this.principal_id
}
