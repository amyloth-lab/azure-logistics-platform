# Terraform - Planned Layout

This directory is intentionally empty on Day 1. Terraform work starts on Day 2 with the state bootstrap and the hub.

```text
infra/terraform/
├── bootstrap/                 # state storage, initial RG (local state, then migrate)
├── modules/
│   ├── network-hub/           # hub VNet, firewall, Bastion, gateway, DNS resolver
│   ├── network-spoke/         # spoke VNet, subnets, peering, route tables, NSGs
│   ├── private-dns/           # zones, links, records
│   ├── aks/                   # private cluster, node pools, add-ons, identities
│   ├── app-service/           # plan, app, slots, VNet integration, private endpoint
│   ├── functions/             # Flex Consumption, VNet integration, app settings
│   ├── apim/                  # Standard v2, private endpoint, outbound integration
│   ├── data/                  # SQL, Redis, Storage, Key Vault, Service Bus
│   ├── acr/                   # registry, private endpoint, retention
│   ├── observability/         # Log Analytics, App Insights, diagnostics, alerts
│   └── security/              # policy, Defender, role assignments
├── envs/
│   ├── dev/
│   │   ├── backend.hcl.example
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars.example
│   └── prod/
└── README.md
```

## Backend shape (example, no secrets)

```hcl
terraform {
  required_version = ">= 1.9.0"

  backend "azurerm" {
    resource_group_name  = "rg-logistics-tfstate"
    storage_account_name = "stlogisticstfstate<unique>"
    container_name       = "tfstate"
    key                  = "dev/network.tfstate"
    use_azuread_auth     = true
  }
}
```

The pipeline supplies `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, and `ARM_USE_OIDC=true`. There is no storage key in the backend configuration. The blob lease provides state locking.

## Non-negotiable rules

- Remote state in Azure Blob, Entra-only auth, private endpoint, versioning, soft delete, lease locking.
- One state key per environment and stack. Do not share a state file across environments.
- Pin Terraform and provider versions. Commit `.terraform.lock.hcl`.
- No secrets in `.tf` or `.tfvars`. Use managed identities and Key Vault references.
- No public IPs or public PaaS access unless the ADR explicitly permits it.
- Tag every resource with `env`, `owner`, `costCenter`, `workload`, `dataClassification`, `managedBy`.
- Run `terraform fmt`, `validate`, `tflint`, and `checkov` before every PR.
- Plans are artifacts. Production apply requires approval.
- `prevent_destroy` on state storage, Key Vault, and other recovery-critical resources.
- Do not use `latest` image tags or unpinned modules.

## Day 2 sequence

1. Bootstrap state storage with Azure CLI.
2. Configure the backend and migrate local state.
3. Build the hub network and shared security.
4. Assign policy, budget, and diagnostic settings.
5. Prove state locking and a clean plan before moving to Day 3.
