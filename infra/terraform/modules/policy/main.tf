data "azurerm_subscription" "current" {}

resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "deny-public-ip-outside-approved-rgs"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny public IPs outside approved resource groups"
  description  = "Only the edge and hub resource groups may create public IP addresses. Everything else must use private endpoints."

  parameters = jsonencode({
    allowedResourceGroups = {
      type = "Array"
      metadata = {
        displayName = "Allowed resource groups"
        description = "Resource groups permitted to create public IP addresses."
      }
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/publicIPAddresses"
        },
        {
          value = "[resourceGroup().name]"
          notIn = "[parameters('allowedResourceGroups')]"
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })

  metadata = jsonencode({
    category = "Network"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "deny_public_ip" {
  name                 = "deny-public-ip-outside-approved-rgs"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.deny_public_ip.id
  display_name         = "Deny public IPs outside approved resource groups"
  enforce              = true

  parameters = jsonencode({
    allowedResourceGroups = {
      value = var.allowed_public_ip_resource_groups
    }
  })
}

output "policy_assignment_id" {
  value = azurerm_subscription_policy_assignment.deny_public_ip.id
}
