resource "azurerm_mssql_server" "this" {
  name                          = var.sql_server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = var.tags

  azuread_administrator {
    login_username              = var.sql_admin_login
    object_id                   = var.sql_admin_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "this" {
  name                        = "sqldb-logistics"
  server_id                   = azurerm_mssql_server.this.id
  sku_name                    = "GP_S_Gen5_1"
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
  max_size_gb                 = 32
  zone_redundant              = false
  tags                        = var.tags
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${var.sql_server_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sql"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids["privatelink.database.windows.net"]]
  }
}

resource "azurerm_storage_account" "docs" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = false
  tags                            = var.tags

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azapi_resource" "containers" {
  for_each = toset(["documents", "audit"])

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.value
  parent_id = "${azurerm_storage_account.docs.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.storage_account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.docs.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids["privatelink.blob.core.windows.net"]]
  }
}

resource "azurerm_servicebus_namespace" "this" {
  name                = var.servicebus_namespace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  # Private endpoints are only supported on Premium Service Bus.
  sku                           = "Premium"
  capacity                      = 1
  premium_messaging_partitions  = 1
  local_auth_enabled            = false
  public_network_access_enabled = false
  minimum_tls_version           = "1.2"
  tags                          = var.tags
}

resource "azurerm_servicebus_topic" "orders" {
  name         = "orders"
  namespace_id = azurerm_servicebus_namespace.this.id
}

resource "azurerm_servicebus_topic" "inventory" {
  name         = "inventory"
  namespace_id = azurerm_servicebus_namespace.this.id
}

resource "azurerm_servicebus_topic" "shipments" {
  name         = "shipments"
  namespace_id = azurerm_servicebus_namespace.this.id
}

resource "azurerm_servicebus_subscription" "order_processor" {
  name               = "order-processor"
  topic_id           = azurerm_servicebus_topic.orders.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "order_audit" {
  name               = "order-audit"
  topic_id           = azurerm_servicebus_topic.orders.id
  max_delivery_count = 10
}

resource "azurerm_private_endpoint" "servicebus" {
  name                = "pe-${var.servicebus_namespace_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-servicebus"
    private_connection_resource_id = azurerm_servicebus_namespace.this.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids["privatelink.servicebus.windows.net"]]
  }
}

resource "azurerm_managed_redis" "this" {
  name                      = var.redis_name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  sku_name                  = "Balanced_B0"
  high_availability_enabled = false
  public_network_access     = "Disabled"
  tags                      = var.tags

  default_database {
    access_keys_authentication_enabled = false
    client_protocol                    = "Encrypted"
    clustering_policy                  = "NoCluster"
  }
}

resource "azurerm_private_endpoint" "redis" {
  name                = "pe-${var.redis_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-redis"
    private_connection_resource_id = azurerm_managed_redis.this.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids["privatelink.redis.azure.net"]]
  }
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "sql_database_name" {
  value = azurerm_mssql_database.this.name
}

output "storage_account_name" {
  value = azurerm_storage_account.docs.name
}

output "storage_account_id" {
  value = azurerm_storage_account.docs.id
}

output "servicebus_namespace_id" {
  value = azurerm_servicebus_namespace.this.id
}

output "servicebus_namespace_name" {
  value = azurerm_servicebus_namespace.this.name
}

output "redis_hostname" {
  value = azurerm_managed_redis.this.hostname
}
