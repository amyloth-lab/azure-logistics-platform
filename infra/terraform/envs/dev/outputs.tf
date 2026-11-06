output "platform_resource_group" {
  value = azurerm_resource_group.platform.name
}

output "workload_resource_group" {
  value = azurerm_resource_group.workload.name
}

output "hub_vnet_id" {
  value = module.network_hub.vnet_id
}

output "firewall_private_ip" {
  value = module.firewall.firewall_private_ip
}

output "firewall_public_ip" {
  value = module.firewall.firewall_public_ip
}

output "bastion_public_ip" {
  value = module.bastion.bastion_public_ip
}

output "log_analytics_workspace_id" {
  value = module.observability.workspace_id
}

output "private_dns_zone_ids" {
  value = module.private_dns.zone_ids
}

output "policy_assignment_id" {
  value = module.policy.policy_assignment_id
}
