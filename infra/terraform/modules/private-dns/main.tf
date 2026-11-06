resource "azurerm_private_dns_zone" "this" {
  for_each = toset(var.zones)

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = toset(var.zones)

  name                  = "link-hub-${replace(each.value, ".", "-")}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value].name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

output "zone_ids" {
  value = { for zone, resource in azurerm_private_dns_zone.this : zone => resource.id }
}
