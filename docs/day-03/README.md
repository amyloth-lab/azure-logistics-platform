# Day 3A - Spokes, Private DNS, ACR, Key Vault, and Data Services

**Timebox:** 4-5 hours
**Mode:** Build the network and data foundation. No AKS, APIM, App Service, Functions, or application code today.
**Outcome:** Four spoke VNets, hub peering, route tables, private DNS links, ACR, Key Vault, Azure SQL, Blob Storage, Service Bus, and Azure Managed Redis are deployed privately.

> **Before starting:** read [the project state](../PROJECT-STATE.md). It is the compact memory of Days 1-2 and the current Day 3A blocker.

> **Why "3A"?** Day 3 in the original plan tried to build the network, every data service, AKS, APIM, App Service, Functions, ACR, and Ansible in one sitting. That is not a realistic 4-5 hour day for a first DevOps role, and it is how insecure shortcuts happen. Day 3 is split into **3A** (network + data) and **3B** (AKS + APIM + App Service + Functions + Ansible). Finish 3A, reply `EOD`, then 3B is released.

---

## 1. What this builds

```text
Network spokes
  -> vnet-ingress    10.1.0.0/16  (App Gateway later)
  -> vnet-workload   10.2.0.0/16  (AKS, APIM, App Service, Functions later)
  -> vnet-data       10.3.0.0/16  (private endpoints)
  -> vnet-management 10.4.0.0/16  (agents, Ansible, ACR)
  -> hub <-> spoke peering
  -> route tables: 0.0.0.0/0 -> Azure Firewall
  -> private DNS zone links to every spoke

Private services
  -> ACR Premium + private endpoint
  -> Key Vault + private endpoint
  -> Azure SQL server/database + private endpoint
  -> Storage account + documents/audit containers + private endpoint
  -> Service Bus Premium namespace + topics/subscriptions + private endpoint
  -> Azure Managed Redis + private endpoint
```

What is **not** built today:

- AKS cluster.
- APIM instance.
- App Service, Functions, App Gateway.
- Ansible baseline VMs.
- The FastAPI application.
- Build or release pipelines.

Those are Day 3B and Day 4.

---

## 2. Preflight

### 2.1 Confirm Day 2

```powershell
# Run from the repository root
git status
git log --oneline -3
```

You should be on `main` with Day 2 committed. The Day 2 hub should be applied and `terraform plan` should have been clean.

### 2.2 Confirm Terraform and Azure CLI

```powershell
terraform version
az account show --query "{name:name,id:id,state:state}" -o table
```

If Azure CLI still throws the `.azure` permission error, fix it before proceeding:

```powershell
icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T
```

Then reopen the terminal and run `az login` again.

### 2.3 Confirm the state backend

```powershell
cd infra\terraform\envs\dev
terraform init -backend-config=backend.hcl
terraform state list
```

The state key remains `dev/hub.tfstate` for continuity. It now manages the dev platform, not only the hub. Do not rename it in the middle of the week.

---

## 3. What changed in the code

New modules:

```text
infra/terraform/modules/
├── network-spokes/   # four VNets, 12 subnets, peering, route tables, NSGs
├── acr/              # Premium registry + private endpoint
├── keyvault/         # RBAC vault + private endpoint
└── data/             # SQL, Storage, Service Bus, Managed Redis + endpoints
```

New providers in `envs/dev/versions.tf`:

- `hashicorp/random` for unique names.
- `Azure/azapi` for storage containers when shared keys are disabled.
- `hashicorp/azurerm` remains the main provider.

The `data` module uses `azapi_resource` for blob containers because `azurerm_storage_container` can require shared-key auth even when `storage_use_azuread` is enabled. Shared keys stay disabled.

---

## 4. Review the plan first

```powershell
cd infra\terraform\envs\dev
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ..\..
terraform validate
terraform plan -out=day3a.tfplan
```

The plan is large. Expect roughly:

- 2 new resource groups: data and management.
- 4 spoke VNets.
- 12 subnets.
- 8 VNet peerings.
- 3 route tables, 3 default routes, and 9 route-table associations.
- 5 NSGs and their subnet associations.
- 36 private DNS links (9 zones x 4 spokes).
- ACR + private endpoint.
- Key Vault + private endpoint.
- SQL server + database + private endpoint.
- Storage account + 2 containers + private endpoint.
- Service Bus Premium namespace + 3 topics + 2 subscriptions + private endpoint. Private endpoints are not supported on Standard.
- Managed Redis + private endpoint.
- Service Bus topics: `orders`, `inventory`, `shipments`.
- Subscriptions: `order-processor`, `order-audit`.

You should **not** see AKS, APIM, App Service, Functions, or App Gateway.

> Review every `destroy`/`replace`. Day 3A should mostly add resources. If Terraform wants to replace the hub VNet or firewall, stop and investigate.

**Checkpoint:** the plan is understood and contains no unexpected destroys.

---

## 5. Apply

```powershell
terraform apply day3a.tfplan
```

This can take 20-40 minutes. SQL, Redis, and the private endpoints are slow.

### Likely failures and fixes

| Error | Cause | Fix |
|---|---|---|
| `A resource with the ID ... already exists` | A previous partial apply created it | Import it or remove the duplicate; do not delete blindly |
| SQL Entra admin error | `sql_admin_object_id` is wrong or the identity lacks permission | Check `az ad signed-in-user show --query id -o tsv`; use a user/group that can administer SQL |
| Managed Redis SKU unavailable | `Balanced_B0` not available in region/capacity | Try `Balanced_B1`; record the cost change |
| Storage container 403 | Wrong provider path | Confirm `azapi` provider is initialized; do not enable shared keys |
| Private DNS link already exists | Name collision from a previous attempt | Use `terraform state list` and import/adjust |
| ACR name taken | Global name collision | Re-run with a new `random_string` suffix; do not reuse a deleted registry name immediately |
| Policy blocks a public IP | A data service accidentally enabled public access | Fix the module; do not weaken the policy |

**Checkpoint:** apply completes without errors.

---

## 6. Validate the network

### 6.1 VNets and subnets

```powershell
az network vnet list `
  --query "[?starts_with(name, 'vnet-')].{name:name,space:addressSpace.addressPrefixes[0]}" `
  --output table

az network vnet subnet list `
  --resource-group rg-logistics-platform-dev `
  --vnet-name vnet-workload-dev `
  --output table
```

Expected workload subnets:

```text
snet-aks-system
snet-aks-user
snet-apim-outbound
snet-appservice-outbound
snet-functions-outbound
snet-private-endpoints
snet-aks-ingress
```

### 6.2 Peering

```powershell
az network vnet peering list `
  --resource-group rg-logistics-platform-dev `
  --vnet-name vnet-hub-dev `
  --output table
```

You should see four peerings from the hub, one to each spoke. Each spoke should also have a peering back to the hub.

### 6.3 Route tables

```powershell
az network route-table list `
  --resource-group rg-logistics-platform-dev `
  --query "[].{name:name,route:routes[0].addressPrefix,nextHop:routes[0].nextHopIpAddress}" `
  --output table
```

The default route should point to the firewall private IP, normally `10.0.0.4`.

### 6.4 Private DNS links

```powershell
az network private-dns link vnet list `
  --resource-group rg-logistics-platform-dev `
  --zone-name privatelink.database.windows.net `
  --output table
```

You should see the hub link plus links to ingress, workload, data, and management.

**Checkpoint:** every spoke is peered, routed to the firewall, and linked to the private DNS zones.

---

## 7. Validate the private services

### 7.1 Private endpoints

```powershell
az network private-endpoint list `
  --query "[].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" `
  --output table
```

Expected six private endpoints:

- ACR
- Key Vault
- SQL
- Storage Blob
- Service Bus
- Managed Redis

All should be `Approved`.

### 7.2 SQL

```powershell
az sql server list `
  --resource-group rg-logistics-data-dev `
  --query "[].{name:name,fqdn:fullyQualifiedDomainName,public:publicNetworkAccess}" `
  --output table
```

Expected `publicNetworkAccess` is `Disabled`. The database is `sqldb-logistics`.

### 7.3 Storage

```powershell
az storage account list `
  --resource-group rg-logistics-data-dev `
  --query "[].{name:name,public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}" `
  --output table
```

Expected: public access disabled, shared key disabled. Do not try to browse the containers from the public internet; use a private endpoint path from a VM or the AKS cluster later.

### 7.4 Service Bus

```powershell
az servicebus namespace list `
  --resource-group rg-logistics-data-dev `
  --query "[].{name:name,public:publicNetworkAccess,localAuth:disableLocalAuth}" `
  --output table
```

Expected public access disabled and local auth disabled. The app will use managed identity later.

### 7.5 Managed Redis

```powershell
az redisenterprise show `
  --resource-group rg-logistics-data-dev `
  --name <redis-name> `
  --query "{name:name,host:hostName,public:publicNetworkAccess}" `
  --output table
```

Expected public access disabled. Access keys are disabled in the database configuration.

### 7.6 Key Vault

```powershell
az keyvault list `
  --resource-group rg-logistics-data-dev `
  --query "[].{name:name,public:publicNetworkAccess}" `
  --output table
```

Expected public access disabled. You will not be able to read secrets from your laptop until you use a private-network path; that is intentional.

### 7.7 ACR

```powershell
az acr list `
  --resource-group rg-logistics-management-dev `
  --query "[].{name:name,loginServer:loginServer,public:publicNetworkAccess,admin:adminUserEnabled}" `
  --output table
```

Expected: Premium, public access disabled, admin disabled.

**Checkpoint:** all six private endpoints are approved and every data service has public access disabled.

---

## 8. DNS verification without a workload VM

You do not have an AKS pod or management VM yet, so you cannot run a full `nslookup` from inside the VNet. For today, verify the DNS records exist:

```powershell
az network private-dns record-set a list `
  --resource-group rg-logistics-platform-dev `
  --zone-name privatelink.database.windows.net `
  --output table
```

Repeat for `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`, `privatelink.servicebus.windows.net`, `privatelink.redis.azure.net`, and `privatelink.azurecr.io`.

The real resolution test happens in Day 3B from an AKS debug pod or management VM.

---

## 9. Commit and tag Day 3A

```powershell
# Run from the repository root
git status --short
git check-ignore -v infra\terraform\envs\dev\day3a.tfplan
git add infra\terraform docs\day-03 README.md scripts\validate_repo.py
git commit -m "feat(day-3a): spoke network, private endpoints, and data services"
git tag -a day-3a -m "Day 3A checkpoint: network and data platform"
git push origin main --tags
```

**Checkpoint:** commit and tag are pushed.

---

## 10. Day 3A acceptance checklist

- [ ] Four spoke VNets exist with the documented CIDRs.
- [ ] Hub-to-spoke and spoke-to-hub peerings are connected.
- [ ] Workload, ingress, and management route tables send `0.0.0.0/0` to the firewall.
- [ ] Private DNS zones are linked to all four spokes.
- [ ] ACR is Premium, private, and admin-disabled.
- [ ] Key Vault has RBAC, purge protection, and a private endpoint.
- [ ] SQL is Entra-only and private.
- [ ] Storage has public access and shared keys disabled.
- [ ] Service Bus has public access and local auth disabled.
- [ ] Managed Redis is private and access keys are disabled.
- [ ] Six private endpoints are Approved.
- [ ] No AKS, APIM, App Service, Functions, or App Gateway yet.
- [ ] `terraform plan` is clean or only shows known drift.

---

## 11. Cost check

Day 3A adds:

- ACR Premium (fixed monthly).
- Azure SQL serverless database (scales to zero when idle, but storage and backup cost).
- Managed Redis Balanced B0.
- Service Bus Premium, 1 messaging unit (required for private endpoint; significantly more expensive than Standard).
- Storage account.
- Six private endpoints.
- Key Vault.

Check Cost Management tomorrow. If you are stopping for more than a day, consider `terraform destroy` on the dev stack, but keep the state storage. Recreating is slow but cheaper than leaving everything idle.

---

## 12. End of Day 3A

Reply with exactly:

```text
EOD
```

Day 3B will add:

- AKS private cluster.
- APIM Standard v2 with private endpoint and outbound integration.
- App Service and Functions.
- App Gateway WAF_v2.
- Ansible control/agent VMs and the Kubernetes baseline.

Do not start AKS or APIM today. The network and data foundation must be stable first.
