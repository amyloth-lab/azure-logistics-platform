# Day 3B - Compute and Edge Checkpoints

**Status:** Checkpoint 1 code added; AKS apply pending.
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

### Resources

- APIM Standard v2.
- Inbound private endpoint in `snet-private-endpoints`.
- Outbound VNet integration in `snet-apim-outbound` (already delegated to `Microsoft.Web/serverFarms`).
- Public network access disabled after the private endpoint is approved.
- System-assigned managed identity.
- JWT validation policy placeholder.
- Backend to the AKS internal ingress once NGINX is installed.

### Validate

- Private endpoint approved.
- APIM default gateway resolves to the private IP from the workload VNet.
- `curl` from a pod/VM reaches APIM.
- No public APIM access.
- APIM can reach the AKS internal ingress over the private path.

Stop after checkpoint 2.

---

## Checkpoint 3 - App Service, Functions, App Gateway, Ansible

### App Service

- Linux Python plan.
- VNet integration in `snet-appservice-outbound`.
- Private endpoint in `snet-private-endpoints`.
- Public network access disabled.
- System-assigned managed identity.
- Placeholder app until Day 4.

### Functions

- Flex Consumption plan.
- VNet integration in `snet-functions-outbound`.
- Private endpoint if HTTP trigger is added; Service Bus trigger is outbound.
- System-assigned managed identity.
- Placeholder function until Day 4.

### App Gateway

- WAF_v2 in `snet-appgw`.
- Public IP and TLS listener.
- Backend pool to APIM private endpoint.
- Health probe and WAF policy.
- Only public application entry point.

### Ansible

- One management VM or two small VMs (Ansible control, self-hosted agent) in `snet-ansible`/`snet-devops-agents`.
- No public IP; Bastion only.
- Ansible installs/hardens tooling and applies the Kubernetes baseline.
- Second run must report `changed=0`.

---

## End of each checkpoint

Do not proceed to the next checkpoint until the current one has:

- A clean `terraform plan`.
- Successful `terraform apply`.
- The validation commands passing.
- A commit and tag.

At the end of the full Day 3B, reply `EOD`. Then Day 4 starts the FastAPI application, Entra auth/RBAC, tests, and the build pipeline.
