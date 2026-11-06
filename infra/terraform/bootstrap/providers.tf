provider "azurerm" {
  features {}

  # Use Entra ID for storage data-plane operations. Do not fall back to account keys.
  storage_use_azuread = true
}
