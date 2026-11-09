data "azuread_client_config" "current" {}

locals {
  app_roles = {
    "Inventory.Reader" = {
      description = "Read inventory records"
      display     = "Inventory Reader"
    }
    "Inventory.Contributor" = {
      description = "Create and update inventory records"
      display     = "Inventory Contributor"
    }
    "Order.Reader" = {
      description = "Read own orders"
      display     = "Order Reader"
    }
    "Order.Contributor" = {
      description = "Create and update own orders"
      display     = "Order Contributor"
    }
    "Logistics.Manager" = {
      description = "Delete inventory and orders; read all orders"
      display     = "Logistics Manager"
    }
    "Partner.Webhook" = {
      description = "Submit carrier delivery-status webhooks"
      display     = "Partner Webhook"
    }
  }

  # Partner.Webhook is for application clients, not the human lab user.
  user_roles = toset([
    "Inventory.Reader",
    "Inventory.Contributor",
    "Order.Reader",
    "Order.Contributor",
    "Logistics.Manager",
  ])

  assignment_object_id = coalesce(
    var.role_assignment_object_id,
    data.azuread_client_config.current.object_id,
  )
  assign_human_roles = var.assign_roles_to_current_user || var.role_assignment_object_id != null
}

resource "random_uuid" "scope" {}

resource "random_uuid" "app_roles" {
  for_each = local.app_roles
}

resource "azuread_application" "api" {
  display_name     = var.display_name
  identifier_uris  = [var.audience]
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the client to access the logistics API as the signed-in user."
      admin_consent_display_name = "Access logistics API"
      enabled                    = true
      id                         = random_uuid.scope.result
      type                       = "User"
      user_consent_description   = "Allow the client to access the logistics API as you."
      user_consent_display_name  = "Access logistics API"
      value                      = "access_as_user"
    }
  }

  dynamic "app_role" {
    for_each = local.app_roles

    content {
      allowed_member_types = ["User", "Application"]
      description          = app_role.value.description
      display_name         = app_role.value.display
      enabled              = true
      id                   = random_uuid.app_roles[app_role.key].result
      value                = app_role.key
    }
  }

  notes = "Managed by Terraform for the logistics platform lab."
}

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
}

# Public client used for interactive user sign-in and device-code token
# acquisition. Azure CLI cannot request tokens for an arbitrary custom API.
resource "azuread_application" "cli" {
  display_name     = "logistics-cli"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  public_client {
    redirect_uris = ["http://localhost"]
  }

  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = azuread_application.api.oauth2_permission_scope_ids["access_as_user"]
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "cli" {
  client_id = azuread_application.cli.client_id
}

resource "azuread_service_principal_delegated_permission_grant" "cli" {
  service_principal_object_id          = azuread_service_principal.cli.object_id
  resource_service_principal_object_id = azuread_service_principal.api.object_id
  claim_values                         = ["access_as_user"]
}

resource "azuread_app_role_assignment" "user_roles" {
  for_each = local.assign_human_roles ? local.user_roles : toset([])

  app_role_id         = azuread_application.api.app_role_ids[each.value]
  principal_object_id = local.assignment_object_id
  resource_object_id  = azuread_service_principal.api.object_id
}

output "client_id" {
  value = azuread_application.api.client_id
}

output "application_object_id" {
  value = azuread_application.api.object_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.api.object_id
}

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "audience" {
  value = var.audience
}

output "issuer" {
  value = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
}

output "jwks_url" {
  value = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/discovery/v2.0/keys"
}

output "app_role_ids" {
  value = azuread_application.api.app_role_ids
}

output "cli_client_id" {
  value = azuread_application.cli.client_id
}

output "cli_service_principal_object_id" {
  value = azuread_service_principal.cli.object_id
}
