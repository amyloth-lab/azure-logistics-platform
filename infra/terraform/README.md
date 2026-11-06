# Terraform - Layout and Day 2 Status

Day 2 implements the state bootstrap and the secure hub. Spokes, AKS, APIM, data services, and the application arrive on Day 3+.

Implemented now:

- `bootstrap/` - state resource group, storage account, container, Entra auth, versioning, soft delete, temporary deployer IP allow-list.
- `modules/network-hub/` - hub VNet, seven subnets, Bastion/shared NSGs.
- `modules/firewall/` - Azure Firewall, policy, public IP, diagnostics.
- `modules/bastion/` - Azure Bastion and public IP.
- `modules/observability/` - Log Analytics workspace.
- `modules/private-dns/` - nine private DNS zones linked to the hub.
- `modules/policy/` - subscription-scope deny of public IPs outside approved resource groups.
- `envs/dev/` - wires the modules together and creates the budget.

Still planned for Day 3+:

```text
infra/terraform/
├── bootstrap/                 # implemented: state storage, role assignment, container
├── modules/
│   ├── network-hub/           # implemented: hub VNet, seven subnets, Bastion/shared NSGs
│   ├── firewall/              # implemented: firewall, policy, public IP, diagnostics
│   ├── bastion/               # implemented: Bastion and public IP
│   ├── observability/         # implemented: Log Analytics
│   ├── private-dns/           # implemented: nine zones + hub links
│   ├── policy/                # implemented: deny public IP outside approved RGs
│   ├── network-spoke/         # planned: spokes, peering, route tables
│   ├── aks/                   # planned: private cluster, node pools, add-ons, identities
│   ├── app-service/           # planned: plan, app, slots, VNet integration, private endpoint
│   ├── functions/             # planned: Flex Consumption, VNet integration, settings
│   ├── apim/                  # planned: Standard v2, private endpoint, outbound integration
│   ├── data/                  # planned: SQL, Redis, Storage, Key Vault, Service Bus
│   └── acr/                   # planned: registry, private endpoint, retention
├── envs/
│   ├── dev/
│   │   ├── backend.hcl.example
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars.example
│   └── prod/                  # planned
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
