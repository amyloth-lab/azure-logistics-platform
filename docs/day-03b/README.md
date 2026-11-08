# Day 3B - Compute and Edge Checkpoints

**Status:** Day 3B complete with documented gaps. AKS, APIM, and Functions are running. App Service, the public edge, and the Ansible VM are deferred/disabled.
**Purpose:** Build the remaining platform services without turning one day into an unsafe mega-apply.
**Rule:** Do one checkpoint, validate it, then ask for the next. Do not apply all three at once.

> Read [PROJECT-STATE.md](../PROJECT-STATE.md) first. It contains the Day 1-3A decisions, fixes, and current state.

---

## Why this is checkpointed

Day 3B contains AKS, APIM, App Service, Functions, App Gateway, and Ansible. Each has failure modes that look like unrelated problems:

- AKS private DNS and subnet/NSG requirements.
- APIM Standard v2 inbound private endpoint plus outbound integration.
- App Service private endpoint and VNet integration.
- Functions Flex Consumption networking.
- App Gateway WAF backend/TLS/probe behavior.
- Ansible SSH/Bastion and idempotence.

A single apply makes it hard to tell which component broke. Build one layer, validate it, then move on.

---

## Checkpoint 1 - AKS private cluster

**Goal:** A private AKS cluster with system and user node pools, Azure CNI Overlay, workload identity, OIDC issuer, Entra RBAC, internal ingress capability, and ACR pull.

### Decision: use the existing private DNS zone

Chosen: **existing zone**, not `System`.

The implementation creates a user-assigned identity for AKS and grants it:

- `Private DNS Zone Contributor` on `privatelink.australiaeast.azmk8s.io`
- `Network Contributor` on `vnet-workload-dev`

The cluster receives the existing zone ID.

### Code already added

- `infra/terraform/modules/aks/` - cluster, node pool, identity, role assignments, AcrPull.
- `infra/terraform/envs/dev/main.tf` - `module "aks"` wiring.
- Firewall rule collection group `aks-egress` for AKS egress to MCR, AKS FQDN tag, Entra, Ubuntu, and NTP.
- No new subnet, no public IP on nodes.

The configuration passed `terraform validate` in a clean copy without the remote backend.

### Apply

```powershell
cd "C:\Users\OEM\Documents\deepseek-harness\default-workspace\infra\terraform\envs\dev"

Remove-Item aks.tfplan -ErrorAction SilentlyContinue
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ..\..
terraform validate
terraform plan -out=aks.tfplan
terraform apply aks.tfplan
```

The AKS cluster can take 15–25 minutes. Stop if the plan shows a replacement of the hub, firewall, ACR, Key Vault, or data services.

### Validate without a public API server

`az aks get-credentials` from your laptop will write a private FQDN that your laptop cannot reach. Use AKS run command instead:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl get nodes -o wide"
```

Expected: two nodes, `Ready` — one system, one user.

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl get pods -A"
```

Check the cluster shape:

```powershell
az aks show `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --query "{private:apiServerAccessProfile.enablePrivateCluster,oidc:oidcIssuerProfile.enabled,workloadIdentity:securityProfile.workloadIdentity.enabled,nodePools:agentPoolProfiles[].name}" `
  --output json
```

Expected: private `true`, OIDC `true`, workload identity `true`, node pools `system` and `user`.

### If `kubectl` returns `Forbidden: nodes is forbidden`

Entra authentication succeeded, but the user has no Kubernetes RBAC role. The environment now includes:

```hcl
resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

Apply it:

```powershell
terraform plan -out=aks-rbac.tfplan
terraform apply aks-rbac.tfplan
```

Wait 2–5 minutes for the role assignment to propagate, then retry:

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev --command "kubectl get nodes -o wide"
```

This is a **lab convenience** role. In production, assign it to a group with a manual JIT process, not to every engineer permanently.

### Acceptance

- [ ] Cluster is private.
- [ ] Both node pools Ready.
- [ ] OIDC issuer enabled.
- [ ] Workload identity enabled.
- [ ] ACR pull works for a test pod.
- [ ] No public IP on nodes.
- [ ] `az aks command invoke` works, or a management VM/Bastion path is ready.

Commit and tag:

```powershell
git add infra\terraform docs\day-03b docs\PROJECT-STATE.md
git commit -m "feat(day-3b): add private AKS cluster"
git tag -a day-3b-aks -m "Day 3B checkpoint 1: private AKS"
git push origin main --tags
```

Stop after checkpoint 1 and report the result. Do not start APIM yet.

---

## Checkpoint 2 - APIM Standard v2

**Goal:** Private APIM gateway with outbound integration to the workload VNet.

### Code added

- `infra/terraform/modules/apim/`
- APIM Standard v2 (`StandardV2_1`), system-assigned identity.
- Inbound private endpoint in the workload private endpoint subnet.
- Private Link group ID **`Gateway`** (capital G; lowercase fails).
- Private DNS zone `privatelink.azure-api.net`.
- `azapi_update_resource` to set:
  - `publicNetworkAccess = "Disabled"`
  - `virtualNetworkConfiguration.subnetResourceId = snet-apim-outbound`
  - `virtualNetworkType = "External"` (Standard v2 outbound integration; `None` is rejected when a subnet is supplied, and `Internal` is not supported on v2)
- Env wiring and outputs.

This uses `azapi` because the current `azurerm_api_management` resource does not expose the Standard v2 outbound integration or the gateway public-access switch. The classic `virtual_network_configuration` block is deprecated and is not the v2 outbound integration.

`terraform validate` passes. It has not been applied.

### Apply

```powershell
cd "C:\Users\OEM\Documents\deepseek-harness\default-workspace\infra\terraform\envs\dev"

Remove-Item apim.tfplan -ErrorAction SilentlyContinue
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=apim.tfplan
terraform apply apim.tfplan
```

APIM Standard v2 can take 30–60 minutes.

Stop if the plan shows a replacement of AKS, the hub, firewall, ACR, Key Vault, or data services.

### If the `azapi_update_resource` fails

The possible failure points are:

1. **Private endpoint not approved yet** — approve the APIM private endpoint connection, then re-apply.
2. **`virtualNetworkType = "None"` rejected with `cannot be 'none' when 'virtualNetworkConfiguration' is not null`** — use `virtualNetworkType = "External"` for Standard v2 outbound integration. `Internal` is not supported on Standard v2.
3. **API version mismatch** — keep `Microsoft.ApiManagement/service@2024-05-01`; do not guess a preview version.

Do not switch to classic VNet injection or enable public access to work around it.

### Validate

```powershell
az apim show `
  --resource-group rg-logistics-platform-dev `
  --name <apim-name> `
  --query "{sku:sku.name,public:publicNetworkAccess,gateway:gatewayUrl,identity:identity.principalId}" `
  --output json
```

Check the private endpoint:

```powershell
az network private-endpoint list `
  --resource-group rg-logistics-platform-dev `
  --query "[?contains(name, 'apim')].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,ip:customDnsConfigs[0].ipAddresses[0]}" `
  --output table
```

Expect `Approved` and a `10.2.11.x` private IP.

Check private DNS:

```powershell
az network private-dns record-set a list `
  --resource-group rg-logistics-platform-dev `
  --zone-name privatelink.azure-api.net `
  --output table
```

APIM cannot reach AKS until the internal ingress controller and API are deployed on Day 4. This checkpoint validates the gateway, private endpoint, public-access disable, and outbound integration configuration only.

Stop after checkpoint 2.

---

## Checkpoint 3 - App Service, Functions, App Gateway, Ansible

This checkpoint is still split. App Service is **blocked** by the subscription quota.

### 3C-1 - App Service - BLOCKED

**Blocked reason:** the subscription is ineligible for an App Service VM quota increase. Both B1 and S1 have zero App Service VM quota in `australiaeast`. Changing SKUs does not help.

**Code state:** `infra/terraform/modules/app-service/` exists and validates, but the module is disabled:

```hcl
enable_app_service = false
```

With the default false, `terraform plan` will not try to create the App Service plan and will not hit the quota error.

**Options:**

1. **Defer App Service** and host the partner webhook on AKS for now. This keeps the private network design and zero-trust data plane. It is an architecture deviation; record it in ADR-0003 and `PROJECT-STATE.md`.
2. Use a different Azure subscription with App Service quota. This is the cleanest way to keep the original App Service requirement.
3. Use a public/Free App Service plan. This breaks the private endpoint and VNet integration requirements; not recommended.

**Recommended for this lab:** option 1, then revisit if a subscription with quota becomes available.

Do not keep changing B1/S1. Do not enable `enable_app_service` until quota exists.

Continue with Functions, App Gateway, and Ansible. The partner webhook will be deployed on AKS in Day 4 as a documented deviation.

### 3C-2 - Functions

**Code added:** `infra/terraform/modules/functions/`

- Linux Flex Consumption plan (`FC1`).
- Python 3.12 function app.
- User-assigned managed identity, created before the app.
- `Storage Blob Data Contributor` on the private storage account, granted before app creation.
- Deployment package container `function-packages` created in the private storage account.
- `storage_authentication_type = "UserAssignedIdentity"`; no storage keys.
- VNet integration in `snet-functions-outbound`; route all enabled.
- Public network access disabled; no HTTP trigger needed.
- `Azure Service Bus Data Receiver` on the Premium namespace.
- App settings use managed identity:
  - `ServiceBusConnection__fullyQualifiedNamespace`
  - `ServiceBusConnection__credential=managedidentity`

**Apply:**

```powershell
cd "C:\Users\OEM\Documents\deepseek-harness\default-workspace\infra\terraform\envs\dev"

Remove-Item functions.tfplan -ErrorAction SilentlyContinue
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=functions.tfplan
terraform apply functions.tfplan
```

**Validate:**

```powershell
$func = az functionapp list `
  --resource-group rg-logistics-workload-dev `
  --query "[?contains(name, 'func-logistics')].name | [0]" `
  --output tsv

az functionapp show `
  --resource-group rg-logistics-workload-dev `
  --name $func `
  --query "{state:state,public:publicNetworkAccess,kind:kind,host:defaultHostName}" `
  --output json
```

Expected: running, public access disabled, Flex Consumption kind.

Check role assignments:

```powershell
az role assignment list `
  --scope $(az storage account show -g rg-logistics-data-dev -n <storage-name> --query id -o tsv) `
  --query "[?roleDefinitionName=='Storage Blob Data Contributor'].{principal:principalName,role:roleDefinitionName}" `
  --output table
```

The function has no deployed code yet, so `az functionapp function list` may be empty. That is expected until Day 4.

**If VNet integration fails with `SubnetMissingRequiredDelegation`:** Flex Consumption requires the subnet delegation `Microsoft.App/environments`, not `Microsoft.Web/serverFarms`. The network module now uses the correct delegation for `snet-functions-outbound`.

**If VNet integration fails with `Microsoft.App is not registered`:** Flex Consumption uses the `Microsoft.App` resource provider. Register it once and retry:

```powershell
az provider register --namespace Microsoft.App --wait
az provider show --namespace Microsoft.App --query registrationState -o tsv
```

Expected: `Registered`.

Then re-run the plan/apply. If the Function App creation failed after the subnet association started, Terraform will show the failed resource as tainted and replace it.

**If Flex plan creation hits App Service quota:** do not change SKUs repeatedly. Record the quota error and defer Functions the same way as App Service; do not weaken the private storage design.

Stop here and reply `FUNCTIONS done`.

### 3C-3 - App Gateway WAF_v2 - DEFERRED

**Status:** deferred. The public edge is disabled:

```hcl
enable_app_gateway = false
```

**Reason:** the subscription has a 3 public IP limit in `australiaeast`, already consumed by the firewall data IP, firewall management IP, and Bastion. App Gateway needs a fourth. Public IP quota is not available for this lab.

**Decision:** keep APIM private-only and demo the API from inside the workload network. Recorded in [ADR-0013](../adr/0013-defer-edge-private-only.md).

**Code retained:** `infra/terraform/modules/app-gateway/` remains in the repository for a future subscription with public IP quota. Do not set `enable_app_gateway = true` here.

**Consequences:**

- No public API endpoint.
- No WAF inspection or edge TLS termination demonstration.
- No external partner webhook reachability.
- APIM remains reachable only through its private endpoint and private DNS.
- Demo from AKS with `az aks command invoke`, or from a Bastion-connected VM.

Do not expose APIM publicly to compensate. That would discard the private-by-design control for the sake of a demo.

**Continue to Ansible.** Do not apply App Gateway.

### 3C-4 - Ansible baseline - DEFERRED

**Status:** deferred. The VM is disabled:

```hcl
enable_ansible_vm = false
```

**Reason:** Total Regional Cores quota is 4/4 in `australiaeast`; the Ansible VM needs 2 vCPUs.

**Decision:** keep the module and playbooks, do not create the VM. See [ADR-0014](../adr/0014-defer-ansible-vm.md).

**Retained code:**

- `infra/terraform/modules/ansible-vm/`
- `ansible/playbooks/baseline.yml`
- `ansible/ansible_key.pub` (public key only)

**Consequences:**

- No persistent Ansible control host.
- No VM SSH-hardening/idempotence demonstration.
- The Kubernetes baseline will be applied from AKS run command or the release pipeline, not from an Ansible VM.
- Do not shrink AKS just to free vCPU quota.

Day 3B is complete with these documented gaps:

- App Service — quota ineligible
- Public WAF edge — public IP quota
- Ansible control VM — vCPU quota

Do not create any of the deferred resources. Move to EOD.

---

## End of each checkpoint

Do not proceed to the next checkpoint until the current one has:

- A clean `terraform plan`.
- Successful `terraform apply`.
- The validation commands passing.
- A commit and tag.

At the end of the full Day 3B, reply `EOD`. Then Day 4 starts the FastAPI application, Entra auth/RBAC, tests, and the build pipeline.
