# Day 2 - Terraform State Bootstrap and the Secure Hub

**Timebox:** 4-5 hours
**Mode:** Build the foundation. No AKS, APIM, SQL, Redis, or application code today.
**Outcome:** Terraform state is in Azure Blob with locking, and the hub network, firewall, Bastion, private DNS zones, Log Analytics, policy guardrail, and budget are deployed.

Read this once, then work top to bottom. Every step has a checkpoint.

---

## 1. What you are building today

```text
Terraform state
  -> resource group rg-logistics-tfstate
  -> storage account, private container, Entra-only auth, versioning, soft delete
  -> bootstrap state migrated from local to Blob

Hub
  -> vnet-hub-dev 10.0.0.0/16
  -> AzureFirewallSubnet, AzureFirewallManagementSubnet, AzureBastionSubnet,
     GatewaySubnet, DNS inbound/outbound, shared subnet
  -> Azure Firewall Basic or Standard + policy + public IP
  -> Azure Bastion Basic + public IP
  -> 9 private DNS zones linked to the hub
  -> Log Analytics workspace
  -> custom policy: deny public IPs outside approved resource groups
  -> monthly budget with alerts
```

You are **not** building today:

- AKS or its node pools.
- APIM, App Gateway, App Service, Functions.
- SQL, Redis, Blob application storage, Service Bus, Key Vault private endpoints.
- The API application.

Those are Day 3 and Day 4.

---

## 2. Preflight (20 minutes)

### 2.1 Confirm the Day 1 checkpoint

From the repository root:

```powershell
git status
git log --oneline -3
```

You should be on `main`, with your Day 1 work committed.

### 2.2 Make Terraform available

Check:

```powershell
terraform version
```

If Terraform is not recognized, add the winget package directory to this terminal:

```powershell
$tfDir = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Hashicorp.Terraform_*" -Recurse -Filter terraform.exe | Select-Object -First 1).DirectoryName
$env:Path = "$tfDir;$env:Path"
terraform version
```

You want Terraform **1.9 or later**.

### 2.3 Make Azure CLI work

```powershell
az account show --query "{name:name,id:id,tenantId:tenantId,state:state}" -o table
```

If you see `PermissionError` under `C:\Users\OEM\.azure`, fix the ACL from an **Administrator** PowerShell:

```powershell
icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T
```

Then reopen the terminal and run:

```powershell
az login
az account list --output table
az account set --subscription "<your-subscription-id>"
az account show --query "{name:name,id:id,state:state}" -o table
```

**Checkpoint:** `az account show` returns the intended subscription and `Enabled`.

### 2.4 Confirm permissions

You need:

- Permission to create resource groups, VNets, firewalls, Bastion, and Log Analytics (Contributor or equivalent).
- Permission to create role assignments on the new storage account (`Owner`, `User Access Administrator`, or a custom role with `Microsoft.Authorization/roleAssignments/write`).
- Permission to create and assign an Azure Policy definition (`Owner`, `Resource Policy Contributor`, or equivalent).
- Permission to create a subscription budget (`Microsoft.Consumption/budgets/write`).

If you are missing the role-assignment or policy permission, ask the subscription owner before you start. Do not work around it by enabling shared keys or skipping the policy.

### 2.5 Confirm the region and cost decision

This guide uses `australiaeast`.

> **Use a dedicated lab subscription.** The policy guardrail in this stack is assigned at subscription scope and denies public IPs outside two resource groups. In a shared subscription it can block unrelated workloads. If you must share a subscription, stop and change the policy assignment scope to the workload resource groups before applying.

- Azure Firewall **Basic** is the default lab SKU. Basic **always has a management NIC**, so the module creates a management public IP and attaches `AzureFirewallManagementSubnet`. The extra public IP is small; the firewall SKU cost is unchanged. **Standard** is an acceptable fallback if Basic is unavailable; it costs more but supports threat-intelligence deny mode and threat-intelligence logs. Premium adds IDPS/TLS inspection and is not required for Day 2.
- Azure Bastion **Basic** is used in the lab. It also has a fixed monthly cost.
- Standard firewall pricing is roughly **USD 900-1,000/month** plus data processing. Adjust your budget before leaving it running.
- If either is too expensive, stop now and decide: use a different lab profile, or accept the cost for 2-3 days.
- Do not deploy the hub and leave it running for weeks without a budget.

Create the budget variables in `infra/terraform/envs/dev/terraform.tfvars` later. Put a real email in `budget_contact_emails`, or set it to `[]` to disable the budget for now. A disabled budget is a documented gap, not a silent one.

---

## 3. The Terraform layout

```text
infra/terraform/
├── bootstrap/                 # local state first, then migrate to Blob
│   ├── main.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── versions.tf
│   ├── backend.tf.example
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── modules/
│   ├── network-hub/           # VNet, subnets, Bastion/Shared NSGs
│   ├── firewall/              # Azure Firewall + policy + public IP
│   ├── bastion/               # Azure Bastion + public IP
│   ├── observability/         # Log Analytics
│   ├── private-dns/           # zones + hub links
│   └── policy/                # deny public IPs outside approved RGs
└── envs/dev/                  # wires the modules together
    ├── main.tf
    ├── providers.tf
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    ├── backend.hcl.example
    └── terraform.tfvars.example
```

The bootstrap is a separate stack because the state storage cannot store its own creation state until it exists. This is the chicken-and-egg problem described in [ADR-0007](../adr/0007-terraform-remote-state.md).

---

## 4. Step 1 - Bootstrap the state storage (45 minutes)

### 4.1 Get your public IP

```powershell
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
"$ip/32"
```

This is the IP that will be allowed to reach the state storage during bootstrap. If your ISP changes it, update `deployer_ip` and re-apply.

### 4.2 Configure and apply the bootstrap

```powershell
cd infra\terraform\bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Set:

```hcl
prefix      = "logistics"
environment = "dev"
location    = "australiaeast"
deployer_ip = "<your-ip>/32"
```

Then:

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Expected resources:

- `azurerm_resource_group.tfstate`
- `random_string.suffix`
- `azurerm_storage_account.tfstate`
- `azurerm_role_assignment.state_rw`
- `time_sleep.wait_for_rbac`
- `azapi_resource.tfstate` (the `tfstate` container)

The container is created through the **ARM control plane** with `azapi_resource`, not `azurerm_storage_container`. The `azurerm` container resource can require shared-key auth even when `storage_use_azuread` is enabled; we want shared keys disabled, so ARM is the correct path.

The `time_sleep` gives Entra RBAC time to propagate before you migrate the backend state. If the backend write fails with `AuthorizationPermissionMismatch`, wait 5 minutes and retry. Do not disable Entra auth or turn on shared keys to "fix" it.

**Checkpoint:** `terraform output` returns the resource group, storage account, container, and backend configuration.

### 4.3 Migrate the bootstrap state into Blob

Get the backend configuration:

```powershell
terraform output -raw backend_config
```

Write it to a local ignored file:

```powershell
$backend = terraform output -raw backend_config
[System.IO.File]::WriteAllText((Join-Path (Get-Location) "backend.hcl"), $backend)
```

Create the backend block from the example:

```powershell
Copy-Item backend.tf.example backend.tf
terraform init -backend-config=backend.hcl -migrate-state
```

Terraform asks whether to copy the existing local state to the new backend. Answer `yes`.

Then prove the backend works:

```powershell
terraform state list
terraform plan
```

**Checkpoint:** `terraform state list` shows the bootstrap resources and `terraform plan` says `No changes`.

`backend.tf`, `backend.hcl`, `terraform.tfstate`, and `bootstrap.tfplan` are ignored by Git. Do not force-add them.

---

## 5. Step 2 - Configure the dev backend (10 minutes)

Move to the dev environment:

```powershell
cd ..\..\envs\dev
Copy-Item backend.hcl.example backend.hcl
notepad backend.hcl
```

Replace `storage_account_name` with the name from the bootstrap output. Keep:

```hcl
resource_group_name  = "rg-logistics-tfstate"
storage_account_name = "<from bootstrap output>"
container_name       = "tfstate"
key                  = "dev/hub.tfstate"
use_azuread_auth     = true
```

Then initialize:

```powershell
terraform init -backend-config=backend.hcl
```

**Checkpoint:** init succeeds and does not ask for a storage key.

---

## 6. Step 3 - Plan the hub (30 minutes)

### 6.1 Set the variables

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Recommended lab values:

```hcl
prefix                            = "logistics"
environment                       = "dev"
location                          = "australiaeast"
firewall_sku_tier                 = "Basic"   # or "Standard" if Basic is unavailable
firewall_threat_intelligence_mode = "Alert"   # Standard supports "Deny" after testing
budget_amount_usd                 = 200
budget_contact_emails             = ["you@example.com"]
```

Set `budget_contact_emails = []` if you do not want the budget yet. Do not leave a fake email and assume alerts work.

### 6.2 Format, validate, plan

```powershell
terraform fmt -check -recursive ..\..
terraform validate
terraform plan -out=hub.tfplan
```

Read the plan summary. You should see approximately:

- 2 resource groups.
- 1 hub VNet.
- 7 subnets.
- 2 NSGs and 2 subnet associations.
- Azure Firewall + policy + public IP.
- Bastion + public IP.
- Log Analytics workspace.
- 9 private DNS zones and 9 hub links.
- 1 custom policy definition + 1 subscription assignment.
- 1 budget (if you supplied an email).

You should **not** see AKS, APIM, SQL, Redis, Service Bus, or App Service.

**Checkpoint:** the plan is understood and contains no unexpected destroys or public IPs in workload resources.

---

## 7. Step 4 - Apply the hub (30-45 minutes)

```powershell
terraform apply hub.tfplan
```

This can take 15-30 minutes because Azure Firewall and Bastion are slow resources.

### If the policy blocks the firewall public IP

The policy allows public IPs only in:

- `rg-logistics-platform-dev`
- `rg-logistics-edge-dev`

The firewall data IP, firewall management IP (Basic), and Bastion public IP are in the platform resource group, so they should pass. If they do not, check the assignment parameters:

```powershell
az policy assignment show --name deny-public-ip-outside-approved-rgs --query "parameters.allowedResourceGroups.value" -o json
```

### If the budget fails

The start date must be the first day of a month. If you are running this later than November 2026, change:

```hcl
budget_start_date = "2026-12-01T00:00:00Z"
```

or the first day of your current month.

### If Azure Firewall Basic is unavailable

Change:

```hcl
firewall_sku_tier = "Standard"
```

Standard is a valid lab fallback. It supports the threat-intelligence log category, so the diagnostic setting includes it automatically (the module only skips that category for Basic). Expect a higher cost and record the SKU change in `review-notes.local.md`.

If the firewall was already created as Basic, Terraform may propose a **replacement** for the SKU change. Read the plan before applying; the firewall can take 20-30 minutes to recreate.

**Checkpoint:** `terraform apply` completes and `terraform output` returns the hub values.

---

## 8. Step 5 - Validate the hub (30 minutes)

### 8.1 Check the network

```powershell
az network vnet subnet list `
  --resource-group rg-logistics-platform-dev `
  --vnet-name vnet-hub-dev `
  --output table
```

Expected subnets:

```text
AzureFirewallSubnet
AzureFirewallManagementSubnet
AzureBastionSubnet
GatewaySubnet
snet-dns-inbound
snet-dns-outbound
snet-shared
```

### 8.2 Check the firewall

```powershell
az network firewall show `
  --resource-group rg-logistics-platform-dev `
  --name afw-dev `
  --query "{privateIp:ipConfigurations[0].privateIPAddress,sku:sku.tier}" `
  --output table
```

Expected private IP: `10.0.0.4`.

### 8.3 Check public IPs

```powershell
az network public-ip list `
  --resource-group rg-logistics-platform-dev `
  --query "[].{name:name,ip:ipAddress,sku:sku.name}" `
  --output table
```

You should see **three for Basic**: the firewall data IP, the firewall management IP, and the Bastion public IP. Standard/Premium show two (data and Bastion). If you see a public IP in the workload resource group, stop and investigate.

### 8.4 Check private DNS

```powershell
az network private-dns zone list `
  --resource-group rg-logistics-platform-dev `
  --query "[].name" `
  --output table
```

Expected nine zones, including:

```text
privatelink.azure-api.net
privatelink.azurewebsites.net
privatelink.database.windows.net
privatelink.redis.azure.net
privatelink.blob.core.windows.net
privatelink.vaultcore.azure.net
privatelink.servicebus.windows.net
privatelink.azurecr.io
privatelink.australiaeast.azmk8s.io
```

### 8.5 Check the policy

Wait 5-10 minutes for the assignment to propagate. Then try to create a public IP in the workload resource group:

```powershell
az network public-ip create `
  --resource-group rg-logistics-workload-dev `
  --name pip-policy-test `
  --sku Standard `
  --allocation-method Static
```

Expected:

```text
RequestDisallowedByPolicy
```

If it succeeds, delete the test IP immediately:

```powershell
az network public-ip delete `
  --resource-group rg-logistics-workload-dev `
  --name pip-policy-test
```

Then inspect the policy assignment and its `allowedResourceGroups` parameter. Do not weaken the policy just to make the test pass.

### 8.6 Check state and drift

```powershell
terraform plan
terraform state list
```

Expected: `No changes`, and the state lists the hub resources.

### 8.7 Check the state backend

```powershell
az storage blob list `
  --account-name <state-storage-account> `
  --container-name tfstate `
  --auth-mode login `
  --output table
```

You should see `bootstrap/terraform.tfstate` and `dev/hub.tfstate`.

**Checkpoint:** all validation commands pass, or you have a written explanation for each exception.

---

## 9. Step 6 - Commit and tag Day 2 (10 minutes)

Check what Git will include:

```powershell
git status --short
```

It should show Terraform source, `.terraform.lock.hcl` files, and documentation. It should **not** show:

- `terraform.tfstate`
- `*.tfplan`
- `terraform.tfvars`
- `backend.hcl`
- `backend.tf`
- `.terraform/`

Confirm ignores:

```powershell
git check-ignore -v infra\terraform\bootstrap\backend.hcl
git check-ignore -v infra\terraform\envs\dev\terraform.tfvars
```

Then:

```powershell
git add infra\terraform docs\day-02 README.md .gitignore
git commit -m "feat(day-2): bootstrap terraform state and hub network"
git tag -a day-2 -m "Day 2 checkpoint: remote state and secure hub"
git push origin main --tags
```

**Checkpoint:** `git log --oneline -1` shows the commit and the tag is pushed.

---

## 10. Day 2 acceptance checklist

- [ ] Terraform state is in Blob, not on the laptop.
- [ ] Bootstrap state was migrated successfully.
- [ ] `use_azuread_auth = true`; no storage keys.
- [ ] State blob has versioning and soft delete.
- [ ] Hub VNet and all seven subnets exist.
- [ ] Azure Firewall and policy exist; private IP is `10.0.0.4`.
- [ ] Azure Bastion exists.
- [ ] Nine private DNS zones are linked to the hub.
- [ ] Log Analytics workspace exists and firewall diagnostics are configured.
- [ ] Policy denies a public IP in the workload resource group.
- [ ] Budget exists, or its absence is documented.
- [ ] `terraform plan` says no changes.
- [ ] Only firewall (data + management) and Bastion public IPs exist in the platform resource group.
- [ ] No AKS, APIM, SQL, Redis, or Service Bus yet.
- [ ] Day 2 commit and tag are pushed.

---

## 11. Cost and cleanup

Day 2 leaves these billable resources running:

- Azure Firewall Basic or Standard (fixed cost; Standard is significantly higher).
- Azure Bastion Basic (fixed cost).
- Three public IPs for Basic (firewall data, firewall management, Bastion); two for Standard/Premium.
- Log Analytics workspace.
- State storage (small).

If you are stopping for more than 24 hours and want to save money:

```powershell
cd infra\terraform\envs\dev
terraform destroy
```

This removes the hub but keeps the state storage. Day 3 can recreate the hub. Do **not** destroy `rg-logistics-tfstate`; that is your Terraform state.

If you keep the hub running, check Cost Management tomorrow morning. The budget alert is not a substitute for looking.

---

## 12. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform: not recognized` | Winget path not in PATH | Reopen terminal or add `$tfDir` to `$env:Path` |
| `az` PermissionError under `.azure` | ACL/ownership on user profile | `icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T` as Administrator |
| `403` creating state container | Wrong API/provider path or RBAC not ready | Confirm `azapi` provider; wait 5 minutes; do not enable shared keys |
| `AuthorizationFailed` creating a role assignment | Missing `Microsoft.Authorization/roleAssignments/write` | Ask for Owner/User Access Administrator at the storage account scope |
| Backend `403` | Wrong identity, IP allow-list, or no data-plane role | `az login` same user; check `deployer_ip`; check `Storage Blob Data Contributor` |
| `StorageAccountAlreadyTaken` | Name collision and state lost | Choose a new prefix or import/adopt the existing account |
| `BasicSkuFirewallMissingManagementIpConfiguration` | Basic requires a management NIC; module input missing | Ensure `firewall_management_subnet_id` is passed and the management public IP exists |
| Firewall apply fails | Subnet/NSG/SKU issue | Confirm `AzureFirewallSubnet` name and `/26`; use Standard if Basic is unavailable in region |
| Policy blocks firewall IP | Platform RG missing from allowed list | Inspect assignment parameters; add platform RG |
| Budget fails | Start date not first of month or past | Set first day of current month |
| Bastion fails | NSG missing required rules | Compare `nsg-bastion-dev` with Azure Bastion required rules |
| `terraform plan` wants to replace firewall | Changed SKU/tier or subnet | Stop; read the plan; do not apply blindly |
| State lock stuck | Crashed apply | Confirm no Terraform process is running; use `terraform force-unlock <lock-id>` only then |

---

## 13. End of Day 2

Reply with exactly:

```text
EOD
```

Day 3 will build the spokes, AKS, App Service, APIM, SQL, Redis, Blob, Service Bus, Functions, ACR, and the Ansible baseline. Do not start those today.
