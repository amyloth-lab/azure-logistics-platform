data "azurerm_client_config" "current" {}
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

resource "azurerm_resource_group" "data" {
  name     = "rg-${var.prefix}-data-${var.environment}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "management" {
  name     = "rg-${var.prefix}-management-${var.environment}"
  location = var.location
  tags     = var.tags
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
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

module "data" {
  source = "../../modules/data"

  resource_group_name              = azurerm_resource_group.data.name
  location                         = var.location
  environment                      = var.environment
  data_private_endpoints_subnet_id = module.network_spokes.data_private_endpoints_subnet_id
  private_dns_zone_ids             = module.private_dns.zone_ids
  sql_server_name                  = "sql-logistics-${var.environment}-${random_string.suffix.result}"
  sql_admin_object_id              = data.azurerm_client_config.current.object_id
  sql_admin_login                  = var.sql_admin_login
  tenant_id                        = data.azurerm_client_config.current.tenant_id
  storage_account_name             = "stlogistics${var.environment}${random_string.suffix.result}"
  servicebus_namespace_name        = "sb-logistics-${var.environment}-${random_string.suffix.result}"
  redis_name                       = "redis-logistics-${var.environment}-${random_string.suffix.result}"
  tags                             = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "aks_egress" {
  name               = "aks-egress"
  firewall_policy_id = module.firewall.firewall_policy_id
  priority           = 200

  application_rule_collection {
    name     = "aks-required"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "aks-service-tag"
      source_addresses      = ["10.2.0.0/16", "10.4.0.0/16"]
      destination_fqdn_tags = ["AzureKubernetesService"]

      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name                  = "mcr-tag"
      source_addresses      = ["10.2.0.0/16", "10.4.0.0/16"]
      destination_fqdn_tags = ["MicrosoftContainerRegistry"]

      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name                  = "aad-tag"
      source_addresses      = ["10.2.0.0/16", "10.4.0.0/16"]
      destination_fqdn_tags = ["AzureActiveDirectory"]

      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "aks-extra-fqdns"
      source_addresses = ["10.2.0.0/16", "10.4.0.0/16"]

      protocols {
        type = "Https"
        port = 443
      }

      destination_fqdns = [
        "management.azure.com",
        "login.microsoftonline.com",
        "packages.microsoft.com",
        "acs-mirror.azureedge.net",
        "azure.archive.ubuntu.com",
        "security.ubuntu.com"
      ]
    }
  }

  network_rule_collection {
    name     = "aks-ntp"
    priority = 300
    action   = "Allow"

    rule {
      name                  = "acr-private-endpoint"
      source_addresses      = ["10.2.0.0/16"]
      destination_addresses = ["10.4.2.0/24"]
      destination_ports     = ["443"]
      protocols             = ["TCP"]
    }

    rule {
      name                  = "sql-private-endpoint"
      source_addresses      = ["10.2.0.0/16"]
      destination_addresses = ["10.3.1.0/24"]
      destination_ports     = ["1433"]
      protocols             = ["TCP"]
    }

    rule {
      name                  = "ntp"
      source_addresses      = ["10.2.0.0/16", "10.4.0.0/16"]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
      protocols             = ["UDP"]
    }
  }
}

module "network_spokes" {
  source = "../../modules/network-spokes"

  hub_resource_group_name = azurerm_resource_group.platform.name
  hub_vnet_name           = module.network_hub.vnet_name
  hub_vnet_id             = module.network_hub.vnet_id
  firewall_private_ip     = module.firewall.firewall_private_ip
  bastion_subnet_cidr     = "10.0.1.0/26"
  environment             = var.environment
  tags                    = var.tags
}

module "acr" {
  source = "../../modules/acr"

  name                          = "acr${var.prefix}${var.environment}${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.management.name
  location                      = var.location
  private_endpoint_subnet_id    = module.network_spokes.management_private_endpoints_subnet_id
  private_dns_zone_id           = module.private_dns.zone_ids["privatelink.azurecr.io"]
  public_network_access_enabled = var.acr_public_network_access_enabled
  tags                          = var.tags
}

module "aks" {
  source = "../../modules/aks"

  name                       = "aks-logistics-${var.environment}"
  resource_group_name        = azurerm_resource_group.workload.name
  location                   = var.location
  environment                = var.environment
  dns_prefix                 = "aks-logistics-${var.environment}"
  system_subnet_id           = module.network_spokes.aks_system_subnet_id
  user_subnet_id             = module.network_spokes.aks_user_subnet_id
  workload_vnet_id           = module.network_spokes.workload_vnet_id
  acr_id                     = module.acr.id
  log_analytics_workspace_id = module.observability.workspace_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  private_dns_zone_id        = module.private_dns.zone_ids["privatelink.australiaeast.azmk8s.io"]
  tags                       = var.tags
}

# Lab convenience: the human running Terraform needs Kubernetes RBAC to use
# az aks command invoke / kubectl. In production, assign this to a group and
# use a manual JIT process; do not grant it to every engineer permanently.
resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "apim" {
  source = "../../modules/apim"

  name                       = "apim-logistics-${var.environment}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.platform.name
  location                   = var.location
  environment                = var.environment
  publisher_name             = var.apim_publisher_name
  publisher_email            = var.apim_publisher_email
  private_endpoint_subnet_id = module.network_spokes.workload_private_endpoints_subnet_id
  outbound_subnet_id         = module.network_spokes.apim_outbound_subnet_id
  private_dns_zone_id        = module.private_dns.zone_ids["privatelink.azure-api.net"]
  tags                       = var.tags
}

module "app_service" {
  count  = var.enable_app_service ? 1 : 0
  source = "../../modules/app-service"

  name                       = "app-logistics-${var.environment}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.workload.name
  location                   = var.location
  environment                = var.environment
  sku_name                   = var.app_service_sku
  outbound_subnet_id         = module.network_spokes.appservice_outbound_subnet_id
  private_endpoint_subnet_id = module.network_spokes.workload_private_endpoints_subnet_id
  private_dns_zone_id        = module.private_dns.zone_ids["privatelink.azurewebsites.net"]
  tags                       = var.tags
}

module "api_identity" {
  source = "../../modules/api-identity"

  name                    = "id-api-logistics-${var.environment}-${random_string.suffix.result}"
  resource_group_name     = azurerm_resource_group.workload.name
  location                = var.location
  aks_oidc_issuer_url     = module.aks.oidc_issuer_url
  namespace               = "logistics"
  service_account         = "logistics-api"
  storage_account_id      = module.data.storage_account_id
  servicebus_namespace_id = module.data.servicebus_namespace_id
  tags                    = var.tags
}

module "functions" {
  source = "../../modules/functions"

  name                       = "func-logistics-${var.environment}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.workload.name
  location                   = var.location
  environment                = var.environment
  storage_account_id         = module.data.storage_account_id
  storage_container_endpoint = module.data.function_packages_endpoint
  functions_subnet_id        = module.network_spokes.functions_outbound_subnet_id
  servicebus_namespace_id    = module.data.servicebus_namespace_id
  servicebus_namespace_fqdn  = module.data.servicebus_namespace_fqdn
  tags                       = var.tags
}

module "app_gateway" {
  count  = var.enable_app_gateway ? 1 : 0
  source = "../../modules/app-gateway"

  name                     = "agw-logistics-${var.environment}-${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.platform.name
  location                 = var.location
  environment              = var.environment
  subnet_id                = module.network_spokes.appgw_subnet_id
  apim_fqdn                = module.apim.gateway_hostname
  hostname                 = var.app_gateway_hostname
  ssl_certificate_path     = var.app_gateway_cert_path
  ssl_certificate_password = var.app_gateway_cert_password
  waf_mode                 = var.waf_mode
  tags                     = var.tags
}

module "ansible" {
  count  = var.enable_ansible_vm ? 1 : 0
  source = "../../modules/ansible-vm"

  name                = "vm-ansible-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.management.name
  location            = var.location
  subnet_id           = module.network_spokes.ansible_subnet_id
  ssh_public_key      = file("../../../../ansible/ansible_key.pub")
  tags                = var.tags
}

module "entra" {
  source = "../../modules/entra"

  display_name                 = "logistics-api"
  audience                     = "api://logistics-api"
  assign_roles_to_current_user = true
  role_assignment_object_id    = var.entra_role_assignment_object_id
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                       = "kv-${var.prefix}-${var.environment}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.data.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  private_endpoint_subnet_id = module.network_spokes.data_private_endpoints_subnet_id
  private_dns_zone_id        = module.private_dns.zone_ids["privatelink.vaultcore.azure.net"]
  tags                       = var.tags
}

locals {
  spoke_vnets = {
    ingress    = module.network_spokes.ingress_vnet_id
    workload   = module.network_spokes.workload_vnet_id
    data       = module.network_spokes.data_vnet_id
    management = module.network_spokes.management_vnet_id
  }

  dns_links = merge([
    for zone_name, _ in module.private_dns.zone_ids : {
      for vnet_name, vnet_id in local.spoke_vnets :
      "${zone_name}-${vnet_name}" => {
        zone_name = zone_name
        vnet_name = vnet_name
        vnet_id   = vnet_id
      }
    }
  ]...)
}

resource "azurerm_private_dns_zone_virtual_network_link" "spokes" {
  for_each = local.dns_links

  name                  = "link-${each.value.vnet_name}-${substr(sha1(each.key), 0, 6)}"
  resource_group_name   = azurerm_resource_group.platform.name
  private_dns_zone_name = each.value.zone_name
  virtual_network_id    = each.value.vnet_id
  registration_enabled  = false
  tags                  = var.tags
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
