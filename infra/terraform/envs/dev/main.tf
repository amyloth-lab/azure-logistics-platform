data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.prefix}-platform-${var.environment}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-${var.prefix}-workload-${var.environment}"
  location = var.location
  tags     = var.tags
}

module "observability" {
  source = "../../modules/observability"

  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  environment         = var.environment
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = var.tags
}

module "network_hub" {
  source = "../../modules/network-hub"

  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  environment         = var.environment
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

module "firewall" {
  source = "../../modules/firewall"

  resource_group_name           = azurerm_resource_group.platform.name
  location                      = var.location
  environment                   = var.environment
  firewall_subnet_id            = module.network_hub.firewall_subnet_id
  firewall_management_subnet_id = module.network_hub.firewall_management_subnet_id
  sku_tier                      = var.firewall_sku_tier
  threat_intelligence_mode      = var.firewall_threat_intelligence_mode
  log_analytics_workspace_id    = module.observability.workspace_id
  tags                          = var.tags
}

module "bastion" {
  source = "../../modules/bastion"

  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  environment         = var.environment
  bastion_subnet_id   = module.network_hub.bastion_subnet_id
  tags                = var.tags
}

module "private_dns" {
  source = "../../modules/private-dns"

  resource_group_name = azurerm_resource_group.platform.name
  hub_vnet_id         = module.network_hub.vnet_id
  tags                = var.tags
}

module "policy" {
  source = "../../modules/policy"

  allowed_public_ip_resource_groups = [
    azurerm_resource_group.platform.name,
    "rg-${var.prefix}-edge-${var.environment}"
  ]

  tags = var.tags
}

resource "azurerm_consumption_budget_subscription" "this" {
  count = var.budget_amount_usd > 0 && length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = "budget-${var.prefix}-${var.environment}"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.budget_amount_usd
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
    end_date   = "2027-11-01T00:00:00Z"
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = notification.value
      threshold_type = "Actual"
      contact_emails = var.budget_contact_emails
    }
  }
}
