locals {
  ingress_name    = "vnet-ingress-${var.environment}"
  workload_name   = "vnet-workload-${var.environment}"
  data_name       = "vnet-data-${var.environment}"
  management_name = "vnet-management-${var.environment}"

  spoke_vnets = {
    ingress = {
      name                = azurerm_virtual_network.ingress.name
      resource_group_name = azurerm_virtual_network.ingress.resource_group_name
      id                  = azurerm_virtual_network.ingress.id
    }
    workload = {
      name                = azurerm_virtual_network.workload.name
      resource_group_name = azurerm_virtual_network.workload.resource_group_name
      id                  = azurerm_virtual_network.workload.id
    }
    data = {
      name                = azurerm_virtual_network.data.name
      resource_group_name = azurerm_virtual_network.data.resource_group_name
      id                  = azurerm_virtual_network.data.id
    }
    management = {
      name                = azurerm_virtual_network.management.name
      resource_group_name = azurerm_virtual_network.management.resource_group_name
      id                  = azurerm_virtual_network.management.id
    }
  }
}

resource "azurerm_virtual_network" "ingress" {
  name                = local.ingress_name
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  address_space       = ["10.1.0.0/16"]
  tags                = var.tags
}

# The location is derived from the resource group through this data source so
# the module does not need a separate location input.
data "azurerm_resource_group" "platform" {
  name = var.hub_resource_group_name
}

resource "azurerm_virtual_network" "workload" {
  name                = local.workload_name
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  address_space       = ["10.2.0.0/16"]
  tags                = var.tags
}

resource "azurerm_virtual_network" "data" {
  name                = local.data_name
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  address_space       = ["10.3.0.0/16"]
  tags                = var.tags
}

resource "azurerm_virtual_network" "management" {
  name                = local.management_name
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  address_space       = ["10.4.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.ingress.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_subnet" "aks_system" {
  name                 = "snet-aks-system"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.0.0/22"]
}

resource "azurerm_subnet" "aks_user" {
  name                 = "snet-aks-user"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.4.0/22"]
}

resource "azurerm_subnet" "apim_outbound" {
  name                 = "snet-apim-outbound"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.8.0/24"]

  delegation {
    name = "apim-outbound"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "appservice_outbound" {
  name                 = "snet-appservice-outbound"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.9.0/24"]

  delegation {
    name = "appservice-outbound"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "functions_outbound" {
  name                 = "snet-functions-outbound"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.10.0/24"]

  delegation {
    name = "functions-outbound"

    # Flex Consumption uses the Microsoft.App platform for VNet integration.
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "workload_private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.11.0/24"]
}

resource "azurerm_subnet" "aks_ingress" {
  name                 = "snet-aks-ingress"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.2.12.0/27"]
}

resource "azurerm_subnet" "data_private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.data.name
  address_prefixes     = ["10.3.1.0/24"]
}

resource "azurerm_subnet" "agents" {
  name                 = "snet-devops-agents"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.management.name
  address_prefixes     = ["10.4.0.0/24"]
}

resource "azurerm_subnet" "ansible" {
  name                 = "snet-ansible"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.management.name
  address_prefixes     = ["10.4.1.0/28"]
}

resource "azurerm_subnet" "management_private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.management.name
  address_prefixes     = ["10.4.2.0/24"]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = local.spoke_vnets

  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = each.value.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = local.spoke_vnets

  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = each.value.resource_group_name
  virtual_network_name         = each.value.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  allow_virtual_network_access = true
}

resource "azurerm_route_table" "ingress" {
  name                = "rt-ingress-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_route" "ingress_default" {
  name                   = "default-to-firewall"
  resource_group_name    = var.hub_resource_group_name
  route_table_name       = azurerm_route_table.ingress.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "appgw" {
  subnet_id      = azurerm_subnet.appgw.id
  route_table_id = azurerm_route_table.ingress.id
}

resource "azurerm_route_table" "workload" {
  name                = "rt-workload-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_route" "workload_default" {
  name                   = "default-to-firewall"
  resource_group_name    = var.hub_resource_group_name
  route_table_name       = azurerm_route_table.workload.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "aks_system" {
  subnet_id      = azurerm_subnet.aks_system.id
  route_table_id = azurerm_route_table.workload.id
}

resource "azurerm_subnet_route_table_association" "aks_user" {
  subnet_id      = azurerm_subnet.aks_user.id
  route_table_id = azurerm_route_table.workload.id
}

resource "azurerm_subnet_route_table_association" "apim_outbound" {
  subnet_id      = azurerm_subnet.apim_outbound.id
  route_table_id = azurerm_route_table.workload.id
}

resource "azurerm_subnet_route_table_association" "appservice_outbound" {
  subnet_id      = azurerm_subnet.appservice_outbound.id
  route_table_id = azurerm_route_table.workload.id
}

resource "azurerm_subnet_route_table_association" "functions_outbound" {
  subnet_id      = azurerm_subnet.functions_outbound.id
  route_table_id = azurerm_route_table.workload.id
}

resource "azurerm_subnet_route_table_association" "aks_ingress" {
  subnet_id      = azurerm_subnet.aks_ingress.id
  route_table_id = azurerm_route_table.workload.id
}

resource "azurerm_route_table" "management" {
  name                = "rt-management-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_route" "management_default" {
  name                   = "default-to-firewall"
  resource_group_name    = var.hub_resource_group_name
  route_table_name       = azurerm_route_table.management.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "agents" {
  subnet_id      = azurerm_subnet.agents.id
  route_table_id = azurerm_route_table.management.id
}

resource "azurerm_subnet_route_table_association" "ansible" {
  subnet_id      = azurerm_subnet.ansible.id
  route_table_id = azurerm_route_table.management.id
}

# Minimal NSGs. The AKS-specific NSG rules are added in the AKS module.
resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-appgw-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowOutboundToVnet"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_network_security_group" "apim_outbound" {
  name                = "nsg-apim-outbound-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowOutboundHttps"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_network_security_group" "web_outbound" {
  name                = "nsg-web-outbound-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowOutboundHttps"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-private-endpoints-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowHttpsFromVnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "management" {
  name                = "nsg-management-${var.environment}"
  location            = data.azurerm_resource_group.platform.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowSshFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

resource "azurerm_subnet_network_security_group_association" "apim_outbound" {
  subnet_id                 = azurerm_subnet.apim_outbound.id
  network_security_group_id = azurerm_network_security_group.apim_outbound.id
}

resource "azurerm_subnet_network_security_group_association" "appservice_outbound" {
  subnet_id                 = azurerm_subnet.appservice_outbound.id
  network_security_group_id = azurerm_network_security_group.web_outbound.id
}

resource "azurerm_subnet_network_security_group_association" "functions_outbound" {
  subnet_id                 = azurerm_subnet.functions_outbound.id
  network_security_group_id = azurerm_network_security_group.web_outbound.id
}

resource "azurerm_subnet_network_security_group_association" "workload_pe" {
  subnet_id                 = azurerm_subnet.workload_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_subnet_network_security_group_association" "data_pe" {
  subnet_id                 = azurerm_subnet.data_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_subnet_network_security_group_association" "management_pe" {
  subnet_id                 = azurerm_subnet.management_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_subnet_network_security_group_association" "agents" {
  subnet_id                 = azurerm_subnet.agents.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "ansible" {
  subnet_id                 = azurerm_subnet.ansible.id
  network_security_group_id = azurerm_network_security_group.management.id
}

output "ingress_vnet_id" {
  value = azurerm_virtual_network.ingress.id
}

output "workload_vnet_id" {
  value = azurerm_virtual_network.workload.id
}

output "data_vnet_id" {
  value = azurerm_virtual_network.data.id
}

output "management_vnet_id" {
  value = azurerm_virtual_network.management.id
}

output "appgw_subnet_id" {
  value = azurerm_subnet.appgw.id
}

output "aks_system_subnet_id" {
  value = azurerm_subnet.aks_system.id
}

output "aks_user_subnet_id" {
  value = azurerm_subnet.aks_user.id
}

output "apim_outbound_subnet_id" {
  value = azurerm_subnet.apim_outbound.id
}

output "appservice_outbound_subnet_id" {
  value = azurerm_subnet.appservice_outbound.id
}

output "functions_outbound_subnet_id" {
  value = azurerm_subnet.functions_outbound.id
}

output "workload_private_endpoints_subnet_id" {
  value = azurerm_subnet.workload_private_endpoints.id
}

output "data_private_endpoints_subnet_id" {
  value = azurerm_subnet.data_private_endpoints.id
}

output "management_private_endpoints_subnet_id" {
  value = azurerm_subnet.management_private_endpoints.id
}

output "agents_subnet_id" {
  value = azurerm_subnet.agents.id
}

output "ansible_subnet_id" {
  value = azurerm_subnet.ansible.id
}
