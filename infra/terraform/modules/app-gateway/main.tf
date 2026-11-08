resource "azurerm_public_ip" "this" {
  name                = "pip-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_web_application_firewall_policy" "this" {
  name                = "waf-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

resource "azurerm_application_gateway" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.this.id

  gateway_ip_configuration {
    name      = "gwip"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = "feip"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = "https"
    port = 443
  }

  ssl_certificate {
    name     = "listener-cert"
    data     = filebase64(var.ssl_certificate_path)
    password = var.ssl_certificate_password
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "feip"
    frontend_port_name             = "https"
    protocol                       = "Https"
    ssl_certificate_name           = "listener-cert"
    host_name                      = var.hostname
    require_sni                    = true
  }

  backend_address_pool {
    name  = "apim"
    fqdns = [var.apim_fqdn]
  }

  probe {
    name                                      = "apim-health"
    protocol                                  = "Https"
    path                                      = "/status-0123456789abcdef"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200"]
    }
  }

  backend_http_settings {
    name                                = "apim-https"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
    probe_name                          = "apim-health"
  }

  request_routing_rule {
    name                       = "api"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "apim"
    backend_http_settings_name = "apim-https"
  }
}

output "id" {
  value = azurerm_application_gateway.this.id
}

output "public_ip" {
  value = azurerm_public_ip.this.ip_address
}

output "hostname" {
  value = var.hostname
}
