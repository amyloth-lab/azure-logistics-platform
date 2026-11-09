resource "azurerm_api_management" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "StandardV2_1"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_api_management.this.id
    # APIM's Private Link group ID is case-sensitive: Gateway, not gateway.
    subresource_names    = ["Gateway"]
    is_manual_connection = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# The azurerm_api_management resource does not expose the Standard v2 outbound
# integration or public-network disable in the current provider. Apply those
# properties through the ARM API after the private endpoint exists.
resource "azapi_update_resource" "network" {
  type        = "Microsoft.ApiManagement/service@2024-05-01"
  resource_id = azurerm_api_management.this.id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
      # Standard v2 outbound integration is the "External" mode. "None" is
      # rejected when a subnet is supplied; "Internal" is not supported on v2.
      virtualNetworkType = "External"
      virtualNetworkConfiguration = {
        subnetResourceId = var.outbound_subnet_id
      }
    }
  }

  depends_on = [azurerm_private_endpoint.this]
}

resource "azurerm_api_management_api" "logistics" {
  name                  = "logistics-api"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Logistics API"
  path                  = "logistics"
  protocols             = ["https"]
  service_url           = var.backend_service_url
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "health" {
  api_name            = azurerm_api_management_api.logistics.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  operation_id        = "health"
  display_name        = "Health"
  method              = "GET"
  url_template        = "/health"
}

resource "azurerm_api_management_api_operation" "inventory" {
  api_name            = azurerm_api_management_api.logistics.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  operation_id        = "list-inventory"
  display_name        = "List inventory"
  method              = "GET"
  url_template        = "/api/v1/inventory"
}

resource "azurerm_api_management_api_operation" "orders" {
  api_name            = azurerm_api_management_api.logistics.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  operation_id        = "list-orders"
  display_name        = "List orders"
  method              = "GET"
  url_template        = "/api/v1/orders"
}

output "id" {
  value = azurerm_api_management.this.id
}

output "api_id" {
  value = azurerm_api_management_api.logistics.id
}

output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "gateway_hostname" {
  value = replace(azurerm_api_management.this.gateway_url, "https://", "")
}

output "private_ip" {
  value = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}
