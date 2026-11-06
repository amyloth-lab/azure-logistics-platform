resource "azurerm_public_ip" "firewall" {
  name                = "pip-fw-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Basic SKU always has a management NIC. Standard/Premium do not need one
# unless forced tunneling is enabled, so create this only for Basic.
resource "azurerm_public_ip" "firewall_management" {
  count = var.sku_tier == "Basic" ? 1 : 0

  name                = "pip-fw-mgmt-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_firewall_policy" "this" {
  name                     = "afwp-${var.environment}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = var.sku_tier
  threat_intelligence_mode = var.threat_intelligence_mode
  tags                     = var.tags
}

resource "azurerm_firewall" "this" {
  name                = "afw-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this.id
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  dynamic "management_ip_configuration" {
    for_each = var.sku_tier == "Basic" ? [1] : []
    content {
      name                 = "management"
      subnet_id            = var.firewall_management_subnet_id
      public_ip_address_id = azurerm_public_ip.firewall_management[0].id
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  # Diagnostics are mandatory in this module. Do not gate the resource with a
  # count that depends on an unknown workspace ID; Terraform cannot plan that.
  name                       = "diag-firewall-${var.environment}"
  target_resource_id         = azurerm_firewall.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  # Basic SKU does not support the threat-intelligence log category.
  dynamic "enabled_log" {
    for_each = var.sku_tier == "Basic" ? [] : ["AzureFirewallThreatIntelLog"]
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "firewall_id" {
  value = azurerm_firewall.this.id
}

output "firewall_private_ip" {
  value = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  value = azurerm_public_ip.firewall.ip_address
}

output "firewall_policy_id" {
  value = azurerm_firewall_policy.this.id
}
