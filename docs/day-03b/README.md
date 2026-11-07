# Day 3B - Compute and Edge Checkpoints

**Status:** Not started
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

### Design decision to settle first

You already created a `privatelink.australiaeast.azmk8s.io` zone in the platform resource group. AKS private cluster can either:

- use `private_dns_zone_id = "System"` and create its own zone in the node resource group, or
- use your existing zone and give the cluster identity `Private DNS Zone Contributor`.

Do not create both and assume DNS will resolve correctly. Recommended for this project:

- Use the existing zone for consistency with the other private DNS zones.
- Create a user-assigned identity for AKS before the cluster.
- Grant that identity `Private DNS Zone Contributor` on the AKS zone and `Network Contributor` on the workload VNet if required.
- Pass the existing zone ID to AKS.

If that becomes too complex, use `System` DNS and remove the unused custom AKS zone in a separate change. Record the decision in an ADR.

### Module to add

`infra/terraform/modules/aks/`

Inputs:

- cluster name, resource group, location, DNS prefix.
- system and user subnet IDs.
- ACR ID.
- Log Analytics workspace ID.
- tenant ID.
- private DNS zone ID.
- tags.

Resources:

- `azurerm_kubernetes_cluster`:
  - private cluster, no public FQDN.
  - system-assigned or user-assigned identity.
  - Entra RBAC; local accounts disabled.
  - OIDC issuer and workload identity enabled.
  - Azure CNI Overlay: pod CIDR `100.64.0.0/16`, service CIDR `10.60.0.0/16`, DNS `10.60.0.10`.
  - outbound type `userDefinedRouting`.
  - system node pool in `snet-aks-system`.
- `azurerm_kubernetes_cluster_node_pool` user pool in `snet-aks-user`.
- `AcrPull` role assignment for the kubelet identity on the ACR.
- Optional: `oms_agent` to the Log Analytics workspace.

### Validate

```powershell
az aks show -g rg-logistics-workload-dev -n aks-logistics-dev `
  --query "{private:apiServerAccessProfile.enablePrivateCluster,oidc:oidcIssuerProfile.enabled,workloadIdentity:securityProfile.workloadIdentity.enabled}" -o table

az aks get-credentials -g rg-logistics-workload-dev -n aks-logistics-dev --overwrite-existing
kubectl get nodes -o wide
kubectl get pods -A
```

Acceptance:

- [ ] Cluster is private.
- [ ] Both node pools Ready.
- [ ] OIDC issuer enabled.
- [ ] Workload identity enabled.
- [ ] `kubectl` works from the management VNet or Bastion-connected VM.
- [ ] ACR pull works for a test pod.
- [ ] No public IP on nodes.

Stop after checkpoint 1 and report the result.

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
